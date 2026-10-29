resource "vault_auth_backend" "spiffe_cert" {
  type        = "spiffe"
  path        = "spiffe-cert"
  description = "Authenticate the demo workloads with X.509 SVIDs"
}

resource "vault_spiffe_auth_backend_config" "spiffe_cert" {
  mount        = vault_auth_backend.spiffe_cert.path
  trust_domain = local.trust_domain
  profile      = "static"
  bundle       = vault_pki_secret_backend_root_cert.root.certificate
}

resource "vault_spiffe_auth_backend_role" "cert_workload" {
  for_each = local.workloads

  mount                  = vault_auth_backend.spiffe_cert.path
  name                   = each.key
  workload_id_patterns   = [each.value]
  token_policies         = [vault_policy.workload[each.key].name]
  token_ttl              = 300
  token_max_ttl          = 3600
  token_explicit_max_ttl = 3600
  token_type             = "batch"

  depends_on = [vault_spiffe_auth_backend_config.spiffe_cert]
}

resource "vault_auth_backend" "spiffe_jwt" {
  type        = "spiffe"
  path        = "spiffe-jwt"
  description = "Authenticate the demo workloads with JWT SVIDs"

  tune {
    passthrough_request_headers = ["Authorization"]
  }
}

data "http" "jwt_bundle" {
  url = "${trimsuffix(var.vault_address, "/")}/v1/${vault_mount.spiffe.path}/trust_bundle/web"

  depends_on = [vault_spiffe_secret_backend_config.issuer]
}

resource "vault_spiffe_auth_backend_config" "spiffe_jwt" {
  mount        = vault_auth_backend.spiffe_jwt.path
  trust_domain = local.trust_domain
  profile      = "static"
  audience     = [local.jwt_audience]
  bundle       = data.http.jwt_bundle.response_body
}

resource "vault_spiffe_auth_backend_role" "jwt_workload" {
  for_each = local.workloads

  mount                  = vault_auth_backend.spiffe_jwt.path
  name                   = each.key
  workload_id_patterns   = [each.value]
  token_policies         = [vault_policy.workload[each.key].name]
  token_ttl              = 300
  token_max_ttl          = 3600
  token_explicit_max_ttl = 3600
  token_type             = "batch"

  depends_on = [vault_spiffe_auth_backend_config.spiffe_jwt]
}
