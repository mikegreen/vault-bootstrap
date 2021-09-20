
provider "vault" {
  alias     = "new"
  namespace = var.new-namespace
}

provider "vault" {
  alias = "vault-root"
}

resource "vault_namespace" "new-namespace" {
  provider = vault.vault-root
  path     = var.new-namespace
}

# Create a token with the admin-namespace-only policy
resource "vault_token" "namespace-admin-token" {
  provider = vault.new
  ttl      = "1h"
  policies = [vault_policy.admin-policy.name]
  depends_on = [
    vault_policy.admin-policy
  ]
}

# Create a token that can only manage secrets 
resource "vault_token" "namespace-secrets-manager-token" {
  provider = vault.new
  ttl      = "8h"
  policies = [vault_policy.secrets-manager-policy.name]
  depends_on = [
    vault_policy.secrets-manager-policy
  ]
}

resource "vault_mount" "all_the_secrets" {
  depends_on = [vault_namespace.new-namespace]
  provider   = vault.new
  for_each   = toset(var.secrets_to_mount)
  type       = each.key
  path       = "${var.path-prefix}-${each.key}"
}

resource "vault_mount" "shared_secrets" {
  depends_on = [vault_namespace.new-namespace]
  provider   = vault.new
  type       = "kv"
  path       = "${var.path-prefix}-shared"
}

resource "vault_auth_backend" "all_the_auths" {
  depends_on = [vault_namespace.new-namespace]
  provider   = vault.new
  for_each   = toset(var.auths_to_mount)
  type       = each.key
  path       = each.key
  tune {
    default_lease_ttl = "6h"
    max_lease_ttl     = "24h"
  }
}

resource "vault_auth_backend" "userpass" {
  depends_on = [vault_namespace.new-namespace]
  provider   = vault.new
  type       = "userpass"
  path       = "userpass"
}

# Add rate limit of 100/sec across namespace to protect noisy neighbor issues
resource "vault_quota_rate_limit" "namespace-wide-quota" {
  depends_on = [vault_namespace.new-namespace]
  # From https://www.vaultproject.io/api/system/rate-limit-quotas#parameters
  name = "${var.new-namespace}-wide-quota"
  path = "${var.new-namespace}/"
  rate = var.namespace-rate-limit
  # provider 2.19.1 does not yet support interval/block_interval
  # see https://github.com/hashicorp/terraform-provider-vault/issues/1049
  # interval = "5s"
  # block_interval = "5s"
}

# # Assuming the kv mount is enabled, add a secret into the KV engine just created
# # Note, we need depends_on because TF does not know if this mount exists yet
# resource "vault_generic_secret" "secret" {
#   provider   = vault.new
#   depends_on = [vault_mount.all_the_secrets]
#   path       = "kv/first-secret"
#   data_json  = <<EOT
#     {
#       "foo":  "bar",
#       "pizza": "cheesey"
#     }
#     EOT
# }

# Create PKI mount 
resource "vault_mount" "pki-benchmarking" {
  depends_on                = [vault_namespace.new-namespace]
  provider                  = vault.new
  path                      = "pki-benchmarking"
  type                      = "pki"
  description               = "Mount PKI at its own path as not to break anything existing"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 2592000
}

# Create role for PKI 
resource "vault_pki_secret_backend_role" "example_pki" {
  provider         = vault.new
  backend          = vault_mount.pki-benchmarking.path
  name             = "example_pki"
  ttl              = 180
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 4096
  allowed_domains  = ["example.com", "my.domain"]
  allow_subdomains = true
  key_usage        = ["DigitalSignature", "KeyAgreement", "KeyEncipherment"]
}

# Generate self-signed internal CA
resource "vault_pki_secret_backend_root_cert" "example" {
  # depends_on = [vault_mount.pki-benchmarking]

  provider = vault.new
  backend  = vault_mount.pki-benchmarking.path

  type                 = "internal"
  common_name          = "Root CA"
  ttl                  = "315360001"
  format               = "pem"
  private_key_format   = "der"
  key_type             = "rsa"
  key_bits             = 4096
  exclude_cn_from_sans = true
  ou                   = "HashiCorp, greenacreslimited"
  # organization         = "My organization"
}

# Create a certificate to make sure above all works
resource "vault_pki_secret_backend_cert" "app" {
  # need a depends on for the first run, as TF will try to create this before the above is done
  depends_on = [vault_pki_secret_backend_root_cert.example]

  provider = vault.new
  backend  = vault_mount.pki-benchmarking.path

  name        = vault_pki_secret_backend_role.example_pki.name
  common_name = "app.my.domain"
}

# create a transit mount for Boundary to use as KMS
# if create-boundary-transit = true
# TODO - move this into its own module
resource "vault_mount" "transit-boundary" {
  depends_on = [vault_namespace.new-namespace]
  count      = var.create-boundary-transit ? 1 : 0
  provider   = vault.new

  path        = "transit-boundary"
  type        = "transit"
  description = "Transit secret mount for Boundary to use as KMS"
}

resource "vault_transit_secret_backend_key" "root" {
  count    = var.create-boundary-transit ? 1 : 0
  provider = vault.new

  backend          = vault_mount.transit-boundary[count.index].path
  name             = "boundary-root"
  type             = "rsa-4096"
  deletion_allowed = true
}

resource "vault_transit_secret_backend_key" "worker-auth" {
  count    = var.create-boundary-transit ? 1 : 0
  provider = vault.new

  backend          = vault_mount.transit-boundary[count.index].path
  name             = "boundary-worker-auth"
  type             = "aes256-gcm96"
  deletion_allowed = true
}

# For demo/lazy purposes, we'll create this policy and the token blindly even if boundary isnt in play
resource "vault_policy" "transit-boundary" {
  count = var.create-boundary-transit ? 1 : 0

  provider = vault.new
  name     = "${var.new-namespace}-transit-policy"
  policy   = data.vault_policy_document.transit-boundary.hcl
}

# Create a token for boundary
resource "vault_token" "boundary" {
  count = var.create-boundary-transit ? 1 : 0

  depends_on   = [vault_policy.transit-boundary]
  provider     = vault.new
  ttl          = "24h"
  policies     = [vault_policy.transit-boundary[count.index].name]
  display_name = "Boundary-token"

  renew_min_lease = 3600
  renew_increment = 3600
}


# Create a token for boundary
resource "vault_token" "short-ttl" {
  provider         = vault.new
  ttl              = "60s"
  policies         = [vault_policy.secrets-manager-policy.name]
  depends_on       = [vault_policy.secrets-manager-policy]
  explicit_max_ttl = "8760h"
  renew_min_lease  = 30
  renew_increment  = 45
}
