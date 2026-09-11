# Rede e banco provisionados pelos repositórios irmãos (infra-k8s dono da VPC,
# infra-db dono do RDS) — lidos via SSM em vez de remote state cruzado, já que
# cada repositório tem pipeline e ciclo de vida independentes.
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/fiap-tc3/${var.ambiente}/private-subnet-ids"
}

data "aws_ssm_parameter" "lambda_security_group_id" {
  name = "/fiap-tc3/${var.ambiente}/lambda-security-group-id"
}

data "aws_ssm_parameter" "rds_endpoint" {
  name = "/fiap-tc3/${var.ambiente}/rds-endpoint"
}

data "aws_ssm_parameter" "rds_secret_arn" {
  name = "/fiap-tc3/${var.ambiente}/rds-secret-arn"
}

# Secret compartilhado entre esta Lambda e a aplicação principal (fiap-TC1-oficina):
# gerado uma única vez aqui para não haver duas fontes de verdade para a chave JWT.
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "fiap-tc3/${var.ambiente}/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

# Publicado em SSM para que o repositório da aplicação principal (fiap-TC1-oficina)
# consiga ler o ARN do secret no deploy sem precisar de acesso ao state deste repo.
resource "aws_ssm_parameter" "jwt_secret_arn" {
  name  = "/fiap-tc3/${var.ambiente}/jwt-secret-arn"
  type  = "String"
  value = aws_secretsmanager_secret.jwt_secret.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "fiap-tc3-auth-cpf-${var.ambiente}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_read_secrets" {
  name = "read-jwt-and-db-secrets"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.jwt_secret.arn, data.aws_ssm_parameter.rds_secret_arn.value]
    }]
  })
}

resource "aws_lambda_function" "auth_cpf" {
  function_name = "fiap-tc3-auth-cpf-${var.ambiente}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 256

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  vpc_config {
    subnet_ids         = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
    security_group_ids = [data.aws_ssm_parameter.lambda_security_group_id.value]
  }

  environment {
    variables = {
      DB_HOST           = data.aws_ssm_parameter.rds_endpoint.value
      DB_NAME           = var.db_name
      DB_SECRET_ARN     = data.aws_ssm_parameter.rds_secret_arn.value
      JWT_SECRET_ARN    = aws_secretsmanager_secret.jwt_secret.arn
      JWT_EXPIRATION_MS = var.jwt_expiration_ms
    }
  }

  tags = {
    ambiente = var.ambiente
    projeto  = "fiap-tc3-oficina"
  }
}

resource "aws_cloudwatch_log_group" "auth_cpf" {
  name              = "/aws/lambda/${aws_lambda_function.auth_cpf.function_name}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_api" "auth" {
  name          = "fiap-tc3-auth-${var.ambiente}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.auth.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_apigatewayv2_integration" "auth_cpf" {
  api_id                 = aws_apigatewayv2_api.auth.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth_cpf.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id    = aws_apigatewayv2_api.auth.id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_cpf.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.auth.execution_arn}/*/*"
}
