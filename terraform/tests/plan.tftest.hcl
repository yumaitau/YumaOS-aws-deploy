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
    error_message = "Fargate web task must explicitly target amd64."
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
    error_message = "Marketplace license env must always be injected; omitting the product code must not disable the check."
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
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.alb : rule.cidr_ipv4 != "0.0.0.0/0" && rule.cidr_ipv4 != "::/0"
    ])
    error_message = "ALB ingress must not default to the public internet."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "VPC flow logs must capture all traffic."
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

run "reject_latest_image" {
  command = plan

  variables {
    container_image = "ghcr.io/yumaitau/companyos:latest"
  }

  expect_failures = [var.container_image]
}

run "reject_unproven_region" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [var.aws_region]
}
