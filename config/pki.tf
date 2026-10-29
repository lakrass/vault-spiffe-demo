resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "X.509-SVID issuer for the local SPIFFE demo"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 31536000
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Vault SPIFFE Demo CA"
  ttl         = "8760h"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_role" "workload" {
  for_each = local.workloads

  backend          = vault_mount.pki.path
  name             = each.key
  issuer_ref       = vault_pki_secret_backend_root_cert.root.issuer_id
  ttl              = 3600
  max_ttl          = 3600
  require_cn       = false
  allow_ip_sans    = false
  allowed_uri_sans = ["spiffe://${local.trust_domain}/${each.value}"]
  key_type         = "ec"
  key_bits         = 256
  key_usage        = ["DigitalSignature"]
  client_flag      = true
  server_flag      = true
  no_store         = true
}