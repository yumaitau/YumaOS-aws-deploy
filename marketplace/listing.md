# AWS Marketplace listing copy

Seller Central fields for the YumaOS container product. Do not invent a product code or SKU here. Paste the values AWS issues into the CloudFormation and Terraform parameters.

## Short description

YumaOS is a single-tenant company operating system with AI agents. You run it in your AWS account on ECS Fargate. Yuma IT does not host your data.

## Long description

YumaOS gives one organisation a dedicated Next.js application and a Hermes sidecar that talk over localhost. Agents can draft work. Destructive actions queue for a human who holds `agents.approve`. There is no environment variable that turns that gate off.

The listing images are only those two containers. PostgreSQL and Redis are not shipped as images: the stack creates RDS PostgreSQL 16 (pgvector on migrate) and ElastiCache Redis with TLS in the buyer account, plus a two-AZ VPC, an Application Load Balancer, one Fargate task with YumaOS and Hermes on the same ENI, KMS, Secrets Manager, an uploads bucket, a vault bucket, a Hermes snapshot bucket, and encrypted EFS for the live Hermes home. Amazon Bedrock is pinned to Australian Haiku (`au.anthropic.claude-haiku-4-5-20251001-v1:0`) in `ap-southeast-2`.

You subscribe on AWS Marketplace, then launch from https://github.com/yumaitau/YumaOS-aws-deploy with CloudFormation or Terraform. The `docker pull` snippet AWS shows only proves the subscription can pull the images. It does not create the stack.

The YumaOS web image requires a current AWS Marketplace contract entitlement. It consumes one `standard_deployment` seat at start and revalidates every 15 minutes with `AWS::Marketplace::Usage` so the heartbeat does not consume another unit. Hermes is a public sidecar and is not license-gated. Copying the web image, changing environment variables, or cancelling the subscription does not keep YumaOS usable. Product identity is baked at image build; stack parameters cannot disable or retarget that check.

First visitor registers. Then lock public signup if you want. Support: https://os.yumait.com.au/contact

## Highlights

- Buyer-owned VPC, RDS, Redis, S3, EFS, and KMS. The publisher does not host your data.
- YumaOS and Hermes share one Fargate task and talk on `127.0.0.1`. Do not route that traffic through the ALB.
- Bedrock Australian Haiku in `ap-southeast-2`. No access keys in task definitions.
- Human approval on destructive agent actions. The gate has no off switch.
- Listing images are multi-arch (`linux/amd64` and `linux/arm64`). Choose `X86_64` or `ARM64` (Graviton) on the stack.
- Launch with CloudFormation or Terraform from the public deploy repository.

## Categories

Business Applications / Operations

## Support information

Yuma IT Pty Ltd (ABN 62 684 389 839)
49 Phillip Ave, Watson ACT 2602, Australia
https://os.yumait.com.au/contact
hello@yumait.com.au

Terms: https://os.yumait.com.au/terms
Refund policy: https://os.yumait.com.au/refund-policy

## End user license

Apache-2.0 applies to the deploy artifacts in this repository. The application images require an AWS Marketplace subscription. Customer use is also governed by the Terms and Refund policy on https://os.yumait.com.au/.
