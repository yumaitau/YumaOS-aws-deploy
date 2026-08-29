# Architecture

Buyer account, Region `ap-southeast-2`.

```text
Internet (AllowedIngressCidr)
        |
   public subnets
        |  ALB + WAF
        |
   application subnets (no public IP)
        |  ECS Fargate task (2048 CPU / 4096 MiB)
        |    listing images only:
        |    hermes  :8642 / :9119   EFS /opt/data
        |    web     :3000           depends on hermes HEALTHY
        |    localhost only between the two
        |    no Postgres/Redis container — those are AWS data services
        |
   isolated data subnets
        |  RDS PostgreSQL 16 (pgvector on migrate)
        |  ElastiCache Redis 7 TLS + AUTH
        |
   S3 (gateway endpoint)
        uploads bucket   STORAGE_DRIVER=s3
        vault bucket     YUMA_VAULT_S3_BUCKET + KMS
        logs bucket      SSE-S3
```

## Why one task

Hermes and YumaOS must call each other without crossing the public ALB. On Fargate that means the same `awsvpc` ENI and `127.0.0.1`. Compose can use `http://app:3000`; this stack must not.

## Model

`HERMES_INFERENCE_PROVIDER=bedrock`
`HERMES_MODEL` / `BEDROCK_MODEL_ID` = `au.anthropic.claude-haiku-4-5-20251001-v1:0`
`BEDROCK_MODEL_CAPABLE` = `au.anthropic.claude-sonnet-4-6`

The task role is scoped to those Australian inference profiles. The buyer enables model access in the Bedrock console.

## Secrets

Secrets Manager holds `DATABASE_URL`, `REDIS_URL` (`rediss://`), `BETTER_AUTH_SECRET`, `ENCRYPTION_KEY`, `HERMES_API_KEY` (same value as Hermes `API_SERVER_KEY`), and the dashboard user/password/secret. No static AWS access keys.

## Storage

- Uploads: `S3_BUCKET`
- Vault: `YUMA_VAULT_S3_BUCKET` and `YUMA_VAULT_KMS_KEY_ARN`
- Hermes home: EFS access point uid/gid `10000`, IAM auth, transit encryption
- Postgres: `CREATE EXTENSION vector` during migrate (`docker/migrate.sh` in the image)

## First-launch defaults that stay optional

HTTP ALB, single NAT, single-AZ RDS, single Redis node, 30-day logs, no Secrets Manager rotation Lambda, no cross-region replication. Ingress `0.0.0.0/0` is not a default. It is rejected unless the buyer sets the explicit opt-in.
