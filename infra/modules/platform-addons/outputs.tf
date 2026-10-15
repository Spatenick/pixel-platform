output "container_log_group" {
  value = aws_cloudwatch_log_group.containers.name
}

output "argocd_namespace" {
  value = helm_release.argo_cd.namespace
}

output "grafana_service" {
  description = "kubectl -n monitoring port-forward svc/<this> 3000:80"
  value       = "kube-prometheus-stack-grafana"
}

output "releases" {
  value = {
    aws_load_balancer_controller = helm_release.aws_load_balancer_controller.version
    external_secrets             = helm_release.external_secrets.version
    keda                         = helm_release.keda.version
    kube_prometheus_stack        = helm_release.kube_prometheus_stack.version
    argo_cd                      = helm_release.argo_cd.version
  }
}
