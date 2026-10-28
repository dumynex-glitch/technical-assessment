output "cluster_name" {
  description = "EKS cluster name (use with `aws eks update-kubeconfig`)."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (sensitive)."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Cluster security group ID (created by EKS)."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN — used for IRSA (pods assuming IAM roles). Not used by the API yet, created as a safe default."
  value       = module.eks.oidc_provider_arn
}

output "eks_managed_node_groups" {
  description = "Map of managed node group attributes (name, ARN, status)."
  value       = module.eks.eks_managed_node_groups
}
