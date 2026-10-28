# EXPLANATION — PayTrack DevOps Assessment

Answers to task E (design decisions, offline validation, trade-offs, unfinished
work, AI/tool usage), plus the required breakdown of how cluster, node group,
IAM and networking are configured.

---

## 1. Design decisions and assumptions

### How the cluster, node group, IAM and networking are configured

All of it lives in `infra/main.tf` and is created by one pinned module call
(`terraform-aws-modules/eks/aws`, `~> 21.29`, exact version + SHA256 checksums
locked in `.terraform.lock.hcl`).

| Piece | How it is configured |
|---|---|
| **Cluster** | `module "eks"` with `name`, `kubernetes_version` from variables; API endpoint: private always on, **public off unless explicit CIDRs** (`0.0.0.0/0` rejected by variable validation); control-plane logs `api, audit, authenticator` → CloudWatch; Kubernetes secrets envelope-encrypted with a dedicated KMS key (`encryption_config`); core add-ons (`vpc-cni`, `kube-proxy`, `coredns`) managed in Terraform so a fresh cluster can actually run pods |
| **Cluster IAM role** | Created by the module: trusts `eks.amazonaws.com`, attaches `AmazonEKSClusterPolicy` (control plane calling EC2/ELB/CloudFormation on your behalf) + the KMS encryption policy. Exposed via `cluster_iam_role_name/arn` outputs |
| **Managed node group** | One group `paytrack`: `instance_types` (default `t3.medium`), `min/desired/max` = 2/2/4 (guarded by a `check` block), AL2023 AMI, labels `workload: paytrack-api`, placed in the **private subnets passed as input** → nodes get no public IPs |
| **Node IAM role** | Created by the module: trusts `ec2.amazonaws.com`, attaches worker-node, CNI and ECR-read policies. Exposed via `node_iam_role_name/arn` outputs |
| **Who may administer** | EKS **access entries** (not `aws-auth` ConfigMap edits): empty by default, `platform_admin_role_arns` gains `AmazonEKSClusterAdminPolicy`. `enable_cluster_creator_admin_permissions = false` → even the identity running `terraform apply` gets no implicit admin |
| **IRSA** | Module creates the IAM OIDC provider (`oidc_provider_arn` output) so pods can assume IAM roles via service accounts later — no static AWS keys anywhere in the repo |
| **Networking** | No VPC code at all: `vpc_id` + `private_subnet_ids` are required inputs (platform team owns the network). Assumption: ≥2 private subnets in ≥2 AZs, subnets tagged `kubernetes.io/role/internal-elb=1` if an internal LB is added later |

Hand-written equivalent of what the module does for IAM (for study — the
submission uses the maintained module):

```hcl
# what the module effectively creates for us:
resource "aws_iam_role" "cluster" {          # trust: eks.amazonaws.com
  managed_policy_arns = ["...policy/AmazonEKSClusterPolicy"]
}
resource "aws_iam_role" "node" {             # trust: ec2.amazonaws.com
  managed_policy_arns = [
    "...policy/AmazonEKSWorkerNodePolicy",
    "...policy/AmazonEKS_CNI_Policy",
    "...policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}
```

**Module choice, exact version, why** (required by task A):
`~> 21.29` → resolved `21.29.0` (published 2026-10-07, per the Registry API).
Requirements read from the module itself: Terraform `>= 1.5.7`, AWS provider
`>= 6.59`. Why a module instead of hand-written resources: a small platform
team gets upstream-reviewed IAM least-privilege policies and security fixes
without maintaining them; the assessment still demands the above table so the
abstraction stays inspectable. Alternative (hand-writing every resource) was
considered — better for learning, worse for maintenance; documented instead of
implemented.

### Kubernetes decisions (`k8s/manifests.yaml`)

- **Readiness/liveness/startup probes** on the real endpoints (`/ready`,
  `/health` from `app/app.py`): with a startup-dependent app (see
  `troubleshooting/`), startupProbe replaces guessed `initialDelaySeconds`.
- **securityContext**: non-root UID **10000** (high UID avoids host conflicts),
  `seccompProfile: RuntimeDefault`, all capabilities dropped, no privilege
  escalation, read-only root filesystem (+ `emptyDir` on `/tmp`),
  `automountServiceAccountToken: false` (the API never talks to the Kubernetes
  API).
- **No NetworkPolicy by design** — isolation is enforced at the AWS perimeter
  (security groups, private subnets, dedicated cluster per app); trade-off in §3.
- **ClusterIP only, no Ingress** — API is internal-only (task background).
- **ConfigMap** carries only non-sensitive config (`APP_ENV`, `PORT`); anything
  secret would go to a Secret + IAM-backed store, never a ConfigMap.

### CI decisions (`.github/workflows/validate.yaml`)

- `on: pull_request` only, top-level `permissions: contents: read` (least
  privilege — validation needs nothing else).
- Three independent jobs fail fast and clearly: `terraform fmt/init -backend=false/validate`,
  `kubeconform -strict`, `checkov` (Terraform **and** Kubernetes manifests).
- Tool versions pinned: Terraform 1.17.0, kubeconform 0.6.7, checkov 3.3.30.
- Validation is a **separate workflow from deployment** by design.

### Deployment (optional task — documented, not implemented)

No deploy job ships because no live credentials/cluster exist for this
assessment. The intended design: GitHub OIDC → `aws:role` with
`token.actions.githubusercontent.com` sub conditioned on one repo+branch
(environment `production`), **no long-lived AWS keys**, GitHub Environment
protection requiring 1 reviewer, short session duration (1h), and the deploy
job separate from the validation workflow above.

### Key assumptions (explicit)

