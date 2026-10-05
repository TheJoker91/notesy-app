# EKS cluster + managed node group (deploy_target = "eks"). Nodes run in the
# public subnets with public IPs, like the Fargate tasks, so no NAT gateway.

# ------------------------------------------------------ cluster role ------

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count              = var.deploy_target == "eks" ? 1 : 0
  name               = "${var.project}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count      = var.deploy_target == "eks" ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ----------------------------------------------------------- cluster ------

resource "aws_eks_cluster" "main" {
  count    = var.deploy_target == "eks" ? 1 : 0
  name     = "${var.project}-eks"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids             = aws_subnet.public[*].id
    endpoint_public_access = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # The role must keep its policy while EKS deletes cluster-managed resources.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# --------------------------------------------------------- node role ------

data "aws_iam_policy_document" "eks_nodes_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  count              = var.deploy_target == "eks" ? 1 : 0
  name               = "${var.project}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = var.deploy_target == "eks" ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = each.value
}

# -------------------------------------------------------- node group ------

resource "aws_eks_node_group" "main" {
  count           = var.deploy_target == "eks" ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.project}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  # Scale by hand or with an autoscaler without Terraform reverting it.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  # Nodes can't join (or drain cleanly on destroy) without these policies.
  depends_on = [aws_iam_role_policy_attachment.eks_nodes]
}

# ------------------------------------------------ pipeline access ---------
# The GitHub deploy role can edit resources in the notesy namespace only.

resource "aws_eks_access_entry" "github_deploy" {
  count         = var.deploy_target == "eks" ? 1 : 0
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_iam_role.github_deploy.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_deploy" {
  count         = var.deploy_target == "eks" ? 1 : 0
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_eks_access_entry.github_deploy[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["notesy"]
  }
}
