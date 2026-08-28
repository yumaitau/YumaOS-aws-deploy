output "application_url" {
  description = "Public YumaOS URL."
  value       = local.application_url
}

output "container_image" {
  description = "Immutable YumaOS image reference."
  value       = var.container_image
}

output "hermes_container_image" {
  description = "Immutable Hermes sidecar image reference."
  value       = var.hermes_container_image
}

output "migration_log_group_name" {
  description = "CloudWatch log group for migration tasks."
  value       = aws_cloudwatch_log_group.migration.name
}

output "load_balancer_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.web.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster used by services and one-shot tasks."
  value       = aws_ecs_cluster.this.name
}

output "web_task_definition_arn" {
  description = "Pinned web+Hermes task definition revision."
  value       = aws_ecs_task_definition.web.arn
}

output "migration_task_definition_arn" {
  description = "One-shot migration task definition revision."
  value       = aws_ecs_task_definition.migration.arn
}

output "web_service_arn" {
  description = "Web ECS service ARN, or null during migration-only bootstrap."
  value       = try(aws_ecs_service.web[0].id, null)
}

output "application_subnet_ids" {
  description = "Private subnets for Fargate tasks."
  value       = aws_subnet.application[*].id
}

output "task_security_group_id" {
  description = "Security group for Fargate tasks."
  value       = aws_security_group.tasks.id
}

output "database_endpoint" {
  description = "Private RDS endpoint."
  value       = aws_db_instance.this.endpoint
}

output "cache_endpoint" {
  description = "Private TLS Redis endpoint."
  value       = "${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "uploads_bucket_name" {
  description = "Private KMS-encrypted S3 uploads bucket."
  value       = aws_s3_bucket.uploads.id
}

output "vault_bucket_name" {
  description = "Private KMS-encrypted S3 vault bucket."
  value       = aws_s3_bucket.vault.id
}

output "hermes_file_system_id" {
  description = "EFS file system used as Hermes home."
  value       = aws_efs_file_system.hermes.id
}

output "runtime_secret_arn" {
  description = "Secrets Manager ARN referenced by task definitions. Secret values are never output."
  value       = aws_secretsmanager_secret.runtime.arn
}

output "aws_account_id" {
  description = "Account that owns this deployment."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Deployment region."
  value       = var.aws_region
}
