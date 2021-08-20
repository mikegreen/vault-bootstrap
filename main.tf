# main.tf

# create policies
resource "vault_policy" "admin-like" {
  name   = "admin-like-policy"
  policy = data.vault_policy_document.admin_like_policy_content.hcl
}

resource "vault_policy" "metrics" {
  name   = "metrics-policy"
  policy = data.vault_policy_document.metrics_policy_content.hcl
}

# Create a token with the admin-namespace-only policy
resource "vault_token" "admin-like" {
  ttl      = "24h"
  policies = [vault_policy.admin-like.name]
}

# Create token for metrics consumption
# cabn't output anymore, to get from CLI: terraform state pull
resource "vault_token" "metrics" {
  ttl      = "720h"
  policies = [vault_policy.metrics.name]
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

# add a bootstrapped user
resource "vault_generic_endpoint" "admin_user" {
  path                 = "auth/userpass/users/admin_user"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["${vault_policy.admin-like.name}"],
  "password": "changeme5"
}
EOT
}

# add a namespace
module "sandbox" {
  source               = "./modules/bootstrap-namespace/"
  new-namespace        = "sandbox"
  allow-subnamespaces  = false
  namespace-rate-limit = 100
  providers = {
    // vault.zone = vault.dev1
    vault.vault-root = vault.vault-root
  }
}

# add a namespace
module "boundary" {
  source                  = "./modules/bootstrap-namespace/"
  new-namespace           = "boundary"
  allow-subnamespaces     = false
  namespace-rate-limit    = 100
  create-boundary-transit = true
  providers = {
    // vault.zone = vault.dev1
    vault.vault-root = vault.vault-root
  }
}
