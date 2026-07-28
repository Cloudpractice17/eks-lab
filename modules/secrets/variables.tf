variable "name" { type = string }
variable "environment" {
  description = "dev or prod — secrets are namespaced by environment so dev and prod never share values"
  type        = string
}
