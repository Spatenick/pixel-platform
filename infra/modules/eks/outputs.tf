output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_security_group_id" {
  description = "EKS-managed security group attached to the control plane and managed nodes (and therefore pods)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "node_group_name" {
  value = aws_eks_node_group.default.node_group_name
}

output "pod_identity_trust_policy" {
  description = "Reusable trust policy JSON for EKS Pod Identity roles."
  value       = local.pod_identity_trust
}

# A handle other modules can depend on to know "the cluster has nodes and
# DNS", i.e. it's ready for Helm installs.
output "ready" {
  value = {
    node_group = aws_eks_node_group.default.id
    coredns    = aws_eks_addon.coredns.id
    ebs_csi    = aws_eks_addon.ebs_csi.id
  }
}
