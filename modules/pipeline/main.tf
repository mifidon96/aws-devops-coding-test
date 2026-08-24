###############################################################################
# Pipeline - GitHub Actions deployment identity
#
# The decision that matters: NO LONG-LIVED KEYS. GitHub Actions assumes an IAM
# role via OIDC federation. There are no AWS access keys stored in repository
# secrets - nothing to leak, rotate, or revoke.
#
# The trust policy is scoped by `sub` to ONE repository and ONE branch. A
# wildcard like repo:org/repo:* would let any branch - including a pull
# request from a fork - assume the role. That is a well-known real-world
# misconfiguration, and the reason the condition below is exact-match.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  tags = merge(var.tags, { Module = "pipeline" })

  # e.g. repo:morgan-github/aws-devops-coding-test:ref:refs/heads/main
  allowed_subject = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.allowed_branch}"
}

###############################################################################
# OIDC provider
#
# Only ONE provider for token.actions.githubusercontent.com can exist per AWS
# account. If the sandbox already has one, set create_oidc_provider = false
# and pass its ARN instead. Check with:
#   aws iam list-open-id-connect-providers
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer validates this thumbprint for GitHub's provider, but the
  # API still requires the field to be populated.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.tags, { Name = "github-actions-oidc" })
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

###############################################################################
# Artefact bucket
#
# Versioned so a bad deploy can be rolled back to a previous object version.
# Account ID in the name because S3 bucket names are globally unique.
###############################################################################

resource "aws_s3_bucket" "artefacts" {
  bucket        = "${var.name_prefix}-artefacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # dev convenience: allows destroy while objects exist

  tags = merge(local.tags, { Name = "${var.name_prefix}-artefacts" })
}

resource "aws_s3_bucket_versioning" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artefacts" {
  bucket = aws_s3_bucket.artefacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# Deploy role
###############################################################################

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.allowed_subject]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name_prefix}-gha-deploy"
  description          = "Assumed by GitHub Actions to deploy application code"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
  max_session_duration = 3600

  tags = local.tags
}

# Least privilege: write to one bucket, update one function. No wildcards on
# the Lambda ARN - the role cannot touch any other function in the account.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid    = "PublishArtefacts"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.artefacts.arn}/*"]
  }

  statement {
    sid    = "UpdateFunctionCode"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_function_name}",
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name_prefix}-gha-deploy-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
