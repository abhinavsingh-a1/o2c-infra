variable "region" {
  description = "AWS region of the dev environment."
  type        = string
  default     = "eu-central-1"
}

variable "enable_audit" {
  description = "Create the audit module (CloudTrail, AWS Config, audit buckets). Off by default: it records and bills while it exists."
  type        = bool
  default     = false
}
