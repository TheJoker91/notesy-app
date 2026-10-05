# ------------------------------------------------- ECS execution role ------
# Used by the ECS agent: pull image, write logs, inject secrets.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "read-app-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.database_url.arn,
        aws_secretsmanager_secret.django_secret_key.arn,
      ]
    }]
  })
}

# ------------------------------------------------------ ECS task role ------
# Identity of the running app. Notesy doesn't call AWS APIs, so it's empty.

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# --------------------------------------------- GitHub Actions (OIDC) -------
# Role the pipeline assumes to push to ECR and deploy to ECS or EKS.

# The OIDC provider is shared by every repo in the account, so Terraform only
# looks it up; it never creates or destroys it.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only pushes to the deploy branch of this repo can assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # ------------------------------------------------- ECS only ---

  dynamic "statement" {
    for_each = aws_ecs_service.app
    content {
      sid = "EcsTaskDefinition"
      actions = [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
      ]
      resources = ["*"] # these actions don't support resource-level permissions
    }
  }

  dynamic "statement" {
    for_each = aws_ecs_service.app
    content {
      sid = "EcsDeploy"
      actions = [
        "ecs:UpdateService",
        "ecs:DescribeServices",
      ]
      resources = [statement.value.id]
    }
  }

  dynamic "statement" {
    for_each = aws_ecs_service.app
    content {
      sid       = "PassTaskRoles"
      actions   = ["iam:PassRole"]
      resources = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  # ------------------------------------------------- EKS only ---
  # `aws eks update-kubeconfig` needs DescribeCluster; in-cluster rights come
  # from the EKS access entry (eks.tf), not IAM.

  dynamic "statement" {
    for_each = aws_eks_cluster.main
    content {
      sid       = "EksDescribe"
      actions   = ["eks:DescribeCluster"]
      resources = [statement.value.arn]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "ecr-push-${var.deploy_target}-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
