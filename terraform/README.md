# YumaOS on AWS ECS Fargate

Buyer launch path: clone https://github.com/yumaitau/YumaOS-aws-deploy and start from the repository README.

Terraform reference stack for a buyer-owned deployment in `ap-southeast-2`:

- Two-AZ VPC with public ALB subnets, private Fargate subnets, isolated data subnets, NAT egress, and an S3 gateway endpoint.
- One ECS Fargate `X86_64` task: YumaOS web + Hermes sidecar on the same ENI so they talk over `127.0.0.1`.
- RDS PostgreSQL 16 and TLS-only ElastiCache Redis with no public route or public address.
- KMS-encrypted, versioned, public-blocked S3 uploads and vault buckets.
- Encrypted EFS access point for Hermes `/opt/data`.
- Bedrock Australian Haiku pinned on the task role. No AWS access keys enter task definitions.
- CloudWatch logs and Container Insights, ALB readiness checks, optional WAF, and optional AWS Backup.

## Prerequisites

- Terraform 1.8 or newer.
- AWS CLI authenticated to the intended account.
- Buyer account Bedrock access for `au.anthropic.claude-haiku-4-5-20251001-v1:0` in `ap-southeast-2`.
- Immutable multi-architecture images containing `linux/amd64`.

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
