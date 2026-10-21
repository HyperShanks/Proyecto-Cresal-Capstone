from uuid import UUID
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import Usuario
import schemas
from core.security import get_current_user
from routers.ordenes import marcar_despacho_enviado, actualizar_estado_despacho

router = APIRouter(
    prefix="/api/v1/despachos",
    tags=["Despachos y Envíos"]
)

@router.patch(
    "/{id_despacho}/enviar",
    response_model=schemas.DespachoEnvioResponse,
    status_code=200,
    summary="Marcar Despacho como Enviado (Cierre de Ciclo)",
)
def marcar_despacho_enviado_directo(
    id_despacho: UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Endpoint directo para marcar un despacho como enviado.
    """
    return marcar_despacho_enviado(id_despacho=id_despacho, db=db, current_user=current_user)


@router.patch(
    "/{id_despacho}/estado",
    response_model=schemas.DespachoActualizarEstadoResponse,
    status_code=200,
    summary="Actualizar Estado del Despacho (Independiente del estado de la orden)",
)
def actualizar_estado_despacho_directo(
    id_despacho: UUID,
    payload: schemas.DespachoActualizarEstadoRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Endpoint directo para actualizar exclusivamente el estado del despacho (Por Enviar o Enviado).
    """
    return actualizar_estado_despacho(id_despacho=id_despacho, payload=payload, db=db, current_user=current_user)
