# YumaOS AWS Marketplace deploy

Public buyer artifacts for YumaOS on AWS Marketplace. Subscribe on the listing **before** you pull the images or create a stack. The publisher does not host your data.

This repository is CloudFormation, Terraform, and IAM only. The Marketplace listing ships **two** container images — the web app and Hermes. Postgres and Redis are not images; the stack creates RDS PostgreSQL 16 and ElastiCache Redis in the buyer account.

```text
709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws
709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-hermes
```

AWS Marketplace always shows `docker login` + `docker pull` for container listings. That snippet only proves the subscription can pull the images. It does not create VPC, ECS, RDS, Redis, S3, EFS, or IAM. Use this repo to launch the product.

## What the stack creates

- Two-AZ VPC, public ALB, private Fargate, isolated data subnets, NAT egress, S3 gateway endpoint, VPC flow logs
- One ECS Fargate task with **two containers on the same ENI**:
  - `web` — YumaOS on `:3000`
  - `hermes` — Hermes Agent on `:8642` (dashboard `:9119`)
  - Listing tags are multi-arch (`linux/amd64` + `linux/arm64`). Set **Cpu architecture** to `X86_64` or `ARM64` (Graviton). Both containers follow that choice.
- Bilateral localhost wiring (do not change these):
  - `HERMES_URL=http://127.0.0.1:8642`
  - `HERMES_DASHBOARD_URL=http://127.0.0.1:9119`
  - `HERMES_YUMAOS_MCP_URL=http://127.0.0.1:3000/api/hermes/mcp`
- RDS PostgreSQL 16 (pgvector via `CREATE EXTENSION` on migrate) and TLS-only ElastiCache Redis
- KMS-encrypted uploads bucket, vault bucket, and Hermes EFS home
- Amazon Bedrock pinned to Australian Haiku: `au.anthropic.claude-haiku-4-5-20251001-v1:0` in `ap-southeast-2`
- Secrets Manager, CloudWatch, optional WAF, optional AWS Backup

The buyer account must have Bedrock model access for that Australian inference profile. The stack does not create access keys.

## ECS Fargate — CloudFormation

```sh
git clone https://github.com/yumaitau/YumaOS-aws-deploy.git
cd YumaOS-aws-deploy/cloudformation
cp parameters.example.json parameters.json
```

Console: Create stack → Upload `yumaos-fargate.yaml` → set **ContainerImage**, **HermesContainerImage**, **CpuArchitecture** (`X86_64` or `ARM64`), **MarketplaceProductCode**, **MarketplaceProductSku** → set **AllowedIngressCidr** → acknowledge IAM → Create. Do not use `0.0.0.0/0` unless **AllowInternetIngress** is true.

Details: [`cloudformation/README.md`](cloudformation/README.md). Seller Central copy lives in [`marketplace/`](marketplace/).

## ECS Fargate — Terraform

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
# pin both images to a Marketplace ECR sha-<7> that exists (not 1.0.0, 1.0.1, or 1.0.2)
# set marketplace codes; set allowed_ingress_cidrs
terraform init
terraform apply -var-file=terraform.tfvars
terraform output application_url
```

The listing image requires a current AWS Marketplace entitlement. Copying the image does not keep the product usable after the subscription ends. There is no environment variable that turns the check off.

First visitor registers (signup is open). Then set `AUTH_DISABLE_SIGNUP=true` in a follow-up if you want to lock public registration. No seed admin is baked into the image.

Full variable notes: [`terraform/README.md`](terraform/README.md).

## Health

- `GET /livez` — process liveness
- `GET /readyz` — configuration, database, and storage (503 if dependencies are down)
- Hermes sidecar: `GET http://127.0.0.1:8642/health` from inside the task

## Cost

You pay AWS directly for Fargate, ALB, NAT, RDS, ElastiCache, S3, EFS, KMS, Secrets Manager, CloudWatch, Bedrock tokens, and optional WAF/Backup. Marketplace contract charges are separate.

## Destroy

CloudFormation:

```sh
aws cloudformation delete-stack --stack-name yumaos
```

Terraform:

```sh
cd terraform
YUMAOS_ALLOW_DESTROY=yes ./destroy.sh -var-file=terraform.tfvars
```

Empty the uploads and vault buckets first if objects exist.

## CI

Pushes and pull requests to `main` run [`.github/workflows/security.yml`](.github/workflows/security.yml): Terraform fmt and validate, Checkov, Gitleaks, and Trivy.

## Support

https://os.yumait.com.au/contact
