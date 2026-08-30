# YumaOS on AWS ECS Fargate

Buyer launch path: clone https://github.com/yumaitau/YumaOS-aws-deploy and start from the repository README.

Terraform reference stack for a buyer-owned deployment in `ap-southeast-2`:

- Two-AZ VPC with public ALB subnets, private Fargate subnets, isolated data subnets, NAT egress, and an S3 gateway endpoint.
- One ECS Fargate task (`X86_64` or `ARM64`): YumaOS web + Hermes sidecar on the same ENI so they talk over `127.0.0.1`. Those are the only Marketplace listing images. Listing tags include both `linux/amd64` and `linux/arm64`.
- RDS PostgreSQL 16 and TLS-only ElastiCache Redis with no public route or public address. They are not container images.
- KMS-encrypted, versioned, public-blocked S3 uploads and vault buckets.
- Encrypted EFS access point for the live Hermes `/opt/data` home, plus a private S3 bucket for sqlite snapshots. Hermes does not receive `DATABASE_URL`; migrate reserves a `hermes` Postgres schema for a future state backend.
- Bedrock Australian Haiku pinned on the task role. No AWS access keys enter task definitions.
- CloudWatch logs and Container Insights, ALB readiness checks, optional WAF, and optional AWS Backup.

## Prerequisites

- Terraform 1.8 or newer.
- AWS CLI authenticated to the intended account.
- Buyer account Bedrock access for `au.anthropic.claude-haiku-4-5-20251001-v1:0` in `ap-southeast-2`.
- Immutable listing tags containing `linux/amd64` and `linux/arm64`. Pin a `sha-<7>` that already exists. Do not use `1.0.0`, `1.0.1`, or `1.0.2`. Set `cpu_architecture` to `X86_64` or `ARM64`.
- The listing images require a current Marketplace contract entitlement. Terraform variables cannot disable that check.
- `web_desired_count` must stay 1 (`MaxCount=1`). Leave `enable_deployment_rollback` false until the service already exists.
- ECS container health checks use `node` (web `/livez`) and `python3` (Hermes `/health`). The listing images do not ship `curl`.

Never put secrets in `terraform.tfvars`. Terraform state contains generated database/application secrets; use an encrypted remote backend for production.

## Clean-account deployment

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply -var-file=terraform.tfvars
terraform output application_url
```

The image entrypoint waits for Postgres, applies Drizzle (`CREATE EXTENSION vector` included), then starts. Hermes must be healthy before the web container starts. First visitor registers. Leave `ses_from_email` empty until that first account exists.

`./bootstrap.sh` is optional. Ordinary `terraform apply` is enough.

## Production switches

```hcl
app_url                      = "https://yumaos.example.com"
certificate_arn              = "arn:aws:acm:ap-southeast-2:...:certificate/..."
allowed_ingress_cidrs        = ["203.0.113.0/24"]
allow_internet_ingress       = false
database_multi_az            = true
database_deletion_protection = true
cache_high_availability      = true
single_nat_gateway           = false
enable_aws_backup            = true
force_destroy_backup_vault   = false
force_destroy_data_buckets   = false
```

HTTPS is ACM on the ALB. Outbound email is optional (`ses_from_email`) and attaches `ses:SendEmail` only when set.

## Destroy

```sh
YUMAOS_ALLOW_DESTROY=yes ./destroy.sh -var-file=terraform.tfvars
```
