#!/bin/bash
#export VPC_NAME="beeen-vpc"
# VPC 존재 여부를 확인하는 Terraform 코드를 check.tf 파일에 생성
cat << EOF > check.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.17.0"
    }
  }
}

provider "aws" {
  region        = "$AWS_DEFAULT_REGION"
  access_key    = "$AWS_ACCESS_KEY_ID"
  secret_key    = "$AWS_SECRET_ACCESS_KEY"
}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["$VPC_NAME"]
  }
}
EOF

terraform init && terraform plan

# Terraform plan의 결과를 저장
PLAN_RESULT=$?

# check.tf 파일을 삭제
rm check.tf

# Plan 결과에 따라 다른 스크립트를 실행
if [ $PLAN_RESULT -eq 0 ]; then
     echo @@@@@ [$VPC_NAME] Partial Provision Start @@@@@
     ./partial.sh
else
    echo @@@@@ [VPC not Found] Full Provison Start @@@@@
    ./full_pro.sh
fi
