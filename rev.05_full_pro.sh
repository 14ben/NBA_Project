#!/bin/bash

destroy() {
  echo "Start Destroy"
#  curl -i -X POST -d '{"id":'$ID',"progress":"provision","state":"failed","emessage":"'$apply_output'"}' -H "Content-Type: application/json" $API_ENDPOINT
  terraform destroy -auto-approve > /dev/null 2>&1
  echo "Destroy Success"
}
trap 'destroy' ERR


### Providers
cat << EOF >> main.tf
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

EOF

### VPC 생성
    cat << EOF >> main.tf
resource "aws_vpc" "${TITLE}-vpc" {
  cidr_block = "10.10.0.0/16"
  tags = {
      Name = "$TITLE-vpc"
      Terraform   = "true"
      Enviroment  = "dev"
  }
}
EOF
### Subnet 생성
 cat << EOF >> main.tf
data "aws_availability_zones" "available" {}
EOF

# PUB SUB
if [ -n "$PUB_SUB_COUNT" ]; then
    echo "새로운 PUB_Subnet 생성(개수): $PUB_SUB_COUNT개"
    cat << EOF >> main.tf
resource "aws_subnet" "${TITLE}-pub-subnet" {
  count = $PUB_SUB_COUNT
  vpc_id     = aws_vpc.$TITLE-vpc.id
  cidr_block = "10.10.$DL{count.index+1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = "true"
  tags = {
    Name = "$TITLE-public-subnet-$DL{count.index+1}"
    "kubernetes.io/role/elb" = "1"
  }
}
EOF
fi

# PRI SUB
if [ -n "$PRI_SUB_COUNT" ]; then
    echo "새로운 PRI_Subnet 생성(개수): $PRI_SUB_COUNT개"
    cat << EOF >> main.tf
