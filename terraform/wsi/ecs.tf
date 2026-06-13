resource "aws_ecs_cluster" "main" {
  name = "wsi-ecs"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "wsi-ecs"
  }
}

resource "aws_cloudwatch_log_group" "about" {
  name              = "/ecs/about-task-def"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "projects" {
  name              = "/ecs/projects-task-def"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "about" {
  family                   = "about-task-def"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "about"
      image     = "${aws_ecr_repository.about.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.about.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "about-task-def"
  }
}

resource "aws_ecs_task_definition" "projects" {
  family                   = "projects-task-def"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "projects"
      image     = "${aws_ecr_repository.projects.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.projects.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "projects-task-def"
  }
}

resource "aws_ecs_service" "about" {
  name            = "wsi-about-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.about.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private["a"].id, aws_subnet.private["b"].id]
    security_groups  = [aws_security_group.about.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.about.arn
    container_name   = "about"
    container_port   = 5000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = {
    Name = "wsi-about-svc"
  }
}

resource "aws_ecs_service" "projects" {
  name            = "wsi-projects-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.projects.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private["a"].id, aws_subnet.private["b"].id]
    security_groups  = [aws_security_group.projects.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.projects.arn
    container_name   = "projects"
    container_port   = 5000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = {
    Name = "wsi-projects-svc"
  }
}
