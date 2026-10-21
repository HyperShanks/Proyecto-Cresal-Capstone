# backend/core/exceptions.py
"""
Manejadores de excepciones globales, estandarización de respuestas de error
y sanitización de datos sensibles para evitar fugas técnicas (SPEC-HU-07).
"""

from typing import Optional, Any, List
import logging
from fastapi import FastAPI, Request, HTTPException, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict
from sqlalchemy.exc import SQLAlchemyError, IntegrityError, OperationalError

logger = logging.getLogger("cresal.exceptions")


class ErrorResponseDTO(BaseModel):
    """Contrato estandarizado de respuesta de error (SPEC-HU-07)."""
    model_config = ConfigDict(from_attributes=True)

    error_code: str
    message_user: str
    message_dev: Optional[str] = None  # Solo para depuración interna si se habilita
    detail: Optional[str] = None  # Retrocompatibilidad con clientes existentes


# ==============================================================================
# MANEJADORES DE EXCEPCIONES GLOBALES
# ==============================================================================

async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError) -> JSONResponse:
    """
    Captura y neutraliza cualquier error proveniente de SQLAlchemy / PostgreSQL.
    Garantiza CERO fugas de nombres de tablas, columnas o trazas de consultas SQL.
    """
    logger.error(f"[DB ERROR] Ruta: {request.url.path} | Error: {str(exc)}")
    
    error_str = str(exc).lower()

    if isinstance(exc, IntegrityError):
        if "unique constraint" in error_str or "duplicate key" in error_str or "llave duplicada" in error_str:
            status_code = status.HTTP_409_CONFLICT
            error_code = "RECORD_ALREADY_EXISTS"
            message_user = "El registro ya existe en el sistema o tiene un identificador duplicado."
        elif "foreign key" in error_str or "llave foránea" in error_str or "violates foreign key" in error_str:
            status_code = status.HTTP_409_CONFLICT
            error_code = "FOREIGN_KEY_VIOLATION"
            message_user = "La operación no pudo completarse porque hace referencia a un registro que no existe o está vinculado a otros datos."
        else:
            status_code = status.HTTP_400_BAD_REQUEST
            error_code = "INTEGRITY_CONSTRAINT_ERROR"
            message_user = "Los datos enviados violan las restricciones de integridad del sistema."
    elif isinstance(exc, OperationalError) or "connection" in error_str:
        status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        error_code = "DATABASE_UNAVAILABLE"
        message_user = "El servicio de base de datos no está disponible temporalmente. Intenta nuevamente en unos momentos."
    else:
        status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
        error_code = "DATABASE_ERROR"
        message_user = "Ocurrió un problema al procesar la información en la base de datos."

    response_dto = ErrorResponseDTO(
        error_code=error_code,
        message_user=message_user,
        message_dev=None,
        detail=message_user,
    )
    return JSONResponse(status_code=status_code, content=response_dto.model_dump())


async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """
    Captura fallos de validación de esquemas Pydantic (HTTP 422).
    Sanea los mensajes técnicos y provee una explicación clara al usuario.
    """
    logger.warning(f"[VALIDATION ERROR] Ruta: {request.url.path} | Errores: {exc.errors()}")
    
    # Construir un resumen legible de campos faltantes o inválidos
    campos_invalidos: List[str] = []
    for err in exc.errors():
        loc = err.get("loc", ())
        if loc:
            if isinstance(loc[-1], int) and len(loc) > 1:
                campo = f"{loc[-2]}[{loc[-1]}]"
            else:
                campo = str(loc[-1])
        else:
            campo = "campo desconocido"

        tipo = err.get("type", "")
        if "missing" in tipo:
            campos_invalidos.append(f"El campo '{campo}' es obligatorio.")
        else:
            campos_invalidos.append(f"El formato del campo '{campo}' es inválido.")

    detalle_amigable = (
        " ".join(campos_invalidos)
        if campos_invalidos
        else "Los datos ingresados no tienen un formato válido."
    )

    es_error_rut = any(
        "rut" in str(err.get("loc", ())).lower()
        or "rut" in str(err.get("msg", "")).lower()
        for err in exc.errors()
    )
    if es_error_rut:
        response_dto = ErrorResponseDTO(
            error_code="ERR_INVALID_RUT",
            message_user=(
                "El RUT ingresado no es válido legalmente. "
                "Verifica que el dígito verificador sea correcto."
            ),
            message_dev=detalle_amigable,
            detail=(
                "El RUT ingresado no es válido legalmente. "
                "Verifica que el dígito verificador sea correcto."
            ),
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content=response_dto.model_dump(),
        )

    response_dto = ErrorResponseDTO(
        error_code="VALIDATION_ERROR",
        message_user="Los datos ingresados no tienen un formato válido o faltan campos requeridos.",
        message_dev=detalle_amigable,
        detail=detalle_amigable,
    )
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=response_dto.model_dump(),
    )


async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    """
    Normaliza cualquier HTTPException explícita al contrato ErrorResponseDTO.
    """
    status_code = exc.status_code
    detail_str = str(exc.detail) if exc.detail else "Error en la petición"

    # Mapeo de códigos según el status
    if status_code == 400:
        error_code = "BAD_REQUEST"
    elif status_code == 401:
        error_code = "UNAUTHORIZED"
    elif status_code == 403:
        error_code = "FORBIDDEN"
    elif status_code == 404:
        error_code = "NOT_FOUND"
    elif status_code == 409:
        error_code = "CONFLICT"
    elif status_code == 422:
        error_code = "UNPROCESSABLE_ENTITY"
    else:
        error_code = f"HTTP_{status_code}"

    response_dto = ErrorResponseDTO(
        error_code=error_code,
        message_user=detail_str,
        message_dev=None,
        detail=detail_str,
    )
    return JSONResponse(status_code=status_code, content=response_dto.model_dump())


async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """
    Captura final de seguridad (Fail-Safe) para excepciones no controladas de Python (500).
    Oculta totalmente el stack trace y cualquier detalle de infraestructura.
    """
    logger.critical(f"[UNHANDLED EXCEPTION] Ruta: {request.url.path} | Error: {str(exc)}", exc_info=True)

    response_dto = ErrorResponseDTO(
        error_code="INTERNAL_SERVER_ERROR",
        message_user="Ocurrió un error inesperado en el servidor. Por favor, intenta más tarde.",
        message_dev=None,
        detail="Ocurrió un error inesperado en el servidor.",
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=response_dto.model_dump(),
    )


# ==============================================================================
# REGISTRO CENTRALIZADO EN FASTAPI
# ==============================================================================

def register_exception_handlers(app: FastAPI) -> None:
    """Inyecta los manejadores de excepciones en la aplicación FastAPI."""
    app.add_exception_handler(SQLAlchemyError, sqlalchemy_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(HTTPException, http_exception_handler)
    app.add_exception_handler(Exception, generic_exception_handler)