1. Platform team owns VPC/subnets and provides their IDs + admin role ARNs as inputs.
2. `terraform apply` (future) runs from a network position allowed to reach the
   API endpoint — VPN/bastion/CI-in-VPC when public endpoint is disabled.
3. `kubernetes_version` placeholder in `terraform.tfvars.example` must be
   confirmed against currently supported EKS versions at apply time.
4. The container image is built elsewhere; repo holds an explicit tag
   (`paytrack-api:1.0.0`), registry address is a placeholder.
5. Troubleshooting incident cluster is a dedicated/paytrack-only cluster
   (drives the perimeter-first isolation stance).

---

## 2. How this is validated without creating cloud resources

| Command | What it proves | Where it runs |
|---|---|---|
| `terraform fmt -check -recursive -diff` | canonical formatting | CI + locally |
| `terraform init -backend=false` | providers/modules resolve; version constraints satisfiable — **no state, no AWS calls** | CI + locally |
| `terraform validate` | config/schema correctness incl. module inputs | CI + locally, green |
| `checkov -d infra --skip-path .terraform` | IaC security policies; 1 documented skip (`CKV_TF_1`) | CI + locally, green |
| `kubeconform -strict -summary k8s/*.yaml` | exact Kubernetes schema, rejects unknown fields | CI + locally, green |
| `checkov -d k8s --framework kubernetes --skip-check CKV_K8S_43,CKV2_K8S_6` | workload security policies; skips are written decisions (§3) | CI + locally, green |

`terraform plan/apply` were never run (constraint: no credentials, no
resources). What that cannot catch: subnet/region values, IAM service-linked
timing, EKS version availability — all flagged as apply-time checks in
`infra/README` notes and assumptions above.

---

## 3. Key security and operational trade-offs

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| API endpoint | private-only default, public only with explicit CIDRs | `0.0.0.0/0` | internal admin API should not face the internet; cost: apply/kubectl must run from inside the network |
| Cluster admin | explicit access entries per role ARN | cluster-creator admin / `aws-auth` edits | auditable, API-managed, revocable by deleting an entry; cost: one-time setup of role ARNs |
| Module pinning | registry semver + lockfile checksums (Checkov `CKV_TF_1` skipped *with reason*) | git SHA pinning | registry verifies integrity; SHA pins hide upstream releases — real debate, documented not hidden |
| Cluster-internal isolation | perimeter (SGs, private subnets, dedicated cluster per app) | in-cluster NetworkPolicy | simplicity for a small team on a single-app cluster; cost: shared clusters would need NetworkPolicy — tracked as future control |
| Image reference | explicit tag in git | digest pinning (`CKV_K8S_43` skipped *with reason*) | digest exists only after build → belongs to CD; cost: tags are mutable → mitigate with immutable-tag convention + image scanning |
| Startup dependency check | (recommendation) retry with backoff / degraded 503 | current fail-fast abort | a dependency blip must not become a deployment outage — see `troubleshooting/DIAGNOSIS.md` |
| Secrets | KMS envelope encryption | AWS-managed default key | own key policy + rotation control, negligible cost at this scale |
| Node sizing | 2× t3.medium, max 4 | 1 node / bigger fleet | 2 nodes = AZ + rollout headroom; scale ceiling exists, HPA/PDB not in scope |

---

## 4. What was not finished, and why

1. **Deploy automation** (optional per assessment) — documented as design above;
   time-boxed to protect deliverables due tonight; also avoids defending a
   second IAM surface live.
2. **State backend (S3 + DynamoDB lock)** — environment-specific and owned by
   the platform team; omitted deliberately so `init -backend=false` works
   credential-free (comment in `versions.tf` explains).
3. **tflint / image vulnerability scan / HPA + PDB** — nice next gates, not
   required; prioritized required checks first (assessment explicitly rewards
   prioritization over control count).
4. **Live `terraform plan`** — impossible without credentials (constraint), so
   applies-time assumptions are listed in §1 instead.
5. **EKS version placeholder** — intentionally not guessed; must be confirmed
   against the region's supported versions at apply time.

---

## 5. Use of AI and other tools

- **Assistant (OpenCode agent)** drafted and reviewed artifacts with me
  driving; **every file was read and pushed by me**, and the assistant was used
  in explain-mode so each decision could be defended here.
- **Tools run locally**: `terraform 1.17.0` (fmt/init/validate), `checkov 3.3.30`
  (venv), `kubeconform 0.6.7` (pinned binary), `git`/`gh` CLI.
- **Verified suggestion (assistant accepted after checking):** `terraform init
  -backend=false` + `terraform validate` as the no-cloud CI gate — I ran the
  exact CI commands locally before enabling the workflow.
- **Changed suggestion:** the assistant initially added an in-cluster
  `NetworkPolicy`; I rejected it in favour of perimeter-level isolation
  (dedicated cluster per app) — the CI skip now carries that reasoning
  instead of silently dropping the check.
- **Rejected suggestion:** the assistant first wrote the EKS module from a
  **stale v20 interface** (`cluster_name`, `cluster_version`, dynamic
  `access_entry` blocks). `terraform init` failed with 7 errors; we pulled the
  module's real v21 interface (Registry API + the downloaded module's own
  `variables.tf`/README) and rewrote it. Tooling caught the hallucination;
  human review confirmed the rewrite. *(Good example of why the offline gate
  exists.)*
- **Tested, not assumed:** probe behaviors were validated against Checkov
  empirically (e.g. `runAsUser: 1000` fails its high-UID check, `10000`
  passes; inline `#checkov:skip` works in Terraform blocks but not in k8s YAML
  — hence CI-level skips with written justification).
