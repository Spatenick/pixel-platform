################################################################################
# Cluster add-ons installed by Terraform (the "platform layer").
#
# Rule of thumb used in this repo:
#   Terraform installs things that need AWS resources/IAM wired to them, or
#   that everything else depends on (CRDs). Argo CD then owns application
#   workloads from Git. See docs/adr/0007-terraform-vs-argocd-boundary.md.
#
# Every release waits for the AWS Load Balancer Controller first: it registers
# admission webhooks, and installing other charts while those webhooks have
# no endpoints is a classic flaky-first-apply failure.
################################################################################

locals {
  dns_enabled = var.domain_name != ""

  repos = {
    eks_charts   = "https://aws.github.io/eks-charts"
    metrics      = "https://kubernetes-sigs.github.io/metrics-server/"
    eso          = "https://charts.external-secrets.io"
    external_dns = "https://kubernetes-sigs.github.io/external-dns/"
    keda         = "https://kedacore.github.io/charts"
    prometheus   = "https://prometheus-community.github.io/helm-charts"
    argo         = "https://argoproj.github.io/argo-helm"
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = local.repos.eks_charts
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions.aws_load_balancer_controller
  namespace  = local.sa.lbc.namespace
  timeout    = 600

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = var.ha_addons ? 2 : 1
    serviceAccount = {
      create = true
      name   = local.sa.lbc.name
    }
    # We only use ALB Ingress, not LoadBalancer Services, so skip the
    # Service mutating webhook entirely (one less thing to break installs).
    enableServiceMutatorWebhook = false
  })]

  depends_on = [aws_eks_pod_identity_association.lbc]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = local.repos.metrics
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  namespace  = "kube-system"

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = local.repos.eso
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets
  namespace        = local.sa.eso.namespace
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      create = true
      name   = local.sa.eso.name
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_pod_identity_association.eso,
  ]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = local.repos.keda
  chart            = "keda"
  version          = var.chart_versions.keda
  namespace        = local.sa.keda.namespace
  create_namespace = true
  timeout          = 600

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_pod_identity_association.keda,
  ]
}

resource "helm_release" "external_dns" {
  count = local.dns_enabled ? 1 : 0

  name             = "external-dns"
  repository       = local.repos.external_dns
  chart            = "external-dns"
  version          = var.chart_versions.external_dns
  namespace        = local.sa.externaldns.namespace
  create_namespace = true

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress"]
    domainFilters = [var.domain_name]
    policy        = "sync"
    registry      = "txt"
    txtOwnerId    = var.cluster_name
    serviceAccount = {
      create = true
      name   = local.sa.externaldns.name
    }
    env = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_pod_identity_association.externaldns,
  ]
}

# Environment-specific glue between Terraform and the apps: a gp3
# StorageClass, the ClusterSecretStore, the ConfigMap of infra outputs, and the
# ExternalSecret for the DB password. See charts/platform-glue.
resource "helm_release" "platform_glue" {
  name             = "platform-glue"
  chart            = "${path.module}/charts/platform-glue"
  namespace        = var.app_namespace
  create_namespace = true

  values = [yamlencode({
    storageClass = {
      create    = true
      name      = "gp3"
      isDefault = true
    }
    clusterSecretStore = {
      name   = "aws-secrets-manager"
      region = var.region
    }
    infraConfig = {
      name = "pixelpipe-infra"
      data = var.app_config
    }
    databaseSecret = {
      name      = "pixelpipe-db"
      remoteKey = var.db_secret_arn
    }
  })]

  depends_on = [helm_release.external_secrets]
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = local.repos.prometheus
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900

  values = concat([yamlencode({
    # EKS manages the control plane, so these endpoints can't be scraped.
    # Leaving them on just produces permanent TargetDown alerts.
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    grafana = {
      sidecar = {
        dashboards = {
          enabled         = true
          searchNamespace = "ALL"
        }
      }
    }

    prometheus = {
      prometheusSpec = {
        # Pick up ServiceMonitors/PrometheusRules from every namespace, not
        # just ones labelled with this Helm release.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        retention                               = var.prometheus_retention
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "2Gi" }
        }
      }
    }
    })],
    # Second values document, only when persistence is on (Helm merges them).
    var.prometheus_persistence_enabled ? [yamlencode({
      prometheus = {
        prometheusSpec = {
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = var.prometheus_storage_size } }
              }
            }
          }
        }
      }
    })] : []
  )

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.platform_glue, # gp3 StorageClass
  ]
}

resource "helm_release" "aws_for_fluent_bit" {
  name             = "aws-for-fluent-bit"
  repository       = local.repos.eks_charts
  chart            = "aws-for-fluent-bit"
  version          = var.chart_versions.aws_for_fluent_bit
  namespace        = local.sa.fluentbit.namespace
  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      create = true
      name   = local.sa.fluentbit.name
    }
    cloudWatchLogs = {
      enabled         = true
      region          = var.region
      logGroupName    = aws_cloudwatch_log_group.containers.name
      logStreamPrefix = "${var.environment}-"
      autoCreateGroup = false
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_pod_identity_association.fluentbit,
  ]
}

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = local.repos.argo
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd
  namespace        = "argocd"
  create_namespace = true
  timeout          = 900

  values = [yamlencode({
    configs = {
      params = {
        # TLS is terminated by kubectl port-forward / an ALB in front, not
        # inside the pod.
        "server.insecure" = true
      }
    }
    dex           = { enabled = false }
    notifications = { enabled = false }

    controller = {
      metrics = { enabled = true, serviceMonitor = { enabled = true } }
    }
    server = {
      metrics = { enabled = true, serviceMonitor = { enabled = true } }
    }
    repoServer = {
      metrics = { enabled = true, serviceMonitor = { enabled = true } }
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.kube_prometheus_stack, # ServiceMonitor CRD
  ]
}

# The "app of apps": one Argo CD Application pointing at gitops/envs/<env>/,
# which in turn contains an Application per workload.
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root-app"
  repository = local.repos.argo
  chart      = "argocd-apps"
  version    = var.chart_versions.argocd_apps
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      "${var.environment}-root" = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_path
          directory      = { recurse = false }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [
    helm_release.argo_cd,
    helm_release.keda,
    helm_release.platform_glue,
    helm_release.metrics_server,
    helm_release.aws_for_fluent_bit,
    helm_release.external_dns,
  ]
}
