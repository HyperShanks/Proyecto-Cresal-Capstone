from datetime import datetime, timezone, timedelta
from uuid import UUID
from typing import List, Dict
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_

from database import get_db
from models import (
    Activo_Inventariado,
    Usuario,
    Vehiculo_Origen,
    Categoria_Activo,
    Sucursal,
    Detalle_Motor,
    Detalle_Caja_Cambio,
    Multimedia_Activo,
)
from core.security import get_current_user
from schemas import (
    ReservaCarritoRequest,
    ReservaCarritoResponse,
    LiberarCarritoResponse,
    HeartbeatCarritoResponse,
    MisReservasItemResponse,
)

router = APIRouter(prefix="", tags=["Carrito y Reserva Temporal"])

TIEMPO_RESERVA_MINUTOS = 15


def limpiar_reservas_expiradas(db: Session) -> int:
    """
    Libera de manera automática los repuestos cuyas reservas temporales
    hayan superado el tiempo límite de inactividad (reserva_expira_en < now_utc).
    Reversa id_estado a 1 (Disponible) e incrementa version_lock.
    """
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    try:
        expirados = (
            db.query(Activo_Inventariado)
            .filter(
                Activo_Inventariado.id_estado == 2,
                Activo_Inventariado.reserva_expira_en.isnot(None),
                Activo_Inventariado.reserva_expira_en < now_utc,
            )
            .all()
        )

        total_liberados = len(expirados)
        if total_liberados > 0:
            for act in expirados:
                act.id_estado = 1
                act.reservado_por = None
                act.reserva_expira_en = None
                act.version_lock = (act.version_lock or 1) + 1
                act.fecha_actualizacion = now_utc

            db.commit()
        return total_liberados
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        return 0


