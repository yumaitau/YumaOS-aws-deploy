mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-2a", "ap-southeast-2b"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {
  override_during = plan
}

variables {
  container_image        = "ghcr.io/yumaitau/companyos@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  hermes_container_image = "ghcr.io/yumaitau/companyos-hermes@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  allowed_ingress_cidrs  = ["203.0.113.0/24"]
}

run "secure_test_baseline" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "RDS must not be publicly accessible."
  }

  assert {
    condition     = aws_ecs_task_definition.web.runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "Default Fargate architecture is X86_64. Set cpu_architecture=ARM64 for Graviton."
  }

  assert {
    condition     = aws_ecs_task_definition.migration.runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "Migration task architecture must match the web task."
  }

  assert {
    condition     = aws_db_instance.this.engine == "postgres"
    error_message = "Application data lives in RDS PostgreSQL, not a task container."
  }

  assert {
    condition     = length(regexall("(?m)^\\s+name\\s+=\\s+\"(web|hermes)\"$", file("${path.module}/ecs.tf"))) == 2
    error_message = "Marketplace Fargate task must declare exactly the web and hermes containers."
  }

  assert {
    condition     = !strcontains(file("${path.module}/ecs.tf"), "postgres:") && !strcontains(file("${path.module}/ecs.tf"), "pgvector") && !strcontains(file("${path.module}/ecs.tf"), "redis:")
    error_message = "Listing task must not reference a Postgres, pgvector, or Redis container image."
  }

  assert {
    condition     = strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "Name: hermes") && strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "Name: web") && !strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "Image: postgres")
    error_message = "CloudFormation task must ship web and Hermes only; Postgres is RDS."
  }

  assert {
    condition     = strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "CpuArchitecture: !Ref CpuArchitecture") && strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "- ARM64")
    error_message = "CloudFormation must let the buyer choose X86_64 or ARM64."
  }

  assert {
    condition = alltrue([
      for variable in local.common_environment : variable.name != "DATABASE_URL"
    ])
    error_message = "DATABASE_URL must come from Secrets Manager against RDS, not a compose hostname."
  }

  assert {
    condition = anytrue([
      for secret in local.common_secrets : secret.name == "DATABASE_URL"
    ])
    error_message = "Web container must receive DATABASE_URL from the RDS-backed secret."
  }

  assert {
    condition     = local.web_hardening.user == "nextjs"
    error_message = "Fargate web container must run as the image non-root user."
  }

  assert {
    condition = contains(
      local.web_hardening.linuxParameters.capabilities.drop,
      "ALL",
    )
    error_message = "Fargate web container must drop all Linux capabilities."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "HERMES_URL" && variable.value == "http://127.0.0.1:8642"
    ])
    error_message = "YumaOS must reach Hermes on localhost inside the same task."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "HERMES_YUMAOS_MCP_URL" && variable.value == "http://127.0.0.1:3000/api/hermes/mcp"
    ])
    error_message = "Hermes must call YumaOS MCP on localhost, never the public ALB."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "AGENT_CHAT_RUNTIME" && variable.value == "hermes"
    ])
    error_message = "Marketplace tasks must use Hermes as the chat runtime."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "BEDROCK_MODEL_ID" && variable.value == "au.anthropic.claude-haiku-4-5-20251001-v1:0"
    ])
    error_message = "Bedrock must be pinned to Australian Haiku."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "AUTH_DISABLE_SIGNUP" && variable.value == "false"
    ])
    error_message = "First administrator must be able to self-register."
  }

  assert {
    condition = anytrue([
      for variable in local.marketplace_environment :
      variable.name == "AWS_MARKETPLACE_ENABLED" && variable.value == "true"
    ])
    error_message = "Marketplace env is documentary only; it must not be omitted in a way that looks like a disable switch."
  }

  assert {
    condition = alltrue([
      for variable in concat(local.common_environment, local.marketplace_environment) :
      !can(regex("(?i)(SKIP_|DISABLE_|ENFORCE_).*LICENSE", variable.name))
    ])
    error_message = "Task environment must not contain a license-disable switch."
  }

  assert {
    condition     = aws_ecs_service.web[0].network_configuration[0].assign_public_ip == false
    error_message = "Web tasks must not receive public IPs."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.uploads.block_public_policy
    error_message = "Uploads bucket must block public policies."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.vault.block_public_policy
    error_message = "Vault bucket must block public policies."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled
    error_message = "Redis traffic must require TLS."
  }

  assert {
    condition     = aws_efs_file_system.hermes.encrypted
    error_message = "Hermes EFS must be encrypted."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.hermes.block_public_policy
    error_message = "Hermes state bucket must block public policies."
  }

  assert {
    condition = anytrue([
      for variable in local.hermes_environment :
      variable.name == "HERMES_HOME" && variable.value == "/opt/data"
    ])
    error_message = "Hermes must use an explicit HERMES_HOME on EFS."
  }

  assert {
    condition = anytrue([
      for variable in local.hermes_environment :
      variable.name == "HERMES_S3_BUCKET"
    ])
    error_message = "Hermes must receive its snapshot bucket name."
  }

  assert {
    condition = anytrue([
      for secret in local.hermes_secrets : secret.name == "HERMES_STATE_DATABASE_URL"
    ])
    error_message = "Hermes may receive the reserved-schema DSN, never DATABASE_URL."
  }

  assert {
    condition = alltrue([
      for secret in local.hermes_secrets : secret.name != "DATABASE_URL"
    ])
    error_message = "Hermes must not receive the YumaOS DATABASE_URL."
  }

  assert {
    condition = anytrue([
      for secret in local.common_secrets : secret.name == "HERMES_STATE_ROLE_PASSWORD"
    ])
    error_message = "Migrate must be able to create the reserved hermes Postgres role."
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.alb : rule.cidr_ipv4 != "0.0.0.0/0" && rule.cidr_ipv4 != "::/0"
    ])
    error_message = "ALB ingress must not default to the public internet."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "VPC flow logs must capture all traffic."
  }

  assert {
    condition     = !strcontains(file("${path.module}/ecs.tf"), "curl")
    error_message = "ECS container health checks must not use curl; listing images do not ship it."
  }

  assert {
    condition     = strcontains(local.web_health_check_command[1], "fetch('http://127.0.0.1:3000/livez')")
    error_message = "Web container health check must use node fetch against /livez."
  }

  assert {
    condition     = strcontains(local.hermes_health_check_command[1], "python3") && strcontains(local.hermes_health_check_command[1], "127.0.0.1:8642/health")
    error_message = "Hermes container health check must use python3 against localhost /health."
  }

  assert {
    condition     = aws_ecs_service.web[0].deployment_circuit_breaker[0].enable == true
    error_message = "Circuit breaker must stay enabled so a crashing task definition stops rolling."
  }

  assert {
    condition     = aws_ecs_service.web[0].deployment_circuit_breaker[0].rollback == false
    error_message = "Deployment rollback must default off. First create plus a license miss would otherwise leave zero tasks."
  }

  assert {
    condition     = aws_ecs_service.web[0].desired_count == 1
    error_message = "Default desired count must be 1 (MaxCount=1)."
  }

  assert {
    condition     = !strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "curl -fsS")
    error_message = "CloudFormation container health checks must not use curl."
  }

  assert {
    condition     = strcontains(file("${path.module}/../cloudformation/yumaos-fargate.yaml"), "EnableDeploymentRollback")
    error_message = "CloudFormation must expose first-create-safe deployment rollback."
  }

  assert {
    condition     = !strcontains(file("${path.module}/../charts/yumaos/values.yaml"), "ghcr.io") && !strcontains(file("${path.module}/../charts/yumaos/values-aws-marketplace.yaml"), "ghcr.io")
    error_message = "Helm defaults must be Marketplace ECR, not GHCR."
  }

  assert {
    condition     = !strcontains(file("${path.module}/../charts/yumaos/values.yaml"), "1.0.8") && !strcontains(file("${path.module}/../charts/yumaos/values-aws-marketplace.yaml"), "tag: \"1.0.")
    error_message = "Helm must not pin a GRiCk version tag or a 1.0.N listing tag that may not exist."
  }

  assert {
    condition     = strcontains(file("${path.module}/../charts/yumaos/values.yaml"), "replicaCount: 1")
    error_message = "Helm replicaCount must default to 1."
  }

  assert {
    condition     = strcontains(file("${path.module}/../charts/yumaos/values.yaml"), "supplementaryGroups")
    error_message = "Web must keep supplementaryGroups so IRSA tokens remain readable under Hermes fsGroup 10000."
  }
}

