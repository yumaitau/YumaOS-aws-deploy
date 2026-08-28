#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proof_file="${script_dir}/../marketplace/proof/aws-fargate-deploy.md"
terraform_args=("$@")

for command in terraform aws jq curl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

cd "${script_dir}"
terraform init

# Clean-account bootstrap: build data plane and task definitions first, run
# migration, then create long-running services only after migration succeeds.
terraform apply -auto-approve "${terraform_args[@]}" -var enable_services=false

region=$(terraform output -raw aws_region)
cluster=$(terraform output -raw ecs_cluster_name)
migration_definition=$(terraform output -raw migration_task_definition_arn)
security_group=$(terraform output -raw task_security_group_id)
subnets=$(terraform output -json application_subnet_ids | jq -r 'join(",")')
network="awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${security_group}],assignPublicIp=DISABLED}"

run_task() {
  local label=$1
  local overrides=${2:-}
  local args=(
    ecs run-task
    --region "${region}"
    --cluster "${cluster}"
    --launch-type FARGATE
    --platform-version LATEST
    --task-definition "${migration_definition}"
    --network-configuration "${network}"
  )
  if [[ -n "${overrides}" ]]; then
    args+=(--overrides "${overrides}")
  fi

  local task_arn
  task_arn=$(aws "${args[@]}" --query 'tasks[0].taskArn' --output text)
  if [[ -z "${task_arn}" || "${task_arn}" == "None" ]]; then
    echo "${label} task did not start" >&2
    exit 1
  fi

  aws ecs wait tasks-stopped --region "${region}" --cluster "${cluster}" --tasks "${task_arn}"

  local exit_code
  exit_code=$(aws ecs describe-tasks \
    --region "${region}" \
    --cluster "${cluster}" \
    --tasks "${task_arn}" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)
  if [[ "${exit_code}" != "0" ]]; then
    aws ecs describe-tasks \
      --region "${region}" \
      --cluster "${cluster}" \
      --tasks "${task_arn}" \
      --query 'tasks[0].{stoppedReason:stoppedReason,containers:containers[].{name:name,reason:reason,exitCode:exitCode}}'
    exit 1
  fi

  printf '%s' "${task_arn}"
}

migration_task_arn=$(run_task "migration")

proof_key="uploads/deployment-proof-$(date -u +%Y%m%dT%H%M%SZ).txt"
proof_script="const {S3Client,PutObjectCommand}=require('@aws-sdk/client-s3');new S3Client({}).send(new PutObjectCommand({Bucket:process.env.S3_BUCKET,Key:process.env.STORAGE_PROOF_KEY,Body:'YumaOS Fargate storage proof\\n',ContentType:'text/plain'})).then(()=>console.log('stored '+process.env.STORAGE_PROOF_KEY)).catch(e=>{console.error(e);process.exit(1)})"
storage_overrides=$(jq -nc \
  --arg key "${proof_key}" \
  --arg script "${proof_script}" \
  '{containerOverrides:[{name:"migration",command:["node","-e",$script],environment:[{name:"STORAGE_PROOF_KEY",value:$key}]}]}')
storage_task_arn=$(run_task "storage proof" "${storage_overrides}")

terraform apply -auto-approve "${terraform_args[@]}" -var enable_services=true

application_url=$(terraform output -raw application_url)
for attempt in $(seq 1 30); do
  if live_response=$(curl -fsS "${application_url}/livez") && ready_response=$(curl -fsS "${application_url}/readyz"); then
    break
  fi
  if [[ "${attempt}" == "30" ]]; then
    echo "Health probes did not become ready: ${application_url}" >&2
    exit 1
  fi
  sleep 10
done

account_id=$(terraform output -raw aws_account_id)
image=$(terraform output -raw container_image)
hermes_image=$(terraform output -raw hermes_container_image)
web_definition=$(terraform output -raw web_task_definition_arn)
bucket=$(terraform output -raw uploads_bucket_name)
vault_bucket=$(terraform output -raw vault_bucket_name)
efs_id=$(terraform output -raw hermes_file_system_id)
log_group=$(terraform output -raw migration_log_group_name)
deployed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$(dirname "${proof_file}")"
cat >"${proof_file}" <<EOF
# AWS Fargate deployment proof

- Recorded: ${deployed_at}
- AWS account: ${account_id}
- Region: ${region}
- URL: ${application_url}
- YumaOS image: \`${image}\`
- Hermes image: \`${hermes_image}\`
- Web task definition: \`${web_definition}\`
- Migration task: \`${migration_task_arn}\`
- Storage proof task: \`${storage_task_arn}\`
- CloudWatch log group: \`${log_group}\`
- Uploads bucket: \`${bucket}\`
- Vault bucket: \`${vault_bucket}\`
- Hermes EFS: \`${efs_id}\`
- Storage proof object: \`s3://${bucket}/${proof_key}\`

## Probe results

\`/livez\`:

\`\`\`json
$(printf '%s' "${live_response}" | jq -c .)
\`\`\`

\`/readyz\`:

\`\`\`json
$(printf '%s' "${ready_response}" | jq -c .)
\`\`\`

## Teardown

Not yet recorded. Run \`YUMAOS_ALLOW_DESTROY=yes ./destroy.sh <same Terraform arguments>\`.
EOF

echo "Deployment healthy: ${application_url}"
echo "Proof written: ${proof_file}"
