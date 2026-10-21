# backend/tests/test_global_exceptions.py
"""
Pruebas de Sanitización de Datos Sensibles, Exception Handlers Globales
y Contrato de Error ErrorResponseDTO (SPEC-HU-07).
"""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError, OperationalError, SQLAlchemyError

from core.exceptions import (
    ErrorResponseDTO,
    register_exception_handlers,
)


@pytest.fixture
def test_app_with_handlers():
    """Crea una aplicación FastAPI aislada para validar los Exception Handlers."""
    test_app = FastAPI()
    register_exception_handlers(test_app)

    class SampleInput(BaseModel):
        email: str
        edad: int = Field(..., ge=18)

    @test_app.post("/test/validation")
    def endpoint_validation(data: SampleInput):
        return {"ok": True, "data": data.model_dump()}

    @test_app.get("/test/http-error/{code}")
    def endpoint_http_error(code: int):
        if code == 400:
            raise HTTPException(status_code=400, detail="Parámetros de solicitud incorrectos.")
        elif code == 401:
            raise HTTPException(status_code=401, detail="PIN incorrecto para este terminal.")
        elif code == 403:
            raise HTTPException(status_code=403, detail="No tienes permisos para realizar esta operación.")
        elif code == 404:
            raise HTTPException(status_code=404, detail="El recurso solicitado no fue encontrado.")
        raise HTTPException(status_code=code, detail="Error genérico")

    @test_app.get("/test/db-integrity-duplicate")
    def endpoint_db_duplicate():
        raise IntegrityError(
            statement="INSERT INTO usuario (email) VALUES ('test@cresal.cl')",
            params={},
            orig=Exception("duplicate key value violates unique constraint 'usuario_email_key'"),
        )

    @test_app.get("/test/db-integrity-fk")
    def endpoint_db_fk():
        raise IntegrityError(
            statement="INSERT INTO orden (id_cliente) VALUES ('fake-id')",
            params={},
            orig=Exception('insert or update on table "orden" violates foreign key constraint "fk_cliente"'),
        )

    @test_app.get("/test/db-operational")
    def endpoint_db_operational():
        raise OperationalError(
            statement="SELECT 1",
            params={},
            orig=Exception("could not connect to server: Connection refused"),
        )

    @test_app.get("/test/unhandled-500")
    def endpoint_unhandled():
        # Fuerza una división por cero no controlada
        return 10 / 0

    return test_app


@pytest.fixture
def exception_client(test_app_with_handlers):
    return TestClient(test_app_with_handlers, raise_server_exceptions=False)


# ==============================================================================
# PRUEBAS DE SANITIZACIÓN Y CONTRATO ERRORRESPONSEDTO
# ==============================================================================

def test_validation_error_422_sanitization(exception_client):
    """Verifica que el error 422 retorne ErrorResponseDTO y oculte tecnicismos."""
    response = exception_client.post("/test/validation", json={"email": "test@cresal.cl", "edad": 15})
    assert response.status_code == 422
    data = response.json()

    assert "error_code" in data
    assert data["error_code"] == "VALIDATION_ERROR"
    assert "message_user" in data
    assert "edad" in data["detail"].lower()


def test_http_exceptions_normalized(exception_client):
    """Verifica que las HTTPExceptions 400, 401, 403, 404 sean normalizadas."""
    res_401 = exception_client.get("/test/http-error/401")
    assert res_401.status_code == 401
    data_401 = res_401.json()
    assert data_401["error_code"] == "UNAUTHORIZED"
    assert data_401["message_user"] == "PIN incorrecto para este terminal."

    res_404 = exception_client.get("/test/http-error/404")
    assert res_404.status_code == 404
    data_404 = res_404.json()
    assert data_404["error_code"] == "NOT_FOUND"
    assert data_404["message_user"] == "El recurso solicitado no fue encontrado."


def test_db_duplicate_key_sanitization_409(exception_client):
    """Verifica que un error de duplicado de BD oculte SQL y devuelva 409 seguro."""
    response = exception_client.get("/test/db-integrity-duplicate")
    assert response.status_code == 409
    data = response.json()

    assert data["error_code"] == "RECORD_ALREADY_EXISTS"
    assert "duplicate key" not in data["message_user"].lower()
    assert "insert into" not in data["message_user"].lower()
    assert "usuario_email_key" not in data["message_user"].lower()


def test_db_foreign_key_sanitization_409(exception_client):
    """Verifica que una violación de llave foránea no exponga nombres de tabla o constraints."""
    response = exception_client.get("/test/db-integrity-fk")
    assert response.status_code == 409
    data = response.json()

    assert data["error_code"] == "FOREIGN_KEY_VIOLATION"
    assert "foreign key" not in data["message_user"].lower()
    assert "fk_cliente" not in data["message_user"].lower()
    assert "insert into" not in data["message_user"].lower()


def test_db_operational_error_503(exception_client):
    """Verifica que una caída de conexión con la BD retorne 503 sin stack trace."""
    response = exception_client.get("/test/db-operational")
    assert response.status_code == 503
    data = response.json()

    assert data["error_code"] == "DATABASE_UNAVAILABLE"
    assert "connection refused" not in data["message_user"].lower()


def test_unhandled_exception_500_zero_traceback_leak(exception_client):
    """Verifica que una excepción crítica de Python devuelva 500 seguro y CERO traceback."""
    response = exception_client.get("/test/unhandled-500")
    assert response.status_code == 500
    data = response.json()

    assert data["error_code"] == "INTERNAL_SERVER_ERROR"
    assert "message_user" in data
    # Comprobar que no hay trazas de ZeroDivisionError ni rutas de archivos del servidor
    assert "ZeroDivisionError" not in str(data)
    assert "Traceback" not in str(data)
    assert "division by zero" not in str(data).lower()
