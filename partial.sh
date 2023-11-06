#!/bin/bash

mkdir main check

cat <<-EOF >> ./check/check.tf
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.20.0"
    }
  }
}

# aws configure
provider "aws" {
  region        = "$AWS_DEFAULT_REGION"
  access_key    = "$AWS_ACCESS_KEY_ID"
  secret_key    = "$AWS_SECRET_ACCESS_KEY"
}

data "aws_vpcs" "vpc" {
  tags = {
    Name = "$VPC_NAME"
  }
}

locals {
  vpc_id = data.aws_vpcs.vpc.ids[0]
}

data "aws_internet_gateway" "doran_igw" {
  filter {
    name   = "attachment.vpc-id"
    values = [local.vpc_id]
  }
}
EOF

cat <<-EOF >> ./main/main.tf
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.20.0"
    }
  }
}

# aws configure
provider "aws" {
  region        = "$AWS_DEFAULT_REGION"
  access_key    = "$AWS_ACCESS_KEY_ID"
  secret_key    = "$AWS_SECRET_ACCESS_KEY"
}

data "aws_vpcs" "vpc" {
  tags = {
    Name = "$VPC_NAME"
  }
}

locals {
  test-vpc_id = data.aws_vpcs.vpc.ids[0]
}

data "aws_vpc" "vpc-cidr" {
  id = local.test-vpc_id

  depends_on = [ data.aws_vpcs.vpc ]
}

locals {
  vpc_id = data.aws_vpc.vpc-cidr.id
}

###########################################CREATE-SUBNET
data "aws_subnets" "subnet" {
  filter {
    name = "vpc-id"
    values = [local.vpc_id] 
  }
}

data "aws_subnet" "subnet" {
  for_each = toset(data.aws_subnets.subnet.ids)
  id       = each.value
}

locals {
  sorted_num = reverse(sort([for subnet_id in data.aws_subnet.subnet : join(" ", slice(split(".", cidrsubnet(subnet_id.cidr_block, 0, 0)), 2, 3))]))
  count_num = length(local.sorted_num) > 0 ? element(local.sorted_num, 0) : 0
}

locals {
    cidr_sub = length(data.aws_subnets.subnet.ids) > 0 ? data.aws_subnet.subnet[data.aws_subnets.subnet.ids[0]].cidr_block : "0.0.0.0/24"
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public-subnet" {
  count = $PUB_SUB_COUNT
  
  vpc_id                  = local.vpc_id
  cidr_block              = "$DL{join(".", slice(split(".", cidrsubnet(data.aws_vpc.vpc-cidr.cidr_block, 0, 0)), 0, 2))}.$DL{(count.index + 1) * 16 + local.count_num}.$DL{join(".", slice(split(".", cidrsubnet(local.cidr_sub, 0, 0)), 3, 4))}"
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true
  tags = {
    Name = "$TITLE-public-subnet-$DL{count.index + 1}"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_subnet" "private-subnet" {
  count = $PRI_SUB_COUNT

  vpc_id                  = local.vpc_id
  cidr_block              = "$DL{join(".", slice(split(".", cidrsubnet(data.aws_vpc.vpc-cidr.cidr_block, 0, 0)), 0, 2))}.$DL{(count.index + 1) * 16 + local.count_num + $PUB_SUB_COUNT * 16 }.$DL{join(".", slice(split(".", cidrsubnet(local.cidr_sub, 0, 0)), 3, 4))}"
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  tags = {
    Name = "$TITLE-private-subnet-$DL{count.index + 1}"
    "kubernetes.io/role/internal-elb" = 1
  }
}

###########################################NAT-GATEWAY

data "aws_nat_gateways" "ngws" {
  vpc_id = local.vpc_id
}

data "aws_nat_gateway" "ngw" {
  count = data.aws_nat_gateways.ngws.ids != null ? length(data.aws_nat_gateways.ngws.ids) : 0
  id    = tolist(data.aws_nat_gateways.ngws.ids)[count.index]
}

locals {
  semi_nat_id = length(data.aws_nat_gateways.ngws.ids) > 0 ? [for nat in data.aws_nat_gateway.ngw : nat.id if nat.state == "available"] : null
}

locals {
  sub_nat_id = local.semi_nat_id != null ? local.semi_nat_id[0] : null
}

resource "aws_nat_gateway" "nat-gateway" {
  count = local.sub_nat_id == null ? 1 : 0
  allocation_id = local.eip_id[0]
  subnet_id     = aws_subnet.public-subnet[0].id

  tags = {
    Name = "$TITLE-nat-gateway"
  }
}

locals {
  nat_id = local.sub_nat_id != null ? local.sub_nat_id : aws_nat_gateway.nat-gateway[0].id
}

#########################################EIP
resource "aws_eip" "eip" {
  count = length(data.aws_nat_gateways.ngws.ids) < 1 ? 1 : 0
  domain = "vpc"
  tags = {
    Name = "$TITLE-eip"
  }
}

locals {
  eip_id = aws_eip.eip[*].id != null ? aws_eip.eip[*].id : null
}
EOF

( cd ./check && terraform init )
( cd ./check && terraform plan )

if [ $? -ne 0 ]; then
cat <<-EOF >> ./main/main.tf
resource "aws_internet_gateway" "internet-gateway" {
  vpc_id = local.vpc_id

  tags = {
    Name = "$TITLE-internet-gateway"
  }
}

locals {
  igw_id = aws_internet_gateway.internet-gateway.id
}

EOF
else
cat <<-EOF >> ./main/main.tf
data "aws_internet_gateway" "internet-gateway" {
  filter {
    name   = "attachment.vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  igw_id = data.aws_internet_gateway.internet-gateway.id
}

EOF
fi

cat <<-EOF >> ./main/main.tf
##################################################ROUTETABLE-IGW
resource "aws_route_table" "pub-sub-routetable" {
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }
  tags = {
    Name = "$TITLE-public-routetable"
  }
}

resource "aws_route_table_association" "pub-sub-association" {
  count = $PUB_SUB_COUNT
  subnet_id      = aws_subnet.public-subnet[count.index].id
  route_table_id = aws_route_table.pub-sub-routetable.id
}
 
##################################################ROUTETABLE-NAT
resource "aws_route_table" "pri-sub-routetable" {
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.nat_id
  }
  tags = {
    Name = "$TITLE-private-routetable"
  }
}

