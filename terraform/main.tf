provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Application = "YumaOS"
        Environment = var.environment
        ManagedBy   = "Terraform"
      },
      var.tags,
    )
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2,
  )

  web_hardening = {
    user       = "nextjs"
    privileged = false
    linuxParameters = {
      capabilities = {
        drop = ["ALL"]
      }
    }
  }

  # Hermes s6 starts as root, drops to uid 10000, and needs a writable home.
  hermes_hardening = {
    privileged = false
    linuxParameters = {
      capabilities = {
        drop = ["ALL"]
        add  = ["CHOWN", "DAC_OVERRIDE", "KILL", "SETGID", "SETUID"]
      }
    }
  }

  application_scheme = var.certificate_arn == null ? "http" : "https"
  application_url = coalesce(
    var.app_url,
    "${local.application_scheme}://${aws_lb.web.dns_name}",
  )

  bedrock_model_id      = var.bedrock_model_id
  bedrock_model_capable = var.bedrock_model_capable

  common_environment = [
    { name = "NODE_ENV", value = "production" },
    { name = "HOSTNAME", value = "0.0.0.0" },
    { name = "PORT", value = "3000" },
    { name = "NEXT_TELEMETRY_DISABLED", value = "1" },
    { name = "CI", value = "1" },
    { name = "APP_NAME", value = "YumaOS" },
    { name = "APP_TIMEZONE", value = var.app_timezone },
    { name = "TZ", value = var.app_timezone },
    { name = "BETTER_AUTH_URL", value = local.application_url },
    { name = "NEXT_PUBLIC_BETTER_AUTH_URL", value = local.application_url },
    { name = "AUTH_DISABLE_SIGNUP", value = "false" },
    { name = "AGENT_CHAT_RUNTIME", value = "hermes" },
    { name = "HERMES_URL", value = "http://127.0.0.1:8642" },
    { name = "HERMES_DASHBOARD_URL", value = "http://127.0.0.1:9119" },
    { name = "HERMES_YUMAOS_MCP_URL", value = "http://127.0.0.1:3000/api/hermes/mcp" },
    { name = "HERMES_MODEL", value = local.bedrock_model_id },
    { name = "HERMES_INFERENCE_PROVIDER", value = "bedrock" },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "AWS_DEFAULT_REGION", value = var.aws_region },
    { name = "BEDROCK_REGION", value = var.aws_region },
    { name = "BEDROCK_MODEL_ID", value = local.bedrock_model_id },
    { name = "BEDROCK_MODEL_CAPABLE", value = local.bedrock_model_capable },
    { name = "POLLY_REGION", value = var.aws_region },
    { name = "STORAGE_DRIVER", value = "s3" },
    { name = "S3_REGION", value = var.aws_region },
    { name = "S3_FORCE_PATH_STYLE", value = "false" },
    { name = "S3_BUCKET", value = aws_s3_bucket.uploads.id },
    { name = "YUMA_VAULT_S3_BUCKET", value = aws_s3_bucket.vault.id },
    { name = "YUMA_VAULT_KMS_KEY_ARN", value = aws_kms_key.this.arn },
    { name = "RUN_MIGRATE_ON_START", value = "1" },
    { name = "RUN_SEED", value = "0" },
    { name = "ALLOW_INSECURE_PUBLIC_URL", value = var.certificate_arn == null ? "true" : "false" },
  ]

  ses_environment = var.ses_from_email == "" ? [] : [
    { name = "EMAIL_PROVIDER", value = "ses" },
    { name = "AWS_SES_REGION", value = var.aws_region },
    { name = "AWS_SES_FROM", value = var.ses_from_email },
    { name = "EMAIL_FROM", value = var.ses_from_email },
  ]

  # Documentary only. The listing image bakes product identity and always
  # calls CheckoutLicense. These variables cannot disable or retarget licensing.
  marketplace_environment = [
    { name = "AWS_MARKETPLACE_ENABLED", value = "true" },
    { name = "AWS_MARKETPLACE_FULFILLMENT", value = "container" },
    { name = "AWS_MARKETPLACE_PRICING_MODEL", value = "contract" },
    { name = "AWS_MARKETPLACE_PRODUCT_CODE", value = var.marketplace_product_code },
    { name = "AWS_MARKETPLACE_PUBLIC_KEY_VERSION", value = tostring(var.marketplace_public_key_version) },
    { name = "AWS_MARKETPLACE_PRODUCT_SKU", value = var.marketplace_product_sku },
  ]

  hermes_environment = [
    { name = "HERMES_HOME", value = "/opt/data" },
    { name = "HOME", value = "/opt/data" },
    { name = "HERMES_S3_BUCKET", value = aws_s3_bucket.hermes.id },
    { name = "HERMES_S3_PREFIX", value = "state" },
    { name = "HERMES_S3_REGION", value = var.aws_region },
    { name = "API_SERVER_ENABLED", value = "true" },
    { name = "API_SERVER_HOST", value = "0.0.0.0" },
    { name = "API_SERVER_PORT", value = "8642" },
    { name = "API_SERVER_CORS_ORIGINS", value = "" },
    { name = "HERMES_DASHBOARD", value = "1" },
    { name = "HERMES_INFERENCE_PROVIDER", value = "bedrock" },
    { name = "HERMES_MODEL", value = local.bedrock_model_id },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "AWS_DEFAULT_REGION", value = var.aws_region },
    { name = "APP_TIMEZONE", value = var.app_timezone },
    { name = "TZ", value = var.app_timezone },
    { name = "HERMES_UID", value = "10000" },
    { name = "HERMES_GID", value = "10000" },
    { name = "PYTHONDONTWRITEBYTECODE", value = "1" },
  ]

  common_secrets = [
    for key in [
      "DATABASE_URL",
      "REDIS_URL",
      "BETTER_AUTH_SECRET",
      "ENCRYPTION_KEY",
      "HERMES_API_KEY",
      "HERMES_DASHBOARD_USER",
      "HERMES_DASHBOARD_PASSWORD",
      "HERMES_DASHBOARD_SECRET",
      "HERMES_STATE_ROLE_PASSWORD",
      ] : {
      name      = key
      valueFrom = "${aws_secretsmanager_secret.runtime.arn}:${key}::"
    }
  ]

  hermes_secrets = [
    { name = "API_SERVER_KEY", valueFrom = "${aws_secretsmanager_secret.runtime.arn}:HERMES_API_KEY::" },
    { name = "HERMES_DASHBOARD_BASIC_AUTH_USERNAME", valueFrom = "${aws_secretsmanager_secret.runtime.arn}:HERMES_DASHBOARD_USER::" },
    { name = "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD", valueFrom = "${aws_secretsmanager_secret.runtime.arn}:HERMES_DASHBOARD_PASSWORD::" },
    { name = "HERMES_DASHBOARD_BASIC_AUTH_SECRET", valueFrom = "${aws_secretsmanager_secret.runtime.arn}:HERMES_DASHBOARD_SECRET::" },
    { name = "HERMES_STATE_DATABASE_URL", valueFrom = "${aws_secretsmanager_secret.runtime.arn}:HERMES_STATE_DATABASE_URL::" },
  ]

  alb_ingress_rules = {
    for pair in setproduct(
      var.certificate_arn == null ? [80] : [80, 443],
      var.allowed_ingress_cidrs,
      ) : "${pair[0]}-${replace(pair[1], "/", "-")}" => {
      port = pair[0]
      cidr = pair[1]
    }
  }

  registry_credentials = var.container_registry_credentials_secret_arn == null ? {} : {
    repositoryCredentials = {
      credentialsParameter = var.container_registry_credentials_secret_arn
    }
  }
}
