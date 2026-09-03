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

This is a container contract listing. The YumaOS web image calls AWS License Manager `CheckoutLicense` (`PROVISIONAL`, dimension `standard_deployment`, `Count=1`) at start using the product identity baked at image build. The 15-minute heartbeat checks `AWS::Marketplace::Usage` (`Unit=None`) with a different ClientToken so it does not draw a second `MaxCount=1` unit. Hermes is a public sidecar and is not license-gated. The task role needs the License Manager actions AWS documents; `Resource: *` is required by those APIs. Task-definition environment variables cannot turn the web check off.

## Why one task (or one pod)

Hermes and YumaOS must call each other without crossing the public ALB. On Fargate that means the same `awsvpc` ENI and `127.0.0.1`. On EKS that means **one pod, two containers**. Compose can use `http://app:3000`; this stack must not. `desired_count` / `replicaCount` stay 1 because `standard_deployment` is `MaxCount=1`.

ECS container health checks run inside the image and use `node` / `python3`. Kubernetes `httpGet` probes are kubelet-side. On EKS, `CheckoutLicense` uses the ServiceAccount IRSA / Pod Identity role, not an ECS task role. Marketplace ECR is not the cluster's own registry; pull tokens last 12 hours.

## Model

`HERMES_INFERENCE_PROVIDER=bedrock`
`HERMES_MODEL` / `BEDROCK_MODEL_ID` = `au.anthropic.claude-haiku-4-5-20251001-v1:0`
`BEDROCK_MODEL_CAPABLE` = `au.anthropic.claude-sonnet-4-6`

The task role may invoke only `au.anthropic.*` inference profiles. Foundation-model invoke is limited to Sydney (`ap-southeast-2`) and Melbourne (`ap-southeast-4`) — that is the AU CRIS destination set. `us.`, `eu.`, `jp.`, and `global.` profiles are not on the role. Terraform rejects a `bedrock_model_id` that does not start with `au.`. The buyer still enables Anthropic model access in the Bedrock console (one-time use-case form). Hermes reads `model.default` from EFS `config.yaml`; the listing image copies `HERMES_MODEL` into that file on start and refuses a non-`au.` id.

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
