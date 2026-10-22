# Module `audit`

Audit trail of the AWS account and the archive bucket for the O2C decision log
(o2c-app ADR-014). Enabled in `envs/dev` with `enable_audit = true` (default `false`).

| Resource | What |
|---|---|
| `aws_cloudtrail.this` | Management events (all regions, global services), log file validation on |
| `aws_config_configuration_recorder.this` | AWS Config for `AWS::EKS::Cluster`, `AWS::RDS::DBInstance`, `AWS::S3::Bucket`, `AWS::IAM::Role` only |
| `aws_config_delivery_channel.this` | Config snapshots and history into the audit-logs bucket (`config/`) |
| `aws_config_configuration_recorder_status.this` | Starts the recorder; on destroy it stops it first |
| `aws_s3_bucket.logs` | `<prefix>-audit-logs-<account>`: SSE-S3, public access blocked, TLS only, lifecycle 7 days, `force_destroy` |
| `aws_s3_bucket.archive` | `<prefix>-audit-archive-<account>`: Object Lock GOVERNANCE, 1-day default retention, versioning, SSE-S3, public access blocked, `force_destroy` |

## Cost (eu-central-1 list prices, small dev account)
- **CloudTrail:** the first copy of management events is free; S3 storage for 7 days
  of logs is cents.
- **AWS Config:** priced per configuration item recorded, $0.003 each, continuous
  recording.
  - Recording is limited to 4 resource types, so only their changes create items. A dev
    account with one EKS cluster, one RDS instance, a dozen buckets and some roles
    records a few hundred items in a busy month: about $1, usually cents.
  - No Config rules or conformance packs: those are billed per evaluation.
  - Recording all resource types would also bill every ENI, security group, volume and
    instance change in an EKS cluster.
- **S3:** a few MB with 7-day expiry in the logs bucket, and a 1-day lock on the
  archive: cents.

## Why the retention is 1 day
Every cloud environment must be destroyable with `terraform destroy` and is destroyed
when not in use (project plan). Object Lock in COMPLIANCE mode, or a long GOVERNANCE
retention, would keep objects and the bucket alive until the retention ends.
- **GOVERNANCE with 1 day** shows the mechanism: an object version cannot be deleted or
  overwritten by normal users before its retention date.
- **Destroy still works:** `force_destroy` removes all versions. Within the day a
  principal with `s3:BypassGovernanceRetention` can still delete them; after the day
  nothing is locked.
- **Production:** use COMPLIANCE mode and a retention that matches the legal period, and
  accept that the bucket cannot be destroyed before it ends.

## Validate (never applied from here)
```
cd terraform/envs/dev
terraform init -backend=false
terraform validate
```
