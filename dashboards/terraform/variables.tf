variable "signoz_endpoint" {
  description = "SigNoz API endpoint reachable from the Terraform runner."
  type        = string
}

variable "signoz_access_token" {
  description = "SigNoz service-account API key."
  type        = string
  sensitive   = true
}
