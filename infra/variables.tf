variable "aws_region" {
  description = "AWS region for the EKS cluster. Configurable so the same code can target another region without edits."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as a prefix for node groups and related resources."
  type        = string
}

variable "vpc_id" {
  description = "ID of the existing VPC (managed by the platform team) where the cluster is placed."
  type        = string
}

variable "private_subnet_ids" {
  description = <<-EOT
    Private subnet IDs (managed by the platform team) for the EKS control plane ENIs
    and the managed node group. EKS requires at least two subnets in two different AZs.
    These subnets must be tagged for auto-discovery if you later add the AWS Load
    Balancer Controller: kubernetes.io/role/internal-elb = 1.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "EKS requires at least two private subnets in two different availability zones."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane. Pin explicitly; confirm it is still supported by EKS at apply time."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "environment" {
  description = "Environment name, used for tagging (e.g. sandbox, staging, production)."
  type        = string
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the Kubernetes API server over the public endpoint
    (e.g. office egress IP /33, CI runner CIDR). Empty list (default) disables the
    public endpoint entirely and keeps only the private endpoint, which requires
    running kubectl/terraform from inside the VPC (VPN, bastion, or CI runner in VPC).
    0.0.0.0/0 is deliberately not accepted here: an internal admin API should not be
    open to the internet. Use it only with a written justification.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.cluster_endpoint_public_access_cidrs : c != "0.0.0.0/0"])
    error_message = "Public endpoint access from 0.0.0.0/0 is not allowed. Use the private endpoint or a specific CIDR."
  }
}

variable "platform_admin_role_arns" {
  description = <<-EOT
    IAM role ARNs granted cluster-admin via EKS access entries (no permanent
    aws-auth ConfigMap entries). Empty by default: nobody gets admin until a role
    is explicitly listed here. These roles must already exist (platform team).
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
