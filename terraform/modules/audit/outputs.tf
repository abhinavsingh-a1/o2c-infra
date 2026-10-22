output "logs_bucket" {
  description = "Bucket with the CloudTrail and AWS Config files (7-day lifecycle)."
  value       = aws_s3_bucket.logs.id
}

output "archive_bucket" {
  description = "Object Lock bucket for the hash-chained decision archive (AUDIT_BUCKET of audit-archiver)."
  value       = aws_s3_bucket.archive.id
}

output "trail_arn" {
  description = "CloudTrail trail for management events."
  value       = aws_cloudtrail.this.arn
}

output "config_recorder_name" {
  description = "AWS Config recorder (started by Terraform, stopped before destroy)."
  value       = aws_config_configuration_recorder.this.name
}
