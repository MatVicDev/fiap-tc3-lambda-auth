variable "aws_region" {
  description = "Região AWS onde a Lambda e o API Gateway são criados"
  type        = string
  default     = "us-east-1"
}

variable "ambiente" {
  description = "Nome do ambiente (homologacao | producao) — usado em tags e nomes de recursos"
  type        = string
  default     = "homologacao"
}

variable "db_name" {
  description = "Nome do banco de dados da oficina"
  type        = string
  default     = "oficina"
}

variable "jwt_expiration_ms" {
  description = "Validade do token emitido, em milissegundos — deve bater com JWT_EXPIRATION da aplicação principal"
  type        = string
  default     = "86400000"
}

variable "lambda_zip_path" {
  description = "Caminho do artefato .zip da função, gerado pelo pipeline de CI/CD"
  type        = string
  default     = "../build/lambda.zip"
}
