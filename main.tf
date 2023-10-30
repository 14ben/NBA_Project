terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.17.0"
    }
  }
}

provider "aws" {
  region        = ""
  access_key    = ""
  secret_key    = ""
}

cat << EOF >> main.tf
resource "aws_vpc" "-vpc" {
  cidr_block = "10.10.0.0/16"
941092
  tags = {
      Name = "-vpc"
      Terraform   = "true"
      Enviroment  = "dev"
  }
}
data "aws_availability_zones" "available" {}
