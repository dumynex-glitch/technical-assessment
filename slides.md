---
marp: true
theme: default
paginate: true
---

# PayTrack — DevOps Assessment

**Decisions, trade-offs, assumptions**
Technical discussion · dumynex-glitch

<!-- Presenter note: 30 min content, last 15 min = our questions to the team -->

---

# What was delivered

- **`infra/`** — EKS cluster + managed node group, Terraform, offline-validated
- **`k8s/`** — Namespace, Deployment, Service, ConfigMap, hardening per scanner
- **`.github/workflows/validate.yaml`** — PR-only validation, 3 jobs, least privilege
- **`troubleshooting/`** — evidence-based 5xx diagnosis
- **`EXPLANATION.md`** — decisions, trade-offs, AI usage disclosure
- **CI evidence** — all 3 jobs green on GitHub-hosted runners (PR #1)

---

# Architecture (what exists vs what I wrote)

```
[platform team]                [this assessment]
existing VPC ──────────────► infra/ : terraform-aws-modules/eks ~>21.29
  private subnets (≥2 AZ)         ├─ cluster (private endpoint default)
  security groups                 ├─ IAM roles (cluster + node), OIDC/IRSA
                                  └─ managed node group (2× t3.medium, private)
                                k8s/ : paytrack ns → Deployment → ClusterIP
                                CI : PR → fmt/validate + kubeconform + checkov
```

No VPC code, no state backend, no `terraform apply` — constraints respected.

---

# Infra decisions

- **Module `~> 21.29`** (resolved 21.29.0, registry + lockfile checksums) —
  small team, upstream-reviewed IAM policies, security fixes for free
- **Version requirements read from the module itself**: TF ≥1.5.7, AWS ≥6.59
- **API endpoint**: private only by default; public needs explicit CIDRs;
  `0.0.0.0/0` rejected *by variable validation*, not by convention
- **No backend block** on purpose → `init -backend=false` works credential-free
- **Assumption flagged**: confirm EKS version support at apply time

---

# IAM (the core of the answer)

| Control | Choice |
|---|---|
| Cluster role | `eks.amazonaws.com` trust + `AmazonEKSClusterPolicy` (module) |
| Node role | `ec2.amazonaws.com` trust + worker/CNI/ECR-read (module) |
| Admin access | **EKS access entries**, role ARN list, default **empty** |
| Apply identity | `enable_cluster_creator_admin_permissions = false` — **no implicit admin** |
| Pod → AWS | OIDC provider created (IRSA); zero static keys anywhere |
| Secrets | KMS envelope encryption, own key policy |

Story: *who can do what, proven by what, revocable how*.

---

# Kubernetes controls (prioritized)

- **Probes**: readiness `/ready`, liveness `/health`, **startupProbe** budget —
  learned directly from the incident (`Running ≠ Ready ≠ serving`)
- **securityContext**: non-root UID 10000, seccomp RuntimeDefault, drop ALL,
  read-only rootfs, no privilege escalation, **no SA token mount**
- **ClusterIP only** — internal API, no Ingress
- **ConfigMap** = non-sensitive only
- **NetworkPolicy: deliberately omitted** — perimeter isolation (SGs, private
  subnets, dedicated cluster per app); checkov skip carries the reasoning
  (cost note: dedicated cluster = $0.10/h control plane)

---

# CI: validation separate from deployment

- `on: pull_request` · top-level `permissions: contents: read`
- **Terraform**: `fmt -check` → `init -backend=false` → `validate`
- **kubeconform v0.6.7** `-strict` (unknown fields rejected)
- **checkov 3.3.30** — Terraform *and* manifests; 3 skips total, each with a
  written justification in code (no silent green)
- Pinned tool versions; deploy job **not shipped** — documented OIDC design:
  sub-conditioned role, environment reviewers, 1 h sessions, no long-lived keys
- **Evidence**: 3/3 jobs green on GitHub runners (PR #1)

---

# Troubleshooting: the 5xx incident

- **Evidence chain**: 5xx at 10:08 vs release 10:05 → readiness 503 →
  `startup_check unavailable` → `server startup aborted` → BackOff →
  rollout stuck, previous image still available
- **Leading hypothesis**: fail-fast startup check + unreachable downstream →
  crash-looping new pods, never Ready; endpoint churn → intermittent 5xx
- **Discriminators**: `--previous` logs, exit codes, `get endpoints`,
  in-cluster curl (timeout = network, refused = app down), `kubectl top`
- **Rollback rule**: impact first — stuck > rollout timeout or 5xx > 5 min →
  `rollout undo` now, root cause after (previous image available = cheap)
- **Preventive #1**: startupProbe + readiness reflecting *real* dependency state
  (static `/ready: true` in `app.py` tells the Service nothing)

---

# Key trade-offs (honest table)

| Chosen | Rejected | Cost of choosing |
|---|---|---|
| Private endpoint | `0.0.0.0/0` | apply/kubectl need in-VPC access |
| Semver + lockfile | SHA-pinned git source | CKV_TF_1 skipped *with reason* |
| Perimeter isolation | in-cluster NetworkPolicy | shared clusters would need it back |
| Image tags in git | digest pinning | belongs to CD — CKV_K8S_43 skipped *with reason* |
| Retry-with-backoff *(recommended)* | fail-fast abort | current app code aborts — incident root cause |

---

# Not finished (and why)

1. **Deploy automation** — optional per assessment; documented OIDC design only
   (protects time; avoids unreviewable second IAM surface)
2. **State backend** — platform-owned, env-specific; omitted so validation runs
   credential-free
3. **tflint / image scan / HPA+PDB** — next gates, not required; prioritization
   over control count (per assessment guidance)
4. **Live `terraform plan`** — impossible without credentials — assumption list
   provided instead

---

# AI usage (accountable, not decorative)

- Assistant drafted with me driving; **I read and pushed every file**
- ✅ **Verified**: `init -backend=false` + `validate` as no-cloud gate — ran the
  exact CI commands locally before enabling the workflow
- 🔄 **Changed**: assistant proposed in-cluster NetworkPolicy — I rejected it
  for perimeter isolation; the CI skip carries *my* reasoning, not silence
- ❌ **Rejected**: assistant wrote the EKS module from stale v20 API —
  `terraform init` failed with 7 errors → pulled real v21 interface from
  Registry API + module source → **tooling caught the hallucination**
- Tested, not assumed: `runAsUser: 1000` fails checkov's high-UID check,
  `10000` passes (empirically)

---

# Questions for the Kirimo team

<!-- Prepare YOUR own 4–5 — starters below, personalize before 10:00 -->

1. How is the cluster/infra split between platform and app teams today?
2. What does on-call look like — who gets paged for a 5xx like the incident?
3. Current deploy path: PR → CD on merge? Any canary/progressive delivery?
4. Where does IAM review live — IaC PR review, SCPs, or both?
5. What would your first 90 days of priorities be for me in this role?

---

# Thank you

All artifacts: `github.com/dumynex-glitch/technical-assessment` (private)
Validation evidence: PR #1 checks — 3/3 green
Discussion open — decisions above are all reversible, here's how.