run "reject_world_open_ingress" {
  command = plan

  variables {
    allowed_ingress_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [aws_vpc_security_group_ingress_rule.alb]
}

run "allow_world_open_ingress_when_explicit" {
  command = plan

  variables {
    allowed_ingress_cidrs  = ["0.0.0.0/0"]
    allow_internet_ingress = true
  }

  assert {
    condition = anytrue([
      for rule in aws_vpc_security_group_ingress_rule.alb : rule.cidr_ipv4 == "0.0.0.0/0"
    ])
    error_message = "allow_internet_ingress must be able to open the ALB when the buyer opts in."
  }
}

run "migration_only_bootstrap" {
  command = plan

  variables {
    enable_services = false
  }

  assert {
    condition     = length(aws_ecs_service.web) == 0
    error_message = "Bootstrap must be able to run migration before the service exists."
  }
}

run "arm64_runtime_platform" {
  command = plan

  variables {
    cpu_architecture = "ARM64"
  }

  assert {
    condition     = aws_ecs_task_definition.web.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "cpu_architecture=ARM64 must set the web task to ARM64."
  }

  assert {
    condition     = aws_ecs_task_definition.migration.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "cpu_architecture=ARM64 must set the migration task to ARM64."
  }
}

run "reject_unknown_architecture" {
  command = plan

  variables {
    cpu_architecture = "IA64"
  }

  expect_failures = [var.cpu_architecture]
}

run "reject_latest_image" {
  command = plan

  variables {
    container_image = "ghcr.io/yumaitau/companyos:latest"
  }

  expect_failures = [var.container_image]
}

run "reject_burned_image_1_0_0" {
  command = plan

  variables {
    container_image = "709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws:1.0.0"
  }

  expect_failures = [var.container_image]
}

run "reject_burned_image_1_0_1" {
  command = plan

  variables {
    container_image = "709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws:1.0.1"
  }

  expect_failures = [var.container_image]
}

run "reject_burned_image_1_0_2_arm64" {
  command = plan

  variables {
    hermes_container_image = "709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-hermes:1.0.2-arm64"
  }

  expect_failures = [var.hermes_container_image]
}

run "reject_second_task" {
  command = plan

  variables {
    web_desired_count = 2
  }

  expect_failures = [var.web_desired_count]
}

run "enable_deployment_rollback_after_first_create" {
  command = plan

  variables {
    enable_deployment_rollback = true
  }

  assert {
    condition     = aws_ecs_service.web[0].deployment_circuit_breaker[0].rollback == true
    error_message = "enable_deployment_rollback must turn rollback on for later updates."
  }
}

run "reject_unproven_region" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [var.aws_region]
}
