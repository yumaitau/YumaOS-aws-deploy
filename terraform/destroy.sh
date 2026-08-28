#!/usr/bin/env bash
set -euo pipefail

if [[ "${YUMAOS_ALLOW_DESTROY:-}" != "yes" ]]; then
  echo "Refusing destroy. Set YUMAOS_ALLOW_DESTROY=yes after checking account, region, and workspace." >&2
  exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proof_file="${script_dir}/../marketplace/proof/aws-fargate-deploy.md"

cd "${script_dir}"
account_id=$(terraform output -raw aws_account_id)
region=$(terraform output -raw aws_region)

echo "Destroying YumaOS resources in AWS account ${account_id}, region ${region}."
terraform destroy -auto-approve "$@"

destroyed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ -f "${proof_file}" ]]; then
  cat >>"${proof_file}" <<EOF

Destroy completed: ${destroyed_at} in account ${account_id}, region ${region}.
EOF
fi

echo "Destroy complete."
