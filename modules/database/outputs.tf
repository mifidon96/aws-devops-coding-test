output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "TDS port."
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Security group attached to the instance. Passed to the api module."
  value       = aws_security_group.db.id
}

output "secret_arn" {
  description = "Secrets Manager secret ARN. Granted to the Lambda execution role."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secret name, passed to the Lambda as an environment variable."
  value       = aws_secretsmanager_secret.db.name
}
