# Router de Tickets de Soporte (HU-2.7)
# Expone los endpoints para crear y consultar tickets de soporte internos.
# Todos los endpoints están protegidos por JWT Bearer Token.

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from database import get_db
from models import Usuario, Ticket_Soporte
from schemas import TicketCreate, TicketResponse
from core.security import create_access_token, get_current_user


# ─────────────────────────────────────────────────────────────────────────────
# Router principal
# ─────────────────────────────────────────────────────────────────────────────
router = APIRouter(
    tags=["Tickets de Soporte"]
)


# ─────────────────────────────────────────────────────────────────────────────
# POST / — Crea un nuevo ticket de soporte
# ─────────────────────────────────────────────────────────────────────────────
@router.post(
    "",
    response_model=TicketResponse,
    status_code=201,
    summary="Crear Ticket de Soporte",
    description="Crea un nuevo ticket de soporte interno. "
                "El campo id_usuario_creador se asigna automáticamente "
                "desde el JWT del operario autenticado.",
)
def crear_ticket(
    ticket_data: TicketCreate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Flujo de creación de ticket:

    1. Valida el JWT del operario mediante la dependencia get_current_user.
    2. Crea el objeto Ticket_Soporte con id_usuario_creador = current_user.id_usuario.
    3. Persiste en la base de datos y retorna el ticket completo.
    """
    nuevo_ticket = Ticket_Soporte(
        tipo_ticket=ticket_data.tipo_ticket,
        prioridad=ticket_data.prioridad,
        asunto=ticket_data.asunto,
        descripcion=ticket_data.descripcion,
        id_usuario_creador=current_user.id_usuario,
        tabla_referencia=ticket_data.tabla_referencia,
        id_referencia=ticket_data.id_referencia,
        # estado_ticket usa server_default="Abierto" definido en el modelo ORM
    )

    db.add(nuevo_ticket)
    db.commit()
    db.refresh(nuevo_ticket)

    # Serializar fechas como strings ISO 8601 antes de retornar
    return _ticket_to_response(nuevo_ticket)


# ─────────────────────────────────────────────────────────────────────────────
# GET /mis-tickets — Lista los tickets del operario autenticado
# ─────────────────────────────────────────────────────────────────────────────
@router.get(
    "/mis-tickets",
    response_model=List[TicketResponse],
    status_code=200,
    summary="Listar Mis Tickets",
    description="Retorna todos los tickets creados por el operario autenticado, "
                "ordenados por fecha de creación descendente (más recientes primero).",
)
def obtener_mis_tickets(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Consulta los tickets filtrando exclusivamente por id_usuario_creador
    del usuario que realiza la petición, garantizando aislamiento de datos.
    """
    tickets = (
        db.query(Ticket_Soporte)
        .filter(Ticket_Soporte.id_usuario_creador == current_user.id_usuario)
        .order_by(Ticket_Soporte.fecha_creacion.desc())
        .all()
    )

    return [_ticket_to_response(t) for t in tickets]


# ─────────────────────────────────────────────────────────────────────────────
# Helper: convierte un ORM Ticket_Soporte → TicketResponse con fechas serializadas
# ─────────────────────────────────────────────────────────────────────────────
def _ticket_to_response(ticket: Ticket_Soporte) -> TicketResponse:
    """
    Mapea el objeto SQLAlchemy al DTO de respuesta Pydantic.
    Las columnas DateTime se convierten a strings ISO 8601 para garantizar
    compatibilidad con el parser JSON de Flutter/Dart.
    """
    return TicketResponse(
        id_ticket=ticket.id_ticket,
        tipo_ticket=ticket.tipo_ticket,
        prioridad=ticket.prioridad,
        asunto=ticket.asunto,
        descripcion=ticket.descripcion,
        id_usuario_creador=ticket.id_usuario_creador,
        id_usuario_resolutor=ticket.id_usuario_resolutor,
        tabla_referencia=ticket.tabla_referencia,
        id_referencia=ticket.id_referencia,
        estado_ticket=ticket.estado_ticket,
        observacion_cierre=ticket.observacion_cierre,
        fecha_creacion=ticket.fecha_creacion.isoformat() if ticket.fecha_creacion else None,
        fecha_cierre=ticket.fecha_cierre.isoformat() if ticket.fecha_cierre else None,
    )
