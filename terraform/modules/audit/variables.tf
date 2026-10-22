variable "name_prefix" {
  description = "Prefix of every resource name, e.g. o2c-dev. Bucket names also get the account id."
  type        = string
}

variable "log_retention_days" {
  description = "Days CloudTrail and AWS Config files are kept in the audit-logs bucket."
  type        = number
  default     = 7
}

variable "archive_retention_days" {
  description = <<-EOT
    Default Object Lock retention (GOVERNANCE) of the audit-archive bucket. 1 day keeps
    the environment destroyable (every cloud environment is destroyed when not in use);
    production would use years and COMPLIANCE mode.
  EOT
  type        = number
  default     = 1
}

variable "config_resource_types" {
  description = "Resource types AWS Config records (each recorded change is a billed configuration item)."
  type        = list(string)
  default = [
    "AWS::EKS::Cluster",
    "AWS::RDS::DBInstance",
    "AWS::S3::Bucket",
    "AWS::IAM::Role",
  ]
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
