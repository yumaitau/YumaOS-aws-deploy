resource "random_password" "database" {
  length  = 40
  special = false
}

resource "random_password" "cache" {
  length  = 40
  special = false
}

resource "random_password" "better_auth" {
  length  = 64
  special = false
}

resource "random_password" "encryption" {
  length  = 64
  special = false
}

resource "random_password" "hermes_api" {
  length  = 48
  special = false
}

resource "random_password" "hermes_dashboard" {
  length  = 32
  special = false
}

resource "random_password" "hermes_dashboard_secret" {
  length  = 48
  special = false
}

resource "random_password" "hermes_db" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "runtime" {
  name_prefix             = "${local.name}-runtime-"
  description             = "YumaOS runtime connection strings and application secrets"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DATABASE_URL              = "postgresql://yumaosadmin:${random_password.database.result}@${aws_db_instance.this.address}:5432/yumaos?sslmode=require"
    REDIS_URL                 = "rediss://:${random_password.cache.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
    BETTER_AUTH_SECRET        = random_password.better_auth.result
    ENCRYPTION_KEY            = random_password.encryption.result
    HERMES_API_KEY            = random_password.hermes_api.result
    HERMES_DASHBOARD_USER      = "operator"
    HERMES_DASHBOARD_PASSWORD  = random_password.hermes_dashboard.result
    HERMES_DASHBOARD_SECRET    = random_password.hermes_dashboard_secret.result
    HERMES_STATE_ROLE_PASSWORD = random_password.hermes_db.result
    HERMES_STATE_DATABASE_URL  = "postgresql://hermes:${random_password.hermes_db.result}@${aws_db_instance.this.address}:5432/yumaos?sslmode=require"
  })
}
