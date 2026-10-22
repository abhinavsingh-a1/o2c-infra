output "audit_archive_bucket" {
  description = "Object Lock bucket for the decision archive (null unless enable_audit)."
  value       = one(module.audit[*].archive_bucket)
}

output "audit_logs_bucket" {
  description = "CloudTrail and AWS Config bucket (null unless enable_audit)."
  value       = one(module.audit[*].logs_bucket)
}
