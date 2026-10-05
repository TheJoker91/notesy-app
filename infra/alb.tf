# ALB in front of the ECS service (ECS only; on EKS a Service of type
# LoadBalancer provisions its own load balancer).

resource "aws_lb" "main" {
  count              = var.deploy_target == "ecs" ? 1 : 0
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app" {
  count       = var.deploy_target == "ecs" ? 1 : 0
  name        = "${var.project}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # required for Fargate (awsvpc networking)

  deregistration_delay = 30

  health_check {
    path                = "/login/" # "/" redirects anonymous users here
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  count             = var.deploy_target == "ecs" ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}
