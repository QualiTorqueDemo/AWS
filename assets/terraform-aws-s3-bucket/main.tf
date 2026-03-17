provider "aws" {
  region = "eu-west-1"

  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
}

resource "random_pet" "this" {
  length = 2
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket        = "s3-bucket-${random_pet.this.id}"
  force_destroy = true
}