resource "aws_subnet" "${TITLE}-pri-subnet" {
  count = $PRI_SUB_COUNT
  vpc_id     = aws_vpc.$TITLE-vpc.id
  cidr_block = "10.10.$DL{count.index+10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = "false"
  tags = {
    Name = "$TITLE-private-subnet-$DL{count.index+10}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
EOF
fi

#### Internet GW
#  cat <<-EOF >> main.tf
#resource "aws_internet_gateway" "$TITLE-igw" {
#  vpc_id = aws_vpc.$TITLE-vpc.id
#  tags = {
#    Name = "$TITLE-internet-gateway"
#  }
#}
#EOF
#
#### NAT GW
#  cat <<-EOF >> main.tf
#resource "aws_nat_gateway" "$TITLE-nat-gw" {
#  allocation_id = aws_eip.$TITLE-eip.id
#  subnet_id     = aws_subnet.$TITLE-pub-subnet[0].id
#  tags = {
#    Name = "$TITLE-nat-gateway"
#  }
#}
#EOF
#
#### EIP
#  cat <<-EOF >> main.tf
#resource "aws_eip" "$TITLE-eip" {
#  domain = "vpc"
#  tags = {
#    Name = "$TITLE-eip"
#  }
#}
#EOF
#
#### public Subnet Route Table 및 Association 
## create public subnet route table
#  cat <<-EOF >> main.tf
#resource "aws_route_table" "$TITLE-public" {
#  vpc_id = aws_vpc.$TITLE-vpc.id
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = aws_internet_gateway.$TITLE-igw.id
#  }
#  tags = {
#    Name = "$TITLE-public-routetable"
#  }
#}
#EOF
#
### association routetable - public subnet
#  cat <<-EOF >> main.tf
#resource "aws_route_table_association" "$TITLE-routing-public" {
#    count = $PUB_SUB_COUNT
#    subnet_id     = aws_subnet.$TITLE-pub-subnet[count.index].id
#    route_table_id = aws_route_table.$TITLE-public.id
#}
#EOF
#
#### Private Subnet Route Table 및 Association 
## create Private subnet route table
#  cat <<-EOF >> main.tf
#resource "aws_route_table" "$TITLE-private" {
#  vpc_id = aws_vpc.$TITLE-vpc.id
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = aws_nat_gateway.$TITLE-nat-gw.id
#  }
#  tags = {
#    Name = "$TITLE-private-routetable"
#  }
#}
#EOF
#
## association routetable - private subnet
#  cat <<-EOF >> main.tf
#resource "aws_route_table_association" "$TITLE-routing-private" {
#    count = $PRI_SUB_COUNT
#    subnet_id     = aws_subnet.$TITLE-pri-subnet[count.index].id
#    route_table_id = aws_route_table.$TITLE-private.id
#}
#EOF
#
#### SG
#    cat << EOF >> main.tf
### SG 정의
#resource "aws_security_group" "${TITLE}-eks-sg" {
#  name        = "$TITLE-eks-sg"
#  description = "$TITLE-eks-sg"
#  vpc_id      = aws_vpc.$TITLE-vpc.id
#
#  tags = {
#    Name = "$TITLE-eks-sg"
#  }
#
### 필수 ingress
#  ingress {
#    from_port   = 443
#    to_port     = 443
#    protocol    = "tcp"
#    cidr_blocks = ["10.10.0.0/16"]
#  }
#
#  ingress {
#    from_port   = 6443
#    to_port     = 6443
#    protocol    = "tcp"
#    cidr_blocks = ["10.10.0.0/16"]
#  }
#
#  ingress {
#    from_port   = 9443
#    to_port     = 9443
#    protocol    = "tcp"
#    cidr_blocks = ["10.10.0.0/16"]
#  }
#
#  ingress {
#    from_port   = 80
#    to_port     = 80
#    protocol    = "tcp"
#    cidr_blocks = ["10.10.0.0/16"]
#  }
#
#  ingress {
#    from_port   = -1
#    to_port     = -1
#    protocol    = "icmp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#EOF
#
####
#    cat << EOF >> main.tf
#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#}
#EOF
#
### EKS 추가
## create eks cluster
#if [ -n "$EKS_VER" ]; then
#        echo "새로운 EKS 추가"
#        cat << EOF >> main.tf
#resource "aws_eks_cluster" "$TITLE-eks" {
#  name     = "$AWS_EKS_NAME"
#  role_arn = aws_iam_role.eks_role.arn
#  version  = $EKS_VER
#  vpc_config {
#    subnet_ids              = aws_subnet.${TITLE}-pri-subnet[*].id
#    endpoint_public_access  = true
#    endpoint_private_access = true
#    security_group_ids      = [aws_security_group.$TITLE-eks-sg.id]
#  }
#  depends_on = [
#    aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy,
#    aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController,
#  ]
#}
#EOF
#fi
#
#### Node-group
#if [ -n "$AWS_DATAPLANE_NAME" ]; then
#  echo "새로운 NodeGroup 추가"
#  cat << EOF >> main.tf
#resource "aws_eks_node_group" "$TITLE-eks-node-group" {
#  cluster_name    = aws_eks_cluster.$TITLE-eks.name
#  node_group_name = "$AWS_DATAPLANE_NAME"
#  node_role_arn   = aws_iam_role.node-group-role.arn
#  subnet_ids      = aws_subnet.${TITLE}-pri-subnet[*].id
#  instance_types  = ["$INSTANCE_TYPE"]
#  capacity_type   = "$CAPACITY_TYPE"
#  scaling_config {
#    min_size     = $SCALING_MIN
#    max_size     = $SCALING_MAX
#    desired_size = $SCALING_DESIRE
#  }
#  depends_on = [
#    aws_iam_role_policy_attachment.attach-AmazonEKSWorkerNodePolicy,
#    aws_iam_role_policy_attachment.attach-AmazonEKS_CNI_Policy,
#    aws_iam_role_policy_attachment.attach-AmazonEC2ContainerRegistryReadOnly,
#    aws_iam_role_policy_attachment.attach-AmazonEC2ContainerRegistryFullAccess,
#    aws_iam_role_policy_attachment.attach-EC2InstanceProfileForImageBuilderECRContainerBuilds
#  ]
#}
#EOF
#fi
#
#### 9. IAM 정책 문서 생성
#    cat << EOF >> main.tf
#data "aws_iam_policy_document" "assume_role-eks" {
#  statement {
#    effect = "Allow"
#
#    principals {
#      type        = "Service"
#      identifiers = ["eks.amazonaws.com"]
#    }
#
#    actions = ["sts:AssumeRole"]
#  }
#}
#
#data "aws_iam_policy_document" "assume_role-nodegroup" {
#  statement {
#    effect = "Allow"
#
#    principals {
#      type        = "Service"
#      identifiers = ["ec2.amazonaws.com"]
#    }
#
#    actions = ["sts:AssumeRole"]
#  }
#}
#EOF
#
#### 10. IAM 역할 생성 및 정책 첨부
#    cat << EOF >> main.tf
## create role about eks
#resource "aws_iam_role" "eks_role" {
#  name               = "${TITLE}-eks_role"
#  assume_role_policy = data.aws_iam_policy_document.assume_role-eks.json
#}
#
#resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#  role       = aws_iam_role.eks_role.name
#}
#
#resource "aws_iam_role_policy_attachment" "eks-AmazonEKSVPCResourceController" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
#  role       = aws_iam_role.eks_role.name
#}
#
## create role about node-group
#resource "aws_iam_role" "node-group-role" {
#  name               = "${TITLE}-node-group-role"
#  assume_role_policy = data.aws_iam_policy_document.assume_role-nodegroup.json
#}
#
#resource "aws_iam_role_policy_attachment" "attach-AmazonEC2ContainerRegistryFullAccess" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
#  role       = aws_iam_role.node-group-role.name
#}
#
#resource "aws_iam_role_policy_attachment" "attach-AmazonEKSWorkerNodePolicy" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#  role       = aws_iam_role.node-group-role.name
#}
#
#resource "aws_iam_role_policy_attachment" "attach-AmazonEKS_CNI_Policy" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#  role       = aws_iam_role.node-group-role.name
#}
#
#resource "aws_iam_role_policy_attachment" "attach-AmazonEC2ContainerRegistryReadOnly" {
#  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#  role       = aws_iam_role.node-group-role.name
#}
#
#resource "aws_iam_role_policy_attachment" "attach-EC2InstanceProfileForImageBuilderECRContainerBuilds" {
#  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
#  role       = aws_iam_role.node-group-role.name
#}
#EOF
#if [ "$LB_POLICY" = "False" ]; then
#  cat << EOF >> main.tf
#resource "aws_iam_policy" "alb_controller" {
#  name        = "AWSLoadBalancerControllerIAMPolicyQUEST"
#  description = "Policy for the AWS ALB controller"
#  policy      = <<$LB_EOF
#{
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Effect": "Allow",
#            "Action": [
#                "iam:CreateServiceLinkedRole"
#            ],
#            "Resource": "*",
#            "Condition": {
#                "StringEquals": {
#                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:DescribeAccountAttributes",
#                "ec2:DescribeAddresses",
#                "ec2:DescribeAvailabilityZones",
#                "ec2:DescribeInternetGateways",
#                "ec2:DescribeVpcs",
#                "ec2:DescribeVpcPeeringConnections",
#                "ec2:DescribeSubnets",
#                "ec2:DescribeSecurityGroups",
#                "ec2:DescribeInstances",
#                "ec2:DescribeNetworkInterfaces",
#                "ec2:DescribeTags",
#                "ec2:GetCoipPoolUsage",
#                "ec2:DescribeCoipPools",
#                "elasticloadbalancing:DescribeLoadBalancers",
#                "elasticloadbalancing:DescribeLoadBalancerAttributes",
#                "elasticloadbalancing:DescribeListeners",
#                "elasticloadbalancing:DescribeListenerCertificates",
#                "elasticloadbalancing:DescribeSSLPolicies",
#                "elasticloadbalancing:DescribeRules",
#                "elasticloadbalancing:DescribeTargetGroups",
#                "elasticloadbalancing:DescribeTargetGroupAttributes",
#                "elasticloadbalancing:DescribeTargetHealth",
#                "elasticloadbalancing:DescribeTags"
#            ],
#            "Resource": "*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "cognito-idp:DescribeUserPoolClient",
#                "acm:ListCertificates",
#                "acm:DescribeCertificate",
#                "iam:ListServerCertificates",
#                "iam:GetServerCertificate",
#                "waf-regional:GetWebACL",
#                "waf-regional:GetWebACLForResource",
#                "waf-regional:AssociateWebACL",
#                "waf-regional:DisassociateWebACL",
#                "wafv2:GetWebACL",
#                "wafv2:GetWebACLForResource",
#                "wafv2:AssociateWebACL",
#                "wafv2:DisassociateWebACL",
#                "shield:GetSubscriptionState",
#                "shield:DescribeProtection",
#                "shield:CreateProtection",
#                "shield:DeleteProtection"
#            ],
#            "Resource": "*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:AuthorizeSecurityGroupIngress",
#                "ec2:RevokeSecurityGroupIngress"
#            ],
#            "Resource": "*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:CreateSecurityGroup"
#            ],
#            "Resource": "*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:CreateTags"
#            ],
#            "Resource": "arn:aws:ec2:*:*:security-group/*",
#            "Condition": {
#                "StringEquals": {
#                    "ec2:CreateAction": "CreateSecurityGroup"
#                },
#                "Null": {
#                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:CreateTags",
#                "ec2:DeleteTags"
#            ],
#            "Resource": "arn:aws:ec2:*:*:security-group/*",
#            "Condition": {
#                "Null": {
#                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
#                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "ec2:AuthorizeSecurityGroupIngress",
#                "ec2:RevokeSecurityGroupIngress",
#                "ec2:DeleteSecurityGroup"
#            ],
#            "Resource": "*",
#            "Condition": {
#                "Null": {
#                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:CreateLoadBalancer",
#                "elasticloadbalancing:CreateTargetGroup"
#            ],
#            "Resource": "*",
#            "Condition": {
#                "Null": {
#                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:CreateListener",
#                "elasticloadbalancing:DeleteListener",
#                "elasticloadbalancing:CreateRule",
#                "elasticloadbalancing:DeleteRule"
#            ],
#            "Resource": "*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:AddTags",
#                "elasticloadbalancing:RemoveTags"
#            ],
#            "Resource": [
#                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
#                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
#                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
#            ],
#            "Condition": {
#                "Null": {
#                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
#                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:AddTags",
#                "elasticloadbalancing:RemoveTags"
#            ],
#            "Resource": [
#                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
#                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
#                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
#                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
#            ]
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:ModifyLoadBalancerAttributes",
#                "elasticloadbalancing:SetIpAddressType",
#                "elasticloadbalancing:SetSecurityGroups",
#                "elasticloadbalancing:SetSubnets",
#                "elasticloadbalancing:DeleteLoadBalancer",
#                "elasticloadbalancing:ModifyTargetGroup",
#                "elasticloadbalancing:ModifyTargetGroupAttributes",
#                "elasticloadbalancing:DeleteTargetGroup"
#            ],
#            "Resource": "*",
#            "Condition": {
#                "Null": {
#                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:AddTags"
#            ],
#            "Resource": [
#                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
#                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
#                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
#            ],
#            "Condition": {
#                "StringEquals": {
#                    "elasticloadbalancing:CreateAction": [
#                        "CreateTargetGroup",
#                        "CreateLoadBalancer"
#                    ]
#                },
#                "Null": {
#                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
#                }
#            }
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:RegisterTargets",
#                "elasticloadbalancing:DeregisterTargets"
#            ],
#            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
#        },
#        {
#            "Effect": "Allow",
#            "Action": [
#                "elasticloadbalancing:SetWebAcl",
#                "elasticloadbalancing:ModifyListener",
#                "elasticloadbalancing:AddListenerCertificates",
#                "elasticloadbalancing:RemoveListenerCertificates",
#                "elasticloadbalancing:ModifyRule"
#            ],
#            "Resource": "*"
#        }
#    ]
#}
#$LB_EOF
#}
#EOF
#
#elif [ "$LB_POLICY" = "True" ]; then
#  echo "LB_POLICY is True. Skipping policy creation."
#fi
#
#terraform init
#terraform apply -auto-approve
#apply_output=$(terraform apply -auto-approve 2>&1 | sed "s/\x1B\[[0-9;]*[JKmsu]//g" | grep -E "Error" || true)
#echo "Create Success"
#if [[ -n $apply_output ]]; then
#  echo "$apply_output" > output.txt
#  echo "$apply_output"
#  destroy



#
#if [ $? -ne 0 ]; then
#  echo "Creation failed"
#  curl -i -X POST -d '{"id":'$ID',"progress":"provision","state":"failed","emessage":"provision failed"}' -H "Content-Type: application/json" $API_ENDPOINT
#  exit 1
#else
#  echo "Created successfully."
#  curl -i -X POST -d '{"id":'$ID',"progress":"provision","state":"success","emessage":"Created successfully."}' -H "Content-Type: application/json" $API_ENDPOINT
#fi
