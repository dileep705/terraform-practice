provider "aws" {
  region = "us-east-2"  # Ohio region
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "my_vpc"
  }
}

# Create Subnets
resource "aws_subnet" "my_subnet" {
  count = 2
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = cidrsubnet(aws_vpc.my_vpc.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "my_subnet-${count.index}"
  }
}

data "aws_availability_zones" "available" {}

# Create EKS Cluster
resource "aws_eks_cluster" "my_cluster" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_role.arn
  vpc_config {
    subnet_ids = aws_subnet.my_subnet[*].id
  }
  depends_on = [aws_iam_role_policy_attachment.eks_policy]
  version   = "1.29"
}

# IAM Role for EKS
resource "aws_iam_role" "eks_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Effect    = "Allow"
      Sid       = ""
    }]
  })
}

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

# Node Group
resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.my_subnet[*].id
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  # Node instance type
  instance_type = "t2.medium"
  
  depends_on = [aws_eks_cluster.my_cluster]
}

# IAM Role for Node Group
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Effect    = "Allow"
      Sid       = ""
    }]
  })
}

# Attach Policies to Node Role
resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registries_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.my_cluster.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.my_cluster.name
}

output "node_group_name" {
  value = aws_eks_node_group.my_node_group.node_group_name
}
