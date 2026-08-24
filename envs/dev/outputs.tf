output "api_endpoint" {
  description = "Base URL of the deployed API. Try: curl <api_endpoint>/health"
  value       = module.api.api_endpoint
}

output "lambda_function_name" {
  description = "GitHub repository variable: LAMBDA_FUNCTION_NAME"
  value       = module.api.function_name
}

output "artefact_bucket" {
  description = "GitHub repository variable: ARTEFACT_BUCKET"
  value       = module.pipeline.artefact_bucket
}

output "deploy_role_arn" {
  description = "GitHub repository variable: AWS_DEPLOY_ROLE_ARN"
  value       = module.pipeline.deploy_role_arn
}

output "db_endpoint" {
  description = "RDS endpoint. Private - reachable only from inside the VPC."
  value       = module.database.endpoint
}
