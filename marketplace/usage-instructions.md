# Usage instructions (Seller Central)

1. Subscribe to YumaOS on AWS Marketplace. Wait until the subscription is active before you pull images or create a stack.
2. Open https://github.com/yumaitau/YumaOS-aws-deploy. Use CloudFormation (`cloudformation/yumaos-fargate.yaml`) or Terraform (`terraform/`).
3. Create the stack in **ap-southeast-2**. Australian Bedrock Haiku is not available as this listing's default in other Regions.
4. Pin both images from Marketplace ECR. Do not use `:latest`.

   ```text
   709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws
   709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-hermes
   ```

5. Set `MarketplaceProductCode` and `MarketplaceProductSku` (Terraform: `marketplace_product_code`, `marketplace_product_sku`) from the listing. The published image always checks out a Marketplace license. Empty, omitted, or overridden values fail the task; they do not disable the check.
6. Set `AllowedIngressCidr` / `allowed_ingress_cidrs` to your office, VPN, or client CIDR. Leave `AllowInternetIngress` / `allow_internet_ingress` false. `0.0.0.0/0` is rejected unless that flag is true.
7. Confirm the buyer account has Bedrock model access for `au.anthropic.claude-haiku-4-5-20251001-v1:0` in `ap-southeast-2`.
8. Create the stack. The YumaOS entrypoint waits for Postgres, creates the `vector` extension, migrates, then starts. Hermes must be healthy on `127.0.0.1:8642` before the web container starts.
9. Open the `ApplicationUrl` output. Register the first administrator. Then set `AUTH_DISABLE_SIGNUP=true` if you want to lock public registration.
10. Health: `GET /livez` (process) and `GET /readyz` (database). Hermes health is `http://127.0.0.1:8642/health` inside the task only.
11. Optional later: ACM certificate + `AppUrl` for HTTPS; verified SES identity for mail; Multi-AZ RDS; Redis HA; AWS Backup.

Do not change these environment values. They are how the two containers talk without leaving the task:

```text
HERMES_URL=http://127.0.0.1:8642
HERMES_DASHBOARD_URL=http://127.0.0.1:9119
HERMES_YUMAOS_MCP_URL=http://127.0.0.1:3000/api/hermes/mcp
```

You pay AWS directly for Fargate, ALB, NAT, RDS, ElastiCache, S3, EFS, KMS, Secrets Manager, CloudWatch, Bedrock tokens, and optional WAF/Backup. Marketplace contract charges are separate.