resource "aws_route_table_association" "pri-sub-association" {
  count = $PRI_SUB_COUNT
  subnet_id      = aws_subnet.private-subnet[count.index].id
  route_table_id = aws_route_table.pri-sub-routetable.id
}

data "aws_iam_policy_document" "assume_role-eks" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "assume_role-nodegroup" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#############################################CREATE-EKS-ROLE
resource "aws_iam_role" "eks_role" {
  name               = "$TITLE-eks_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role-eks.json
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_role.name
}

#############################################CREATE-NODEGROUP-ROLE
resource "aws_iam_role" "node-group-role" {
  name               = "$TITLE-node-group-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role-nodegroup.json
}

resource "aws_iam_role_policy_attachment" "attach-AmazonEC2ContainerRegistryFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
  role       = aws_iam_role.node-group-role.name
}

resource "aws_iam_role_policy_attachment" "attach-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node-group-role.name
}

resource "aws_iam_role_policy_attachment" "attach-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node-group-role.name
}

resource "aws_iam_role_policy_attachment" "attach-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node-group-role.name
}

resource "aws_iam_role_policy_attachment" "attach-EC2InstanceProfileForImageBuilderECRContainerBuilds" {
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
  role       = aws_iam_role.node-group-role.name
}

####################################################CREATE-EKS
resource "aws_eks_cluster" "eks" {
  name     = "$AWS_EKS_NAME"
  role_arn = aws_iam_role.eks_role.arn
  version = $EKS_VER

  vpc_config {
    subnet_ids              = aws_subnet.private-subnet[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.eks-security-group.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController,
  ]
}

#######################################################CREATE-NODEGROUP
resource "aws_eks_node_group" "eks-node-group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "$AWS_DATAPLANE_NAME"
  node_role_arn   = aws_iam_role.node-group-role.arn
  subnet_ids      = aws_subnet.private-subnet[*].id
  instance_types  = ["$INSTANCE_TYPE"]
  capacity_type   = "$CAPACITY_TYPE"
  scaling_config {
    min_size     = $SCALING_MIN
    max_size     = $SCALING_MAX
    desired_size = $SCALING_DESIRE
  }

  depends_on = [aws_iam_role_policy_attachment.attach-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.attach-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.attach-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.attach-AmazonEC2ContainerRegistryFullAccess,
  aws_iam_role_policy_attachment.attach-EC2InstanceProfileForImageBuilderECRContainerBuilds]
}

#######################################################About_SG
resource "aws_security_group" "eks-security-group" {
  name        = "$TITLE-eks-security-group"
  description = "$TITLE-eks-security-group"
  vpc_id      = local.vpc_id

  tags = {
    Name = "$TITLE-eks-security-group"
  }

## 필수 ingress
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  ingress {
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
EOF

if [ "False" = "$LB_POLICY" ]; then
cat <<-EOF >> ./main/main.tf
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-doran"
  description = "Policy for the AWS ALB controller"
  policy      = <<$LB_EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
}
$LB_EOF
}
EOF
fi

destroy() {
  ( cd ./main && terraform destroy -auto-approve )
}

trap 'destroy' ERR

( cd ./main && terraform init )
( cd ./main && terraform apply -auto-approve )

if [ $? -ne 0 ]; then
  echo "Creation failed"
  curl -i -X POST -d '{"id":'$ID',"progress":"provision","state":"failed","emessage":"provision failed"}' -H "Content-Type: application/json" $API_ENDPOINT
  exit 1
else
  echo "Created successfully."
  curl -i -X POST -d '{"id":'$ID',"progress":"provision","state":"success","emessage":"Created successfully."}' -H "Content-Type: application/json" $API_ENDPOINT
fi