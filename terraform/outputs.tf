output "api_endpoint" {
  description = "URL pública do endpoint de autenticação por CPF"
  value       = "${aws_apigatewayv2_api.auth.api_endpoint}/auth/cpf"
}

output "jwt_secret_arn" {
  description = "ARN do secret compartilhado com a aplicação principal"
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.auth_cpf.function_name
}