@router.post(
    "/reservar",
    response_model=ReservaCarritoResponse,
    status_code=status.HTTP_200_OK,
    summary="Reserva temporal y bloqueo concurrente de activo único en carrito (HU-03)",
)
def reservar_activo_carrito(
    payload: ReservaCarritoRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Bloquea temporalmente un repuesto único para el carrito del usuario.
    Aplica control de concurrencia optimista sobre `version_lock`.
    Si el activo ya fue tomado por otro vendedor o la versión cambió,
    responde con HTTP 409 Conflict.
    Si el activo no está disponible o está en mantenimiento/baja,
    responde con HTTP 400 Bad Request.
    """
    # 0. Limpieza previa de expiraciones
    limpiar_reservas_expiradas(db)

    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    exp_time = now_utc + timedelta(minutes=TIEMPO_RESERVA_MINUTOS)

    try:
        # 1. Ejecutar UPDATE atómico con version_lock (ACID)
        # Permite reservar si está disponible (id_estado == 1)
        # o si la reserva previa ya expiró (id_estado == 2 AND reserva_expira_en < now_utc)
        rows_affected = (
            db.query(Activo_Inventariado)
            .filter(
                Activo_Inventariado.id_activo == payload.id_activo,
                Activo_Inventariado.version_lock == payload.version_lock_esperado,
                Activo_Inventariado.estado == "Activo",
                or_(
                    Activo_Inventariado.id_estado == 1,
                    and_(
                        Activo_Inventariado.id_estado == 2,
                        Activo_Inventariado.reserva_expira_en < now_utc,
                    ),
                    and_(
                        Activo_Inventariado.id_estado == 2,
                        Activo_Inventariado.reservado_por == current_user.id_usuario,
                    ),
                ),
            )
            .update(
                {
                    Activo_Inventariado.id_estado: 2,
                    Activo_Inventariado.version_lock: Activo_Inventariado.version_lock + 1,
                    Activo_Inventariado.reservado_por: current_user.id_usuario,
                    Activo_Inventariado.reserva_expira_en: exp_time,
                    Activo_Inventariado.fecha_actualizacion: now_utc,
                },
                synchronize_session=False,
            )
        )

        if rows_affected == 0:
            # Inspeccionar motivo exacto de la colisión o rechazo
            activo_actual = (
                db.query(Activo_Inventariado)
                .filter(Activo_Inventariado.id_activo == payload.id_activo)
                .first()
            )

            if not activo_actual:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Activo no encontrado.",
                )

            # Si el artículo fue dado de baja, no está activo o está en mantenimiento/reparación
            if activo_actual.estado != "Activo" or activo_actual.id_estado not in (1, 2):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El artículo seleccionado se encuentra en mantenimiento o fue dado de baja del inventario.",
                )

            # Si está reservado por otro usuario aún vigente, o version_lock desalineado
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.",
            )

        db.commit()

        # Obtener activo actualizado para retornar respuesta tipada
        activo = (
            db.query(Activo_Inventariado)
            .filter(Activo_Inventariado.id_activo == payload.id_activo)
            .first()
        )

        return ReservaCarritoResponse(
            id_activo=activo.id_activo,
            version_lock=activo.version_lock,
            reservado_por=activo.reservado_por,
            reserva_expira_en=activo.reserva_expira_en,
            mensaje="Activo reservado temporalmente en el carrito con éxito.",
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al reservar activo: {str(e)}",
        )


@router.post(
    "/liberar/{id_activo}",
    response_model=LiberarCarritoResponse,
    status_code=status.HTTP_200_OK,
    summary="Liberar voluntariamente una reserva de carrito (HU-03)",
)
def liberar_activo_carrito(
    id_activo: UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Reversa el estado del activo a Disponible (id_estado = 1),
    limpia los campos de reserva e incrementa version_lock.
    """
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

    try:
        activo = (
            db.query(Activo_Inventariado)
            .filter(Activo_Inventariado.id_activo == id_activo)
            .first()
        )

        if not activo:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Activo no encontrado.",
            )

        # Si no estaba reservado, retornar confirmación idempotente
        if activo.id_estado != 2:
            return LiberarCarritoResponse(
                id_activo=activo.id_activo,
                version_lock=activo.version_lock,
                mensaje="El activo ya se encontraba disponible.",
            )

        # Reversar a Disponible
        activo.id_estado = 1
        activo.reservado_por = None
        activo.reserva_expira_en = None
        activo.version_lock = (activo.version_lock or 1) + 1
        activo.fecha_actualizacion = now_utc

        db.commit()
        db.refresh(activo)

        return LiberarCarritoResponse(
            id_activo=activo.id_activo,
            version_lock=activo.version_lock,
            mensaje="Reserva liberada exitosamente. El activo vuelve a estar disponible.",
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al liberar reserva: {str(e)}",
        )


