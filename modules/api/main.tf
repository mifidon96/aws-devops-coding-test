###############################################################################
# API - Lambda + API Gateway (HTTP API)
#
# The two decisions that matter in this file:
#
#  1. ARTEFACT OWNERSHIP. Terraform packages app/ and creates the function, so
#     a bare `terraform apply` produces a working API. After that, the CI/CD
#     pipeline owns the code via `aws lambda update-function-code`. The
#     lifecycle ignore_changes block stops the next `terraform apply` from
#     reverting a pipeline deployment. Without it, infra applies and app
#     deploys silently fight each other.
#
#  2. The Lambda is VPC-ATTACHED so it can reach RDS on 1433. It reaches
#     Secrets Manager through the Interface VPC Endpoint from the networking
#     module - which is why no NAT Gateway exists in this design.
###############################################################################

locals {
  tags          = merge(var.tags, { Module = "api" })
  function_name = "${var.name_prefix}-api"
}

###############################################################################
# Packaging - zips app/ at plan time
###############################################################################

data "archive_file" "app" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${local.function_name}.zip"
}

###############################################################################
# Security group
#
# Same standalone-rule pattern as the database module. Egress only - the
# Lambda never receives inbound traffic; API Gateway invokes it via the
# Lambda service, not over the network.
###############################################################################

resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Lambda ENIs for the Node.js API"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-lambda-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_db" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "TDS to SQL Server"
  referenced_security_group_id = var.database_security_group_id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "lambda_https_vpc" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to VPC endpoints (Secrets Manager)"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

###############################################################################
# Execution role
###############################################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.tags
}

# Managed policy for creating ENIs in the VPC plus CloudWatch Logs access.
# Required for any VPC-attached Lambda; the ENI actions cannot be scoped to a
# resource by AWS design.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Least privilege: read exactly one secret, nothing else.
data "aws_iam_policy_document" "lambda_secrets" {
  statement {
    sid    = "ReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name   = "${local.function_name}-secrets"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secrets.json
}

###############################################################################
# Log group
#
# Created explicitly so retention is controlled. If Lambda creates it
# implicitly on first invoke, it defaults to never-expire.
###############################################################################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

###############################################################################
# Function
###############################################################################

resource "aws_lambda_function" "api" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256

  runtime = "nodejs20.x"
  handler = "index.handler"

  memory_size = var.memory_size
  timeout     = var.timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_NAME = var.db_secret_name
      DB_NAME        = var.db_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]

  tags = local.tags

  lifecycle {
    # The pipeline owns the deployed artefact after the initial apply.
    # See note 1 at the top of this file.
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }
}

###############################################################################
# HTTP API
#
# HTTP API (v2) rather than REST API: cheaper, lower latency. A $default
# catch-all route proxies everything to the Lambda, so adding endpoints is an
# application change, not an infrastructure change (requirement 1c).
###############################################################################

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-http-api"
  protocol_type = "HTTP"
  description   = "Front door for the ${var.name_prefix} Node.js WebAPI"

  tags = local.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id = aws_apigatewayv2_api.this.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  tags = local.tags
}

# Allows API Gateway (and only this API) to invoke the function.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
