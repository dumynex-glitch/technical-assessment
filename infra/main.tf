provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    Project     = "paytrack"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "devops-assessment"
  }

  # Cluster admin access via EKS access entries instead of editing the
  # aws-auth ConfigMap. Nobody is admin until a role ARN is passed in.
  cluster_admin_access_entries = {
    for arn in var.platform_admin_role_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# Module choice and version rationale: EXPLANATION.md (also required by the
# assessment: "explain the version and why you chose it").
# Exact version is locked in .terraform.lock.hcl after `terraform init`.
module "eks" {
  #checkov:skip=CKV_TF_1: pinned via registry semver + .terraform.lock.hcl exact SHA256 checksums; trade-off documented in EXPLANATION.md
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Networking is borrowed from the platform team's VPC: no VPC resources here.
  # Control plane ENIs and worker nodes both live in the private subnets.
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # API endpoint access (justification lives on the variables):
  # private endpoint always on; public endpoint only when explicit CIDRs given.
  endpoint_private_access      = true
  endpoint_public_access       = length(var.cluster_endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Explicit: no implicit admin. The identity running `terraform apply` does NOT
  # become cluster admin; admins are listed via var.platform_admin_role_arns.
  enable_cluster_creator_admin_permissions = false
  access_entries                           = local.cluster_admin_access_entries

  # Envelope encryption of Kubernetes secrets with a dedicated KMS key
  # (module creates the key, sets up key policy + encryption policy).
  encryption_config = {
    resources = ["secrets"]
  }

  # Control-plane logs to CloudWatch: needed to answer "what happened" during
  # incidents like the 5xx scenario in troubleshooting/.
  enabled_log_types = ["api", "audit", "authenticator"]

  # Core add-ons managed by Terraform: without vpc-cni/kube-proxy/coredns a
  # fresh cluster cannot run or resolve any pods.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  # Managed node group: inherits the cluster's private subnet_ids, so nodes get
  # no public IPs. AL2023 AMI is the default from EKS 1.30 on.
  eks_managed_node_groups = {
    paytrack = {
      instance_types = var.node_instance_types
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size

      labels = {
        workload = "paytrack-api"
      }
    }
  }

  tags = local.tags
}

# Cheap static sanity check at plan/validate time, no cloud calls.
check "node_group_sizes" {
  assert {
    condition     = var.min_size <= var.desired_size && var.desired_size <= var.max_size
    error_message = "Node group sizes must satisfy min_size <= desired_size <= max_size."
  }
}
