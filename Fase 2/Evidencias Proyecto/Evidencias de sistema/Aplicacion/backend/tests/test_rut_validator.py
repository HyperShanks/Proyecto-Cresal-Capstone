import uuid
import pytest
from pydantic import ValidationError

from conftest import TestingSessionLocal
import models
from core.security import create_access_token
from core.utils.validators import (
    calcular_digito_verificador,
    formatear_rut,
    validar_rut_modulo11,
)
from schemas import BaseRutSchema, ClienteCreateRequest


@pytest.fixture
def auth_headers():
    db = TestingSessionLocal()
    try:
        reg = db.query(models.Region).filter(models.Region.id_region == 1).first()
        if not reg:
            reg = models.Region(id_region=1, nombre_region="Valparaíso")
            db.add(reg)
            db.commit()

        com = db.query(models.Comuna).filter(models.Comuna.id_comuna == 1).first()
        if not com:
            com = models.Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(com)
            db.commit()

        sucursal = db.query(models.Sucursal).filter(models.Sucursal.id_sucursal == 1).first()
        if not sucursal:
            sucursal = models.Sucursal(
                id_sucursal=1,
                nombre_sucursal="Casa Matriz - Viña",
                direccion="Calle 1",
                id_comuna=1,
            )
            db.add(sucursal)

        rol = db.query(models.Rol).filter(models.Rol.id_rol == 2).first()
        if not rol:
            rol = models.Rol(id_rol=2, nombre_rol="Vendedor")
            db.add(rol)
        db.commit()

        usuario = db.query(models.Usuario).filter(models.Usuario.rut_usuario == "11.111.111-1").first()
        if not usuario:
            usuario = models.Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="11.111.111-1",
                nombres="Test",
                apellidos="Vendedor",
                email="vendedor.rut@cresal.cl",
                password_hash="fakehash",
                pin_acceso="1234",
                id_rol=2,
                id_sucursal=1,
                estado="Activo",
            )
            db.add(usuario)
            db.commit()
            db.refresh(usuario)

        token = create_access_token(
            data={"sub": str(usuario.id_usuario), "id_rol": usuario.id_rol, "id_sucursal": usuario.id_sucursal}
        )
        return {"Authorization": f"Bearer {token}"}
    finally:
        db.close()


# ==============================================================================
# PRUEBAS DEL ALGORITMO MATEMÁTICO MÓDULO 11
# ==============================================================================

class TestRutAlgorithm:
    """Pruebas directas de las funciones de core.utils.validators."""

    def test_calcular_dv_conocidos(self):
        """Verifica el cálculo del dígito verificador para RUTs chilenos reales."""
        assert calcular_digito_verificador("11111111") == "1"
        assert calcular_digito_verificador("11111112") == "K"
        assert calcular_digito_verificador("12345678") == "5"
        assert calcular_digito_verificador("18765432") == "7"

    def test_calcular_dv_cuerpo_invalido(self):
        """Rechaza cuerpos que no son dígitos."""
        with pytest.raises(ValueError):
            calcular_digito_verificador("12345A78")
        with pytest.raises(ValueError):
            calcular_digito_verificador("")

    def test_validar_rut_validos(self):
        """RUTs válidos con diferentes formatos deben retornar True y formateado."""
        validos = [
            ("11.111.111-1", "11.111.111-1"),
            ("11111111-1", "11.111.111-1"),
            ("111111111", "11.111.111-1"),
            ("11.111.112-k", "11.111.112-K"),
            ("11111112K", "11.111.112-K"),
            ("12.345.678-5", "12.345.678-5"),
            ("18.765.432-7", "18.765.432-7"),
            ("18765432-7", "18.765.432-7"),
        ]
        for rut_in, esperado in validos:
            es_valido, formateado = validar_rut_modulo11(rut_in)
            assert es_valido is True, f"Fallo al validar RUT válido: {rut_in}"
            assert formateado == esperado

    def test_validar_rut_sin_puntos(self):
        """Verifica la opción con_puntos=False."""
        es_valido, formateado = validar_rut_modulo11("11.111.111-1", con_puntos=False)
        assert es_valido is True
        assert formateado == "11111111-1"

    def test_validar_rut_consumidor_final(self):
        """Consumidor Final (6.666.666-6 / 66666666-6) debe ser aceptado por exención legal."""
        es_valido_1, fmt_1 = validar_rut_modulo11("6.666.666-6")
        assert es_valido_1 is True
        assert fmt_1 == "6.666.666-6"

        es_valido_2, fmt_2 = validar_rut_modulo11("6666666-6")
        assert es_valido_2 is True
        assert fmt_2 == "6.666.666-6"

        es_valido_3, fmt_3 = validar_rut_modulo11("66666666-6")
        assert es_valido_3 is True
        assert fmt_3 == "6.666.666-6"

    def test_validar_rut_invalidos(self):
        """RUTs inventados o con dígito incorrecto deben retornar False."""
        invalidos = [
            "1.111.111-1",   # DV real es 4
            "12.345.678-9",  # DV real es 5
            "18.765.432-1",  # DV real es 7
            "12345-6",       # Longitud insuficiente
            "12345678901-2", # Excede longitud
            "abc",           # Basura alfanumérica
            "",              # Vacío
            None,            # None
        ]
        for rut_inv in invalidos:
            es_valido, _ = validar_rut_modulo11(rut_inv)
            assert es_valido is False, f"Se aceptó erróneamente RUT inválido: {rut_inv}"

    def test_formatear_rut(self):
        """Verifica la normalización visual con puntos y guion."""
        assert formatear_rut("111111111") == "11.111.111-1"
        assert formatear_rut("11111112k") == "11.111.112-K"
        assert formatear_rut("11.111.111-1", con_puntos=False) == "11111111-1"


