variable "aws_region" {
  description = "AWS region to deploy into. Must match the AWS_REGION GitHub variable."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix for every resource and as the Project tag."
  type        = string
  default     = "notesy"
}

variable "deploy_target" {
  description = "Where the app runs: \"ecs\" (Fargate behind an ALB) or \"eks\" (managed node group)."
  type        = string
  default     = "eks"

  validation {
    condition     = contains(["ecs", "eks"], var.deploy_target)
    error_message = "deploy_target must be \"ecs\" or \"eks\"."
  }
}

# ---------------------------------------------------------------- network ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

# ------------------------------------------------------------------- app ----

variable "container_port" {
  description = "Port gunicorn listens on inside the container (see Dockerfile EXPOSE)."
  type        = number
  default     = 8000
}

variable "image_tag" {
  description = "Image tag used for the initial task definition. CI replaces it with the commit SHA on each deploy."
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Initial number of running tasks. 0 until the first image is pushed to ECR; Terraform ignores later changes (scale via the pipeline or console)."
  type        = number
  default     = 0
}

variable "run_seed" {
  description = "Run `manage.py seed` (creates the demo/demo user) on container start. For demo sessions only (enable with -var run_seed=true)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the app container."
  type        = number
  default     = 14
}

# ------------------------------------------------------------------- eks ----

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster (newest in standard support as of 2026-10; see `aws eks describe-cluster-versions`)."
  type        = string
  default     = "1.37"
}

# -------------------------------------------------------------- database ----

variable "db_name" {
  description = "Postgres database name."
  type        = string
  default     = "notesy"
}

variable "db_username" {
  description = "Postgres master username."
  type        = string
  default     = "notesy"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
  default     = 20
}

variable "db_deletion_protection" {
  description = "Protect the RDS instance from `terraform destroy`."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- GitHub ----

variable "github_repository" {
  description = "GitHub repo allowed to assume the deploy role, as \"owner/name\"."
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to deploy."
  type        = string
  default     = "main"
}
