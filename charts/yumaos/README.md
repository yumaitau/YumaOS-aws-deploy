# YumaOS on Amazon EKS

Helm chart for buyers who want EKS instead of the ECS Fargate stack in this
repo. **Helm does not create the data plane.** Provision RDS PostgreSQL 16,
ElastiCache Redis, S3, KMS, and (for Hermes state) EFS yourself, then install
this chart.

Seller Central EKS delivery can point at this chart. The listing images are
still Marketplace ECR, not GHCR.

## Why one pod

YumaOS and Hermes must call each other on `127.0.0.1`. On ECS that is one
Fargate task / one ENI. On EKS that is **one pod, two containers**. Two
Deployments, a Service mesh hop, or routing Hermes through Ingress breaks
MCP and chat.

`replicaCount` is hard-capped at **1**. The contract dimension is
`standard_deployment` `MaxCount=1`. A second web container fails
`CheckoutLicense` and the install dies.

## License Manager on EKS

ECS injects the **task role**. EKS does not. The web container calls
`CheckoutLicense` with the default AWS SDK credential chain. Without IRSA or
EKS Pod Identity the process exits `credentials_missing`.

1. Create an IAM role whose trust policy allows this chart's ServiceAccount
   (`eks.amazonaws.com/role-arn` annotation) **or** associate the role with
   EKS Pod Identity.
2. Attach [`iam-policy.json`](../../iam-policy.json) (License Manager
   `Resource: *` plus Bedrock). Add S3, KMS, EFS, and optional SES to that
   same role.
3. Leave `serviceAccount.automount` **true**. IRSA needs the projected token.
4. Set `env.AWS_REGION=ap-southeast-2`. IRSA does not set it. The listing
   image refuses to start without it.
5. Do not drop `web.securityContext.supplementaryGroups: [10000]`. Pod
   `fsGroup` is 10000 for Hermes / EFS, so the projected token is group
   10000. Web runs as uid 1001; without that supplementary group it exits
   `credentials_missing` even when the role annotation is correct.

Do not put `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in `secretEnv`.
Do not add `SKIP_LICENSE`, `DISABLE_LICENSE`, or `YUMA_DISTRIBUTION`. Those
switches are ignored or must not exist.

Hermes is not license-gated. Only the web container checks out a seat.

## Marketplace ECR pulls

After you subscribe, your account may pull:

```text
709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-aws
709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/yumaos-hermes
```

Default EKS nodes authenticate to **your** ECR, not this Marketplace registry.
A docker-registry secret works:

```sh
aws ecr get-login-password --region us-east-1 \
  | kubectl create secret docker-registry marketplace-ecr \
      --docker-server=709825985650.dkr.ecr.us-east-1.amazonaws.com \
      --docker-username=AWS \
      --docker-password-stdin \
      --namespace yumaos
```

That password lasts **12 hours**. Refresh it (CronJob) or configure the node
kubelet ECR credential provider for `709825985650.dkr.ecr.us-east-1.amazonaws.com`.

## Install

```sh
helm upgrade --install yumaos charts/yumaos \
  --namespace yumaos --create-namespace \
  -f charts/yumaos/values-aws-marketplace.yaml \
  --set env.BETTER_AUTH_URL=https://yumaos.example.com \
  --set env.NEXT_PUBLIC_BETTER_AUTH_URL=https://yumaos.example.com \
  --set env.S3_BUCKET=<uploads-bucket> \
  --set image.tag=<sha-7-that-exists> \
  --set hermes.image.tag=<same-sha-7> \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::ACCOUNT:role/yumaos \
  --set secretEnv.DATABASE_URL='postgresql://...' \
  --set secretEnv.REDIS_URL='rediss://...' \
  --set secretEnv.BETTER_AUTH_SECRET='...' \
  --set secretEnv.ENCRYPTION_KEY='...' \
  --set secretEnv.YUMA_VAULT_KMS_KEY_ARN='...' \
  --set secretEnv.HERMES_API_KEY='...'
```

Pin a `sha-<7>` that already exists. Do not launch `1.0.0`, `1.0.1`, or
`1.0.2`. Do not invent a `1.0.N` tag that has not been created from a proven
multi-arch sha.

Leave `web.command` empty. Kubernetes `command` replaces Docker ENTRYPOINT, so
setting it skips `entrypoint.sh` (license gate + migrate). Hermes uses `args`
only so s6 still starts. Both containers use a read-only root filesystem;
writable paths are emptyDir (and Hermes `/opt/data`).

## Probes

Kubernetes `httpGet` probes are executed by kubelet. They do **not** need
`curl` inside the image. ECS container health checks do, which is why the
Fargate templates use `node` / `python3` instead of `curl`.

- Web liveness / startup: `/livez`
- Web readiness: `/readyz` (database and storage)
- Hermes: `/health` on `8642`

## Persistence

`hermes.persistence.enabled` defaults to `emptyDir`. That is first-launch
only — Hermes home dies with the pod. For production set a StorageClass
(EFS CSI on EC2 node groups). EKS Fargate + EFS needs extra pod security
groups; EC2 node groups are the simpler path.

## First user

Signup is open. Register the first administrator, then set
`AUTH_DISABLE_SIGNUP=true` if you want to lock public registration.
