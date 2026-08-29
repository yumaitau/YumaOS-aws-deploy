resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name}/web"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_cloudwatch_log_group" "hermes" {
  name              = "/ecs/${local.name}/hermes"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_cloudwatch_log_group" "migration" {
  name              = "/ecs/${local.name}/migration"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_ecs_task_definition" "web" {
  # checkov:skip=CKV_AWS_336:Hermes s6 and Next.js need writable tmp and Hermes home on EFS
  family                   = "${local.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.web_cpu)
  memory                   = tostring(var.web_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  volume {
    name = "hermes-home"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.hermes.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.hermes.id
        iam             = "ENABLED"
      }
    }
  }

  # Listing images only. Postgres is RDS; Redis is ElastiCache.
  container_definitions = jsonencode([
    merge(local.hermes_hardening, local.registry_credentials, {
      name        = "hermes"
      image       = var.hermes_container_image
      essential   = true
      command     = ["gateway", "run"]
      environment = local.hermes_environment
      secrets     = local.hermes_secrets
      mountPoints = [
        {
          sourceVolume  = "hermes-home"
          containerPath = "/opt/data"
          readOnly      = false
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8642/health >/dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 5
        startPeriod = 90
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.hermes.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "hermes"
        }
      }
    }),
    merge(local.web_hardening, local.registry_credentials, {
      name      = "web"
      image     = var.container_image
      essential = true
      dependsOn = [
        {
          containerName = "hermes"
          condition     = "HEALTHY"
        }
      ]
      portMappings = [
        {
          name          = "http"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = concat(local.common_environment, local.ses_environment, local.marketplace_environment)
      secrets     = local.common_secrets
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:3000/livez >/dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 180
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "web"
        }
      }
    }),
  ])

  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets,
    aws_secretsmanager_secret_version.runtime,
    aws_efs_mount_target.hermes,
  ]
}

resource "aws_ecs_task_definition" "migration" {
  family                   = "${local.name}-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.migration_cpu)
  memory                   = tostring(var.migration_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    merge(local.web_hardening, local.registry_credentials, {
      name        = "migration"
      image       = var.container_image
      essential   = true
      command     = ["sh", "-c", "echo yumaos-migrate-complete"]
      environment = concat(local.common_environment, local.ses_environment, local.marketplace_environment)
      secrets     = local.common_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.migration.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "migration"
        }
      }
    })
  ])

  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets,
    aws_secretsmanager_secret_version.runtime,
  ]
}

resource "aws_ecs_service" "web" {
  count = var.enable_services ? 1 : 0

  name             = "${local.name}-web"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.web.arn
  desired_count    = var.web_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  enable_ecs_managed_tags           = true
  health_check_grace_period_seconds = 240
  propagate_tags                    = "SERVICE"
  wait_for_steady_state             = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.tasks.id]
    subnets          = aws_subnet.application[*].id
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.execution,
    aws_db_instance.this,
    aws_elasticache_replication_group.this,
    aws_efs_mount_target.hermes,
  ]
}
