terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend remoto (S3 + DynamoDB lock) — preencher com o bucket/tabela reais
  # antes do primeiro `terraform init`. Mantido comentado para não quebrar o
  # `init` local enquanto a conta AWS do desafio ainda não existe.
  # backend "s3" {
  #   bucket         = "fiap-tc3-terraform-state"
  #   key            = "lambda-auth/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "fiap-tc3-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}
