# Architecture

Buyer account, Region `ap-southeast-2`.

```text
Internet (AllowedIngressCidr)
        |
   public subnets
        |  ALB + WAF
        |
   application subnets (no public IP)
        |  ECS Fargate task (2048 CPU / 4096 MiB, X86_64 or ARM64)
        |    listing images only (linux/amd64 + linux/arm64):
        |    hermes  :8642 / :9119   EFS /opt/data (live home)
        |                            S3 snapshots of sqlite state
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

## Licensing

This is a container contract listing. The YumaOS web image calls AWS License Manager `CheckoutLicense` (`PROVISIONAL`, dimension `standard_deployment`) using the product identity baked at image build. Hermes is a public sidecar and is not license-gated. The task role needs the License Manager actions AWS documents; `Resource: *` is required by those APIs. Task-definition environment variables cannot turn the web check off.

## Why one task

Hermes and YumaOS must call each other without crossing the public ALB. On Fargate that means the same `awsvpc` ENI and `127.0.0.1`. Compose can use `http://app:3000`; this stack must not.

## Model

`HERMES_INFERENCE_PROVIDER=bedrock`
`HERMES_MODEL` / `BEDROCK_MODEL_ID` = `au.anthropic.claude-haiku-4-5-20251001-v1:0`
`BEDROCK_MODEL_CAPABLE` = `au.anthropic.claude-sonnet-4-6`

The task role is scoped to those Australian inference profiles. The buyer enables model access in the Bedrock console.

## Secrets

Secrets Manager holds `DATABASE_URL`, `REDIS_URL` (`rediss://`), `BETTER_AUTH_SECRET`, `ENCRYPTION_KEY`, `HERMES_API_KEY` (same value as Hermes `API_SERVER_KEY`), the dashboard user/password/secret, `HERMES_STATE_ROLE_PASSWORD`, and `HERMES_STATE_DATABASE_URL` (reserved `hermes` schema, not the app URL). No static AWS access keys.

## Storage

- Uploads: `S3_BUCKET`
- Vault: `YUMA_VAULT_S3_BUCKET` and `YUMA_VAULT_KMS_KEY_ARN`
- Hermes live home: EFS access point uid/gid `10000`, IAM auth, transit encryption. Coding repos and sqlite stay here.
- Hermes snapshots: dedicated S3 bucket (`HERMES_S3_BUCKET`), prefix `state/`. Not the uploads or vault bucket.
- Hermes Postgres: reserved schema `hermes` on the same RDS, owned by a `hermes` login. Hermes does **not** receive `DATABASE_URL`. The DSN is `HERMES_STATE_DATABASE_URL` for a future upstream Postgres backend and is unused by 0.20.5.
- Postgres: `CREATE EXTENSION vector` during migrate (`docker/migrate.sh` in the image)

## First-launch defaults that stay optional

HTTP ALB, single NAT, single-AZ RDS, single Redis node, 30-day logs, no Secrets Manager rotation Lambda, no cross-region replication. Ingress `0.0.0.0/0` is not a default. It is rejected unless the buyer sets the explicit opt-in.
