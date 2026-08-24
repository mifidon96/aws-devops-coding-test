output "function_name" {
  description = "Lambda function name. The pipeline targets this for update-function-code."
  value       = aws_lambda_function.api.function_name
}

output "security_group_id" {
  description = "Lambda security group. Attached to the database SG as an allowed source from the root module."
  value       = aws_security_group.lambda.id
}

output "api_endpoint" {
  description = "Base URL of the HTTP API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}
