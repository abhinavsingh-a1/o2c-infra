# Dev environment. Further modules (VPC, EKS, RDS, ...) are added here with E2/E14.

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

locals {
  name_prefix = "o2c-dev"
  tags = {
    project     = "o2c"
    environment = "dev"
    managed_by  = "terraform"
  }
}

module "audit" {
  source = "../../modules/audit"
  count  = var.enable_audit ? 1 : 0

  name_prefix = local.name_prefix
  tags        = local.tags
}
