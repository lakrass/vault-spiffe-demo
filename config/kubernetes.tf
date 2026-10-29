resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = "kubernetes"
  description = "Bootstrap SVID issuance using Kubernetes service accounts"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt = false
}

resource "vault_kubernetes_auth_backend_role" "workload" {
  for_each = local.workloads

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = [each.key]
  bound_service_account_namespaces = ["default"]
  token_policies                   = [vault_policy.workload[each.key].name]
  token_ttl                        = 300
  token_max_ttl                    = 3600
  token_explicit_max_ttl           = 3600
  token_type                       = "batch"

  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
}

resource "vault_policy" "workload" {
  for_each = local.workloads

  name   = "spiffe-${each.key}"
  policy = <<-EOT
    path "${vault_mount.pki.path}/issue/${each.key}" {
      capabilities = ["update"]
      required_parameters = ["uri_sans"]
      allowed_parameters = {
        "uri_sans" = ["spiffe://${local.trust_domain}/${each.value}"]
        "ttl" = []
      }
    }

    path "${vault_mount.pki.path}/cert/ca" {
      capabilities = ["read"]
    }

    path "${vault_mount.spiffe.path}/role/${each.key}/mintjwt" {
      capabilities = ["update"]
      required_parameters = ["audience"]
      allowed_parameters = {
        "audience" = ["${local.jwt_audience}"]
      }
    }
  EOT
}
