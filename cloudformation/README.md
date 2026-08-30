# YumaOS on AWS ECS Fargate (CloudFormation)

Native CloudFormation for buyers who do not want Terraform. Same first-launch shape as the Terraform stack in this repo: VPC, ALB, one Fargate task (YumaOS web + Hermes sidecar — the only two Marketplace images), RDS PostgreSQL 16, ElastiCache Redis (TLS), Secrets Manager, KMS, uploads and vault buckets, and Hermes EFS.

Subscribe on AWS Marketplace before you create the stack. The images are Marketplace ECR, not GHCR. Pin the Region to `ap-southeast-2` so Australian Bedrock Haiku works.

## Console

1. Open CloudFormation in `ap-southeast-2`.
2. Create stack → With new resources → Upload a template file → `yumaos-fargate.yaml`.
3. Pin **Container image** and **Hermes container image** to a Marketplace ECR `sha-<7>` that already exists. Do not use `1.0.0`, `1.0.1`, or `1.0.2`. Listing tags are multi-arch (`linux/amd64` + `linux/arm64`). Set **CPU architecture** to `X86_64` or `ARM64` (Graviton). Product identity is baked into those images. **Marketplace product code** / **product ID** on the stack are documentary and cannot disable licensing.
4. Set **Allowed ingress CIDR** to your office, VPN, or client range. Leave **Allow internet ingress** false. `0.0.0.0/0` is rejected unless that flag is true.
5. Leave **ACM certificate ARN** and **SES From** empty for a first HTTP launch without mail.
6. Acknowledge IAM capabilities. Create.

When the stack is `CREATE_COMPLETE`, open the `ApplicationUrl` output. First user registers. Then lock signup if you want (`AUTH_DISABLE_SIGNUP=true` on a later update). No seed admin is baked into the image.

## CLI

```sh
cd cloudformation
cp parameters.example.json parameters.json
# edit MarketplaceProductCode, MarketplaceProductSku, ContainerImage, HermesContainerImage, AllowedIngressCidr

# Template is over the 51 KiB inline body limit; deploy uploads it to S3.
aws cloudformation deploy \
  --stack-name yumaos \
  --template-file yumaos-fargate.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides $(python3 -c 'import json; print(" ".join("%s=%s" % (p["ParameterKey"], p["ParameterValue"]) for p in json.load(open("parameters.json"))))')

aws cloudformation describe-stacks --stack-name yumaos \
  --query "Stacks[0].Outputs[?OutputKey=='ApplicationUrl'].OutputValue" \
  --output text
```

The YumaOS image entrypoint waits for Postgres, runs `CREATE EXTENSION vector`, applies Drizzle, then starts. Hermes must be healthy on `127.0.0.1:8642` before the web container starts. A separate migration task definition is an output if you want an explicit pre-roll.

## Bilateral localhost wiring

Do not point these at the public ALB or a Cloudflare hostname:

| Variable | Value |
| --- | --- |
| `HERMES_URL` | `http://127.0.0.1:8642` |
| `HERMES_DASHBOARD_URL` | `http://127.0.0.1:9119` |
| `HERMES_YUMAOS_MCP_URL` | `http://127.0.0.1:3000/api/hermes/mcp` |

## Optional parameters

| Parameter | Empty default | Later |
| --- | --- | --- |
| `CertificateArn` + `AppUrl` | HTTP ALB | ACM in the ALB Region. TLS terminates on the ALB. HTTP still forwards to the target group; HTTPS is added on 443. |
| `SesFromEmail` | No mail | Verified SES identity. Stack sets `EMAIL_PROVIDER=ses` and `ses:SendEmail` on the task role. |
| `DatabaseMultiAz` / `CacheHighAvailability` | Off | Production resilience. |
| `EnableAwsBackup` | Off | Daily AWS Backup of RDS, uploads, vault, and Hermes EFS. |
| `AllowedIngressCidr` | none (required) | Office, VPN, or client CIDR. |
| `AllowInternetIngress` | `false` | Set `true` only to allow `0.0.0.0/0` on the ALB. |

Dual-NAT (per-AZ egress) is Terraform-only.

## Destroy

Empty the uploads and vault buckets first if objects exist, then:

```sh
aws cloudformation delete-stack --stack-name yumaos
aws cloudformation wait stack-delete-complete --stack-name yumaos
```

RDS uses `DeletionPolicy: Delete` (no final snapshot) to match the Terraform test teardown. Change that in a fork before production data.
