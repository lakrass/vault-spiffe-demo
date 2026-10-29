resource "vault_mount" "spiffe" {
  path        = "spiffe"
  type        = "spiffe"
  description = "JWT-SVID issuer for the local SPIFFE demo"
}

resource "vault_spiffe_secret_backend_config" "issuer" {
  mount                 = vault_mount.spiffe.path
  trust_domain          = local.trust_domain
  key_lifetime          = "24h"
  bundle_refresh_hint   = "1h"
  jwt_signing_algorithm = "RS256"
}

resource "vault_spiffe_secret_backend_role" "workload" {
  for_each = local.workloads

  mount = vault_mount.spiffe.path
  name  = each.key
  ttl   = "5m"
  template = jsonencode({
    sub = "spiffe://${local.trust_domain}/${each.value}"
  })

  depends_on = [vault_spiffe_secret_backend_config.issuer]
}