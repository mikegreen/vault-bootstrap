variable "new-namespace" {
  type = string
}

variable "path-prefix" {
  type    = string
  default = "bootstrapped"
}

variable "secrets_to_mount" {
  type    = list(any)
  default = ["kv", "kv-v2", "pki", "transit"]
}

variable "auths_to_mount" {
  type    = list(any)
  default = ["github", "aws"]
}

variable "allow-subnamespaces" {
  type    = bool
  default = false
}

variable "namespace-rate-limit" {
  type    = number
  default = 100
}

variable "create-boundary-transit" {
  type    = bool
  default = false
}
