data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
      ]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid    = "ReadRuntimeSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = compact([
      aws_secretsmanager_secret.runtime.arn,
      var.container_registry_credentials_secret_arn,
    ])
  }

  statement {
    sid       = "DecryptRuntimeSecret"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "runtime-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

data "aws_iam_policy_document" "task" {
  # checkov:skip=CKV_AWS_111:Polly DescribeVoices has no resource ARN
  # checkov:skip=CKV_AWS_356:License Manager and Bedrock List* have no resource ARN
  statement {
    sid       = "ListUploadsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.uploads.arn]
  }

  statement {
    sid    = "ManageUploadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }

  statement {
    sid       = "ListVaultBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.vault.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["vault/*"]
    }
  }

  statement {
    sid    = "ManageVaultObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.vault.arn}/vault/*"]
  }

  statement {
    sid       = "ListHermesStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.hermes.arn]
  }

  statement {
    sid    = "ManageHermesStateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.hermes.arn}/*"]
  }

  statement {
    sid    = "UseApplicationKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid    = "AmazonBedrockAuHaiku"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:GetInferenceProfile",
    ]
    resources = local.au_bedrock_invoke_resources
  }

  statement {
    sid    = "AmazonBedrockDiscover"
    effect = "Allow"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:ListInferenceProfiles",
      "bedrock:GetFoundationModel",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AmazonPolly"
    effect = "Allow"
    actions = [
      "polly:SynthesizeSpeech",
      "polly:DescribeVoices",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "HermesEfs"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess",
    ]
    resources = [aws_efs_file_system.hermes.arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.hermes.arn]
    }
  }

  dynamic "statement" {
    for_each = var.ses_from_email == "" ? [] : [1]
    content {
      sid    = "AmazonSesSend"
      effect = "Allow"
      actions = [
        "ses:SendEmail",
        "ses:SendRawEmail",
      ]
      resources = [
        "arn:${data.aws_partition.current.partition}:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
      ]
    }
  }

  statement {
    sid    = "AwsMarketplaceContainerLicense"
    effect = "Allow"
    # Resource * is required by AWS License Manager for these APIs.
    # https://docs.aws.amazon.com/marketplace/latest/userguide/container-license-manager-integration.html
    actions = [
      "license-manager:CheckoutLicense",
      "license-manager:GetLicense",
      "license-manager:CheckInLicense",
      "license-manager:ExtendLicenseConsumption",
      "license-manager:ListReceivedLicenses",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "yumaos-runtime"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
