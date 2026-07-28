variable "name" { type = string }
variable "repositories" {
  description = "List of image repository names to create, e.g. [\"myapp\"]"
  type        = list(string)
}
