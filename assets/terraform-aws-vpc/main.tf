provider "aws" {
  region = "eu-west-1"

  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
}

locals {
  name     = "ex-vpc"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 8)]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([
        module.vpc.private_route_table_ids,
        module.vpc.public_route_table_ids,
      ])
      tags = { Name = "s3-vpc-endpoint" }
    }
  }
}