@router.post(
    "/heartbeat",
    response_model=HeartbeatCarritoResponse,
    status_code=status.HTTP_200_OK,
    summary="Renovar caducidad de reservas temporales del usuario (Heartbeat)",
)
def heartbeat_carrito(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Extiende la marca de tiempo de expiración (reserva_expira_en)
    en 15 minutos para todos los repuestos reservados por el usuario logueado.
    """
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    nueva_exp = now_utc + timedelta(minutes=TIEMPO_RESERVA_MINUTOS)

    try:
        reservas = (
            db.query(Activo_Inventariado)
            .filter(
                Activo_Inventariado.id_estado == 2,
                Activo_Inventariado.reservado_por == current_user.id_usuario,
                Activo_Inventariado.reserva_expira_en >= now_utc,
            )
            .all()
        )

        for act in reservas:
            act.reserva_expira_en = nueva_exp
            act.fecha_actualizacion = now_utc

        db.commit()

        return HeartbeatCarritoResponse(
            mensaje="Heartbeat de carrito procesado exitosamente.",
            activos_renovados=len(reservas),
            nueva_expiracion=nueva_exp,
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al actualizar heartbeat de reservas: {str(e)}",
        )


@router.get(
    "/mis-reservas",
    response_model=List[MisReservasItemResponse],
    status_code=status.HTTP_200_OK,
    summary="Consultar las reservas temporales vigentes del usuario actual",
)
def obtener_mis_reservas(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Retorna la lista de activos actualmente reservados por el usuario logueado
    con el tiempo restante en segundos antes de la caducidad automática.
    """
    limpiar_reservas_expiradas(db)
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

    reservas = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
            Sucursal,
            Detalle_Motor,
            Detalle_Caja_Cambio,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .outerjoin(Sucursal, Activo_Inventariado.id_sucursal_actual == Sucursal.id_sucursal)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .filter(
            Activo_Inventariado.id_estado == 2,
            Activo_Inventariado.reservado_por == current_user.id_usuario,
            Activo_Inventariado.reserva_expira_en >= now_utc,
        )
        .all()
    )

    activo_ids = [activo.id_activo for activo, *_ in reservas]
    fotos_db = (
        db.query(Multimedia_Activo.id_activo, Multimedia_Activo.url_storage)
        .filter(Multimedia_Activo.id_activo.in_(activo_ids))
        .all()
    ) if activo_ids else []
    fotos_map: Dict[UUID, List[str]] = {}
    for act_id, url in fotos_db:
        fotos_map.setdefault(act_id, []).append(url)

    cajas_vehiculo_ids = [
        activo.id_vehiculo
        for activo, _, cat, _, _, _ in reservas
        if cat and cat.id_categoria == 2 and activo.id_vehiculo is not None
    ]
    motores_donantes: Dict[UUID, Detalle_Motor] = {}
    if cajas_vehiculo_ids:
        motores_db = (
            db.query(Activo_Inventariado.id_vehiculo, Detalle_Motor)
            .join(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .filter(
                Activo_Inventariado.id_vehiculo.in_(cajas_vehiculo_ids),
                Activo_Inventariado.id_categoria == 1,
            )
            .all()
        )
        for v_id, dm in motores_db:
            motores_donantes[v_id] = dm

    items = []
    for activo, vehiculo, cat, suc, motor, caja in reservas:
        segundos = int((activo.reserva_expira_en - now_utc).total_seconds()) if activo.reserva_expira_en else 0
        lista_fotos = fotos_map.get(activo.id_activo, [])
        motor_donante = motores_donantes.get(activo.id_vehiculo) if (cat and cat.id_categoria == 2 and activo.id_vehiculo) else None

        cilindrada_val = None
        combustible_val = None
        transmision_val = None
        numero_motor_val = None

        if cat and cat.id_categoria == 1 and motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
            numero_motor_val = motor.numero_motor
        elif cat and cat.id_categoria == 2:
            transmision_val = caja.transmision_tipo if caja else None
            if motor_donante:
                cilindrada_val = motor_donante.cilindrada
                combustible_val = motor_donante.combustible
            numero_motor_val = None
        elif motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
            if cat and cat.id_categoria == 1:
                numero_motor_val = motor.numero_motor
        elif caja:
            transmision_val = caja.transmision_tipo

        items.append(
            MisReservasItemResponse(
                id_activo=activo.id_activo,
                sku_qr_fisico=activo.sku_qr_fisico,
                version_lock=activo.version_lock,
                reserva_expira_en=activo.reserva_expira_en,
                segundos_restantes=max(0, segundos),
                id_categoria=cat.id_categoria if cat else None,
                nombre_categoria=cat.nombre_categoria if cat else None,
                id_sucursal_actual=suc.id_sucursal if suc else None,
                nombre_sucursal=suc.nombre_sucursal if suc else None,
                precio_referencia=activo.precio_referencia,
                precio_minimo=activo.precio_minimo,
                precio_maximo=activo.precio_maximo,
                ubicacion_pasillo=activo.ubicacion_pasillo,
                ubicacion_pallet=activo.ubicacion_pallet,
                ubicacion_galpon=getattr(activo, "ubicacion_galpon", None),
                id_vehiculo=vehiculo.id_vehiculo if vehiculo else None,
                marca=vehiculo.marca if vehiculo else None,
                modelo=vehiculo.modelo if vehiculo else None,
                anio=vehiculo.anio if vehiculo else None,
                numero_motor=numero_motor_val,
                cilindrada=cilindrada_val,
                combustible=combustible_val,
                transmision_tipo=transmision_val,
                imagenes=lista_fotos,
            )
        )

    return items

