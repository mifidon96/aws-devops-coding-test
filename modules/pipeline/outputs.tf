output "deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.deploy.arn
}

output "artefact_bucket" {
  description = "Set as the ARTEFACT_BUCKET repository variable in GitHub."
  value       = aws_s3_bucket.artefacts.id
}
