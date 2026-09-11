import re

_CPF_LENGTH = 11
_CNPJ_LENGTH = 14


def somente_digitos(valor: str) -> str:
    return re.sub(r"\D", "", valor or "")


def cpf_valido(valor: str) -> bool:
    """Mesmo algoritmo de dígito verificador usado em Cpf.java (app principal),
    reimplementado aqui porque a Lambda não compartilha código com o monólito Java."""
    numero = somente_digitos(valor)
    if len(numero) != _CPF_LENGTH:
        return False
    if len(set(numero)) == 1:
        return False

    soma = sum((10 - i) * int(numero[i]) for i in range(9))
    primeiro_dv = 11 - (soma % 11)
    primeiro_dv = 0 if primeiro_dv >= 10 else primeiro_dv
    if primeiro_dv != int(numero[9]):
        return False

    soma = sum((11 - i) * int(numero[i]) for i in range(10))
    segundo_dv = 11 - (soma % 11)
    segundo_dv = 0 if segundo_dv >= 10 else segundo_dv
    return segundo_dv == int(numero[10])
