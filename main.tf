provider "aws" {
  region = "us-west-2"
}

########################################
# Get VPC created by eksctl
########################################
data "aws_vpc" "eks_vpc" {
  filter {
    name   = "tag:Name"
    values = ["eksctl-demo-cluster-cluster/VPC"]
  }
}

########################################
# Get public subnets
########################################
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*Public*"]
  }
}

########################################
# Security Group
########################################
resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = data.aws_vpc.eks_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # OK for sandbox
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################################
# IAM Role for Bastion
########################################
resource "aws_iam_role" "bastion_role" {
  name = "bastion-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bastion_policy" {
  role = aws_iam_role.bastion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "bastion_profile" {
  role = aws_iam_role.bastion_role.name
}

########################################
# Get latest Amazon Linux AMI
########################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

########################################
# Bastion EC2 with full setup
########################################
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  subnet_id = data.aws_subnets.public_subnets.ids[0]

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  iam_instance_profile = aws_iam_instance_profile.bastion_profile.name

  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash

# Update system
yum update -y

# Install AWS CLI (usually preinstalled, but safe)
yum install -y aws-cli

# Install kubectl (adjust version if needed)
curl -o /usr/local/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

# Set region
export AWS_DEFAULT_REGION=us-west-2

# Configure kubeconfig
aws eks update-kubeconfig --region us-west-2 --name demo-cluster

EOF

  tags = {
    Name = "bastion-host"
  }
}

########################################
# Output
########################################
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
