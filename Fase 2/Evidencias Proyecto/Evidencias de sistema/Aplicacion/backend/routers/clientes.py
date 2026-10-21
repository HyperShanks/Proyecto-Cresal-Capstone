# Router de Clientes / Micro-CRM (HU-3.4)
# Permite la búsqueda y consulta rápida de clientes frecuentes por RUT.

from uuid import UUID
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from database import get_db
from models import Cliente, Comuna, Usuario
from core.security import get_current_user
from schemas import ClienteCreateRequest

router = APIRouter(
    prefix="/api/v1/clientes",
    tags=["Clientes / CRM"]
)


class ClienteDataResponse(BaseModel):
    """DTO de salida con los datos de contacto del cliente registrado."""
    model_config = ConfigDict(from_attributes=True)

    id_cliente: UUID
    rut_cliente: str
    nombres: str
    apellidos: str
    telefono: Optional[str] = None
    correo: Optional[str] = None
    id_comuna: Optional[int] = None
    comuna: Optional[str] = None
    consentimiento_legal: bool = True


@router.get(
    "/{rut}",
    response_model=ClienteDataResponse,
    summary="Buscar Cliente por RUT",
    description="Consulta un cliente por su RUT para autocompletar formularios en caja y ventas."
)
def buscar_cliente_por_rut(
    rut: str,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Búsqueda de cliente por RUT:
    1. Limpia el RUT de espacios.
    2. Realiza búsqueda exacta y normalizada (con/sin puntos).
    3. Si no existe, retorna 404 (manejado de forma silenciosa por el frontend).
    4. Si existe, retorna los datos de contacto y el nombre de su comuna.
    """
    rut_limpio = rut.strip()
    rut_norm = rut_limpio.replace(".", "").replace("-", "").upper()

    if rut_norm in ["66666666", "6666666"]:
        cliente = db.query(Cliente).filter(
            Cliente.rut_cliente.in_(["6.666.666-6", "66666666-6", "6666666-6"])
        ).first()
        if not cliente:
            cliente = Cliente(
                rut_cliente="6.666.666-6",
                nombres="Consumidor",
                apellidos="Final",
                consentimiento_legal=True,
                estado="Activo",
            )
            db.add(cliente)
            db.commit()
            db.refresh(cliente)
    else:
        cliente = db.query(Cliente).filter(Cliente.rut_cliente == rut_limpio).first()
        if not cliente:
            # Probar sin puntos
            rut_sin_puntos = rut_limpio.replace(".", "")
            cliente = db.query(Cliente).filter(Cliente.rut_cliente == rut_sin_puntos).first()

    if not cliente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Cliente con RUT '{rut}' no encontrado."
        )

    nombre_comuna = None
    if cliente.id_comuna:
        comuna_obj = db.query(Comuna).filter(Comuna.id_comuna == cliente.id_comuna).first()
        if comuna_obj:
            nombre_comuna = comuna_obj.nombre_comuna

    return ClienteDataResponse(
        id_cliente=cliente.id_cliente,
        rut_cliente=cliente.rut_cliente,
        nombres=cliente.nombres,
        apellidos=cliente.apellidos,
        telefono=cliente.telefono,
        correo=cliente.correo,
        id_comuna=cliente.id_comuna,
        comuna=nombre_comuna,
        consentimiento_legal=cliente.consentimiento_legal,
    )


@router.post(
    "",
    response_model=ClienteDataResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar Nuevo Cliente (Micro-CRM)",
    description="Registra un cliente validando matemáticamente su RUT mediante Módulo 11."
)
@router.post(
    "/",
    response_model=ClienteDataResponse,
    status_code=status.HTTP_201_CREATED,
    include_in_schema=False
)
def registrar_cliente(
    cliente_in: ClienteCreateRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Registra un cliente en el Micro-CRM:
    1. El RUT ya viene saneado y validado matemáticamente por BaseRutSchema.
    2. Si el cliente ya existe, actualiza sus datos o lo retorna.
    3. Si no existe, lo crea y persiste bajo transacción ACID.
    """
    rut_cliente = cliente_in.rut_cliente

    cliente_existente = db.query(Cliente).filter(
        Cliente.rut_cliente == rut_cliente
    ).first()

    if cliente_existente:
        cliente_existente.nombres = cliente_in.nombres
        cliente_existente.apellidos = cliente_in.apellidos
        if cliente_in.telefono:
            cliente_existente.telefono = cliente_in.telefono
        if cliente_in.correo:
            cliente_existente.correo = cliente_in.correo
        cliente_existente.consentimiento_legal = cliente_in.consentimiento_legal
        try:
            db.commit()
            db.refresh(cliente_existente)
        except HTTPException:
            db.rollback()
            raise
        except Exception as e:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Error transaccional al actualizar cliente: {str(e)}"
            )

        nombre_comuna = None
        if cliente_existente.id_comuna:
            comuna_obj = db.query(Comuna).filter(
                Comuna.id_comuna == cliente_existente.id_comuna
            ).first()
            if comuna_obj:
                nombre_comuna = comuna_obj.nombre_comuna

        return ClienteDataResponse(
            id_cliente=cliente_existente.id_cliente,
            rut_cliente=cliente_existente.rut_cliente,
            nombres=cliente_existente.nombres,
            apellidos=cliente_existente.apellidos,
            telefono=cliente_existente.telefono,
            correo=cliente_existente.correo,
            id_comuna=cliente_existente.id_comuna,
            comuna=nombre_comuna,
            consentimiento_legal=cliente_existente.consentimiento_legal,
        )

    id_comuna = cliente_in.id_comuna
    nombre_comuna = cliente_in.comuna
    if not id_comuna and nombre_comuna:
        comuna_db = db.query(Comuna).filter(
            Comuna.nombre_comuna.ilike(nombre_comuna.strip())
        ).first()
        if comuna_db:
            id_comuna = comuna_db.id_comuna
            nombre_comuna = comuna_db.nombre_comuna

    nuevo_cliente = Cliente(
        rut_cliente=rut_cliente,
        nombres=cliente_in.nombres,
        apellidos=cliente_in.apellidos,
        telefono=cliente_in.telefono,
        correo=cliente_in.correo,
        id_comuna=id_comuna,
        consentimiento_legal=cliente_in.consentimiento_legal,
        estado="Activo",
    )

    try:
        db.add(nuevo_cliente)
        db.commit()
        db.refresh(nuevo_cliente)
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al crear cliente: {str(e)}"
        )

    return ClienteDataResponse(
        id_cliente=nuevo_cliente.id_cliente,
        rut_cliente=nuevo_cliente.rut_cliente,
        nombres=nuevo_cliente.nombres,
        apellidos=nuevo_cliente.apellidos,
        telefono=nuevo_cliente.telefono,
        correo=nuevo_cliente.correo,
        id_comuna=nuevo_cliente.id_comuna,
        comuna=nombre_comuna,
        consentimiento_legal=nuevo_cliente.consentimiento_legal,
    )