# ==============================================================================
# PRUEBAS DE ESQUEMAS PYDANTIC (BaseRutSchema)
# ==============================================================================

class SampleRutModel(BaseRutSchema):
    rut_cliente: str


class TestPydanticRutSchema:
    """Pruebas de validación en tiempo de parseo Pydantic."""

    def test_rut_valido_normaliza_correctamente(self):
        instancia = SampleRutModel(rut_cliente="123456785")
        assert instancia.rut_cliente == "12.345.678-5"

    def test_rut_con_k_minuscula_se_vuelve_mayuscula(self):
        instancia = SampleRutModel(rut_cliente="11111112k")
        assert instancia.rut_cliente == "11.111.112-K"

    def test_rut_invalido_lanza_validation_error(self):
        with pytest.raises(ValidationError) as exc_info:
            SampleRutModel(rut_cliente="1.111.111-1")
        assert "no es matemáticamente válido" in str(exc_info.value)

    def test_cliente_create_request_valido(self):
        payload = {
            "rut_cliente": "18.765.432-7",
            "nombres": "Pedro",
            "apellidos": "Pascal",
            "telefono": "+56911223344",
            "consentimiento_legal": True,
        }
        req = ClienteCreateRequest(**payload)
        assert req.rut_cliente == "18.765.432-7"

    def test_cliente_create_request_invalido_rechazado(self):
        payload = {
            "rut_cliente": "12.345.678-9",
            "nombres": "Pedro",
            "apellidos": "Pascal",
        }
        with pytest.raises(ValidationError):
            ClienteCreateRequest(**payload)


# ==============================================================================
# PRUEBAS DE INTEGRACIÓN HTTP (API FastAPI + Exception Handler)
# ==============================================================================

class TestRutApiIntegration:
    """Pruebas de endpoint POST /api/v1/clientes y respuesta de error 422."""

    def test_crear_cliente_rut_valido_201(self, client, auth_headers):
        payload = {
            "rut_cliente": "11.111.111-1",
            "nombres": "Cliente",
            "apellidos": "Prueba Valido",
            "telefono": "+56912345678",
            "correo": "cliente.valido@test.cl",
            "comuna": "Viña del Mar",
            "consentimiento_legal": True,
        }
        resp = client.post("/api/v1/clientes", json=payload, headers=auth_headers)
        assert resp.status_code == 201
        data = resp.json()
        assert data["rut_cliente"] == "11.111.111-1"
        assert data["nombres"] == "Cliente"

    def test_crear_cliente_rut_invalido_retorna_422_err_invalid_rut(self, client, auth_headers):
        """
        Un payload con RUT inválido debe ser capturado por el exception handler global
        y retornar HTTP 422 con error_code='ERR_INVALID_RUT'.
        """
        payload = {
            "rut_cliente": "1.111.111-1",  # RUT inválido
            "nombres": "Invasor",
            "apellidos": "Falso",
            "consentimiento_legal": True,
        }
        resp = client.post("/api/v1/clientes", json=payload, headers=auth_headers)
        assert resp.status_code == 422
        data = resp.json()
        assert data["error_code"] == "ERR_INVALID_RUT"
        assert "no es válido legalmente" in data["message_user"]
        assert "Verifica que el dígito verificador sea correcto" in data["message_user"]

    def test_crear_cliente_rut_inventado_123456789_retorna_422(self, client, auth_headers):
        payload = {
            "rut_cliente": "12.345.678-9",
            "nombres": "Otro",
            "apellidos": "Invalido",
        }
        resp = client.post("/api/v1/clientes", json=payload, headers=auth_headers)
        assert resp.status_code == 422
        data = resp.json()
        assert data["error_code"] == "ERR_INVALID_RUT"
