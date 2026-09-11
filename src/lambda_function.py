import json
import logging
import os
import time
import uuid

import boto3
import jwt
import psycopg2

from cpf_validator import cpf_valido, somente_digitos

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_secrets_client = boto3.client("secretsmanager")

# Cache em escopo de módulo: sobrevive entre invocações no mesmo ambiente de
# execução (warm start), evitando uma chamada ao Secrets Manager por requisição.
_cache = {}


def _get_secret(env_var_arn_name):
    if env_var_arn_name not in _cache:
        arn = os.environ[env_var_arn_name]
        valor = _secrets_client.get_secret_value(SecretId=arn)["SecretString"]
        _cache[env_var_arn_name] = valor
    return _cache[env_var_arn_name]


def _db_connection():
    creds = json.loads(_get_secret("DB_SECRET_ARN"))
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=creds["username"],
        password=creds["password"],
        connect_timeout=5,
    )


def _resposta(status_code, corpo, correlation_id):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "X-Correlation-Id": correlation_id,
        },
        "body": json.dumps(corpo),
    }


def handler(event, context):
    correlation_id = (event.get("headers") or {}).get("X-Correlation-Id") or str(uuid.uuid4())
    log = {"correlationId": correlation_id, "requestId": getattr(context, "aws_request_id", None)}

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        logger.warning(json.dumps({**log, "event": "payload_invalido"}))
        return _resposta(400, {"erro": "Corpo da requisição inválido"}, correlation_id)

    cpf_bruto = body.get("cpf")
    if not cpf_bruto or not cpf_valido(cpf_bruto):
        logger.warning(json.dumps({**log, "event": "cpf_invalido"}))
        return _resposta(400, {"erro": "CPF inválido"}, correlation_id)

    cpf = somente_digitos(cpf_bruto)

    try:
        with _db_connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT status FROM clientes WHERE cpf = %s", (cpf,))
            row = cur.fetchone()
    except Exception:
        logger.exception(json.dumps({**log, "event": "erro_consulta_cliente"}))
        return _resposta(502, {"erro": "Falha ao consultar cadastro do cliente"}, correlation_id)

    if row is None:
        logger.info(json.dumps({**log, "event": "cliente_nao_encontrado"}))
        return _resposta(404, {"erro": "Cliente não cadastrado"}, correlation_id)

    status = row[0]
    if status != "ATIVO":
        logger.info(json.dumps({**log, "event": "cliente_inativo"}))
        return _resposta(403, {"erro": "Cliente inativo"}, correlation_id)

    jwt_secret = _get_secret("JWT_SECRET_ARN")
    expiracao_ms = int(os.environ.get("JWT_EXPIRATION_MS", "86400000"))
    agora = int(time.time())

    # Mesmo formato de claims usado pelo JWTService.java do monólito (sub + role +
    # iat/exp com HS256) para que o token seja aceito pelo JWTFilter sem alterações.
    token = jwt.encode(
        {
            "sub": cpf,
            "role": "CLIENTE",
            "iat": agora,
            "exp": agora + (expiracao_ms // 1000),
        },
        jwt_secret,
        algorithm="HS256",
    )

    logger.info(json.dumps({**log, "event": "token_emitido"}))
    return _resposta(200, {"token": token}, correlation_id)
