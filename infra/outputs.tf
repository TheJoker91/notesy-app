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

output "app_url" {
  description = "Public URL of the app."
  value       = "http://${aws_lb.main.dns_name}"
}

output "github_variables" {
  description = "Repository variables used by .github/workflows/cicd.yaml."
  value = {
    AWS_REGION     = var.aws_region
    APP_NAME       = var.project
    ECR_REPOSITORY = aws_ecr_repository.app.name
    ECS_CLUSTER    = aws_ecs_cluster.main.name
    ECS_SERVICE    = aws_ecs_service.app.name
  }
}

output "github_deploy_role_arn" {
  description = "Store as the AWS_ECR_DEPLOY_ROLE_ARN GitHub secret."
  value       = aws_iam_role.github_deploy.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_task_definition_family" {
  value = aws_ecs_task_definition.app.family
}

output "ecs_container_name" {
  value = var.project
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}
