terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in S3 with locking; bucket, key and region are passed at init
  # (terraform init -backend-config=...). `terraform init -backend=false` validates
  # without it.
  backend "s3" {}
}
