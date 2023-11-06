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

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [""]
  }
}
