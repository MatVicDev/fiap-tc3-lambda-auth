import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cpf_validator import cpf_valido, somente_digitos


def test_cpf_valido_aceita_cpf_correto():
    assert cpf_valido("123.456.789-09")


def test_cpf_valido_rejeita_digitos_verificadores_errados():
    assert not cpf_valido("123.456.789-00")


def test_cpf_valido_rejeita_tamanho_errado():
    assert not cpf_valido("123456789")


def test_cpf_valido_rejeita_todos_digitos_iguais():
    assert not cpf_valido("111.111.111-11")


def test_cpf_valido_rejeita_vazio_ou_none():
    assert not cpf_valido("")
    assert not cpf_valido(None)


def test_somente_digitos_remove_formatacao():
    assert somente_digitos("123.456.789-09") == "12345678909"
