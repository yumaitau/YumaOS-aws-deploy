# Usage instructions (Seller Central)

1. Subscribe to YumaOS on AWS Marketplace. Wait until the subscription is active before you pull images or create a stack.
2. Open https://github.com/yumaitau/YumaOS-aws-deploy. Use CloudFormation (`cloudformation/yumaos-fargate.yaml`) or Terraform (`terraform/`).
3. Create the stack in **ap-southeast-2**. Australian Bedrock Haiku is not available as this listing's default in other Regions.
4. Pin both listing images from Marketplace ECR (web + Hermes only) to a `sha-<7>` tag that already exists. Do not use `:latest`. Do not use `1.0.0` or `1.0.1` (no license gate) or `1.0.2` (arm64-only, heartbeat consumed a second seat). AWS Marketplace ECR does not let sellers delete those tags. A version tag (`1.0.3` or later) is only valid after it has been created from a proven multi-arch sha. Set **Cpu architecture** to `X86_64` or `ARM64` (Graviton). Both containers in the task use that value. To pin one architecture, use the `:tag-amd64` or `:tag-arm64` suffix and match the task architecture. Postgres is the RDS instance this stack creates, not a third image.

   ```text
   709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws
   709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-hermes
   ```

5. The published YumaOS web image consumes one contract seat at start (`CheckoutLicense` `PROVISIONAL`, dimension `standard_deployment`, `Count=1`) and revalidates every 15 minutes with `AWS::Marketplace::Usage` (`Unit=None`) so the heartbeat does not draw a second unit. Hermes is a public sidecar and is not license-gated. Task-definition environment variables cannot disable the web check. Product identity is baked into the web image at build. `MarketplaceProductCode` / `MarketplaceProductSku` on the stack are documentary.
6. Set `AllowedIngressCidr` / `allowed_ingress_cidrs` to your office, VPN, or client CIDR. Leave `AllowInternetIngress` / `allow_internet_ingress` false. `0.0.0.0/0` is rejected unless that flag is true.
7. Confirm the buyer account has Bedrock model access for `au.anthropic.claude-haiku-4-5-20251001-v1:0` in `ap-southeast-2`.
8. Create the stack. The YumaOS entrypoint waits for Postgres, creates the `vector` extension, reserves the `hermes` schema, migrates, then starts. Hermes home is EFS; sqlite snapshots go to the Hermes S3 bucket. Hermes must be healthy on `127.0.0.1:8642` before the web container starts.
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
