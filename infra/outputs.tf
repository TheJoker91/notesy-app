# ---------------------------------------------------------------- network ---

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

# Values to copy into GitHub → Settings → Secrets and variables → Actions.
# ECS-only values are null when deploy_target = "eks", and EKS-only values
# are null when deploy_target = "ecs".

output "deploy_target" {
  value = var.deploy_target
}

output "app_url" {
  description = "Public URL of the app (ECS only; on EKS use the LoadBalancer Service's hostname)."
  value       = one([for lb in aws_lb.main : "http://${lb.dns_name}"])
}

output "github_variables" {
  description = "Repository variables used by .github/workflows/cicd.yaml."
  value = {
    AWS_REGION     = var.aws_region
    APP_NAME       = var.project
    ECR_REPOSITORY = aws_ecr_repository.app.name
    ECS_CLUSTER    = one(aws_ecs_cluster.main[*].name)
    ECS_SERVICE    = one(aws_ecs_service.app[*].name)
    EKS_CLUSTER    = one(aws_eks_cluster.main[*].name)
  }
}

output "github_deploy_role_arn" {
  description = "Store as the AWS_ECR_DEPLOY_ROLE_ARN GitHub secret."
  value       = aws_iam_role.github_deploy.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

# -------------------------------------------------------------------- ecs ---

output "ecs_cluster_name" {
  value = one(aws_ecs_cluster.main[*].name)
}

output "ecs_service_name" {
  value = one(aws_ecs_service.app[*].name)
}

output "ecs_task_definition_family" {
  value = one(aws_ecs_task_definition.app[*].family)
}

output "ecs_container_name" {
  value = var.deploy_target == "ecs" ? var.project : null
}

output "cloudwatch_log_group" {
  value = one(aws_cloudwatch_log_group.app[*].name)
}

# -------------------------------------------------------------------- eks ---

output "eks_cluster_name" {
  value = one(aws_eks_cluster.main[*].name)
}

output "kubeconfig_command" {
  description = "Points kubectl at the cluster."
  value       = one([for c in aws_eks_cluster.main : "aws eks update-kubeconfig --region ${var.aws_region} --name ${c.name}"])
}
