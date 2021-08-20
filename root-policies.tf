# root-policies.tf

# Create the data for the policy
data "vault_policy_document" "admin_like_policy_content" {
  rule {
    path         = "*"
    capabilities = ["create", "read", "update", "list", "sudo"]
    description  = "Policy for admin-like privs without the root token"
  }
}

# Create policy for metrics reading
data "vault_policy_document" "metrics_policy_content" {
  rule {
    path         = "/v1/sys/metrics"
    capabilities = ["read"]
    description  = "Policy for metrics tokens"
  }
}
