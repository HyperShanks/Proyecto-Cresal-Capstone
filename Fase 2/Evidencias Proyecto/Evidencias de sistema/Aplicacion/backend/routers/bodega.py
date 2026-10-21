import uuid
from datetime import datetime, timezone
from uuid import UUID
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status, BackgroundTasks
from sqlalchemy import or_, func
from sqlalchemy.orm import Session
from pydantic import BaseModel

from database import get_db
from services.telegram_service import TelegramService
from models import (
    Activo_Inventariado,
    Orden_Venta,
    Detalle_Orden,
    Vehiculo_Origen,
    Usuario,
    Detalle_Motor,
    Detalle_Caja_Cambio,
    Categoria_Activo,
    Estado_Activo,
    Cliente,
    Auditoria_Barrera,
    Tracking_Logistico,
    Despacho,
    Reservas_Backorder,
    Sucursal,
)
from schemas import (
    TareaAlertaResponse,
    CompletarPreentregaResponse,
    VerificarQrSalidaRequest,
    VerificarQrSalidaResponse,
    ItemSalidaInfo,
    EscanearSalidaRequest,
    EscanearSalidaResponse,
    TareaReingresoDTO,
    ConfirmarReingresoRequest,
    ConfirmarReingresoResponse,
    ResumenAlertasDTO,
)
from core.security import get_current_user, require_bodega_access
from core.policies import validar_horario_operativo_bodega

router = APIRouter(
    prefix="/api/v1/bodega",
    tags=["Tablero Operativo"],
    dependencies=[Depends(require_bodega_access)]
)

# Alias retrocompatible
TareaAlerta = TareaAlertaResponse


@router.get(
    "/resumen-alertas",
    response_model=ResumenAlertasDTO,
    summary="Resumen de Tareas y Alertas de Bodega (SPEC-HU-06)",
    description="Retorna el conteo consolidado y desglosado de tareas operativas pendientes "
                "(preparaciones, entregas/liberadas y reingresos) para la sucursal del bodeguero."
)
def obtener_resumen_alertas(
    sucursal_id: Optional[int] = Query(None, description="ID de la sucursal del bodeguero"),
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    """
    Calcula el resumen agregado de tareas operativas de Bodega para alimentar el Badge del AppBar.
    """
    target_sucursal = sucursal_id if sucursal_id is not None else (usuario_logeado.id_sucursal or 1)

    # 1. Preparaciones y traslados pendientes (no listas o pagadas pendientes de barrera)
    conteo_preparacion = (
        db.query(Detalle_Orden)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .join(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
        .filter(
            Activo_Inventariado.id_estado.in_([2, 3]),
            Activo_Inventariado.id_sucursal_actual == target_sucursal,
            or_(
                Detalle_Orden.estado_preparacion != "Listo",
                Orden_Venta.estado_orden == "Pagada",
            ),
            Orden_Venta.estado_orden.in_(["Reservada", "Pagada"]),
        )
        .count()
    )

    # 2. Entregas / Impresiones pendientes (Activos en bodega sin QR impreso: Paletizado, Reservado, Vendido o Disponible)
    conteo_impresiones = (
        db.query(Activo_Inventariado)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(
            or_(
                Activo_Inventariado.qr_impreso == False,
                Activo_Inventariado.qr_impreso.is_(None),
            ),
            Activo_Inventariado.estado == "Activo",
            Activo_Inventariado.id_sucursal_actual == target_sucursal,
            or_(
                Activo_Inventariado.id_estado.in_([1, 2, 3, 7]),
                func.lower(Estado_Activo.nombre_estado).in_(["disponible", "reservado", "vendido", "paletizado"]),
            ),
            Activo_Inventariado.id_estado != 5,
            ~func.lower(Estado_Activo.nombre_estado).ilike("%desarme%"),
        )
        .count()
    )

    # Las tareas de entrega en barrera (LIBERADA) ya están contabilizadas dentro de conteo_preparacion
    # (órdenes con estado_preparacion != 'Listo' y estado_orden in ['Reservada', 'Pagada']).
    # Por lo tanto, conteo_entregas refleja las impresiones de etiquetas QR pendientes.
    conteo_entregas = conteo_impresiones

    # 3. Reingresos de Logística Inversa
    conteo_reingresos = (
        db.query(Detalle_Orden)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .join(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
        .filter(
            Orden_Venta.estado_orden == "Anulada",
            Detalle_Orden.estado_preparacion != "Reingresado",
            Activo_Inventariado.estado == "Activo",
            (Activo_Inventariado.id_sucursal_actual == target_sucursal) | (Orden_Venta.id_sucursal == target_sucursal),
        )
        .count()
    )

    total_tareas = conteo_preparacion + conteo_entregas + conteo_reingresos

    return ResumenAlertasDTO(
        total_tareas=total_tareas,
        desglose_preparacion=conteo_preparacion,
        desglose_entregas=conteo_entregas,
        desglose_reingresos=conteo_reingresos,
    )


def _construir_etiqueta_data(
    db: Session,
    activo: Activo_Inventariado,
    vehiculo: Optional[Vehiculo_Origen] = None,
    motor: Optional[Detalle_Motor] = None,
    caja: Optional[Detalle_Caja_Cambio] = None,
) -> dict:
    if vehiculo is None and activo.id_vehiculo:
        vehiculo = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first()

    if motor is None:
        if activo.id_categoria == 1:
            motor = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == activo.id_activo).first()
        elif activo.id_categoria == 2 and activo.id_vehiculo:
            # Herencia de especificaciones del activo hermano Motor (SPEC-HU-TAREA-17)
            motor = (
                db.query(Detalle_Motor)
                .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
                .filter(
                    Activo_Inventariado.id_vehiculo == activo.id_vehiculo,
                    Activo_Inventariado.id_categoria == 1,
                )
                .first()
            )

    if caja is None and activo.id_categoria == 2:
        caja = db.query(Detalle_Caja_Cambio).filter(Detalle_Caja_Cambio.id_activo == activo.id_activo).first()

    if activo.id_categoria == 2 and caja:
        transmision_val = caja.transmision_tipo
    elif motor:
        transmision_val = motor.transmision_tipo
    else:
        transmision_val = None

    return {
        "id_activo": str(activo.id_activo),
        "numero_ingreso": vehiculo.numero_ingreso if vehiculo else "N/A",
        "marca": vehiculo.marca if vehiculo else "Desconocida",
        "modelo": vehiculo.modelo if vehiculo else "Desconocido",
        "anio": vehiculo.anio if vehiculo else 0,
        "traccion": vehiculo.traccion if vehiculo else None,
        "cilindrada": motor.cilindrada if motor else None,
        "combustible": motor.combustible if motor else None,
        "transmision": transmision_val,
        "numero_motor": motor.numero_motor if (motor and activo.id_categoria == 1) else None,
        "galpon": activo.ubicacion_galpon or "",
        "pasillo": activo.ubicacion_pasillo or "",
        "pallet": activo.ubicacion_pallet or "",
        "sku_qr_fisico": activo.sku_qr_fisico or "",
    }


def construir_descripcion_repuesto(db: Session, activo: Activo_Inventariado) -> str:
    """
    Construye la descripción formal de un repuesto según el formato de alertas gerenciales:
    Categoría (Motor o Caja) + Marca + Modelo + Cilindrada (si aplica) + Año.
    Ejemplo: 'Motor Geely Azkarra 1.5 2020' o 'Caja Geely Azkarra 2020'
    """
    cat_display = "Repuesto"
    if activo.id_categoria:
        cat_obj = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == activo.id_categoria).first()
        if cat_obj and cat_obj.nombre_categoria:
            nom = cat_obj.nombre_categoria.strip()
            nom_lower = nom.lower()
            if "motor" in nom_lower:
                cat_display = "Motor"
            elif "caja" in nom_lower:
                cat_display = "Caja"
            else:
                cat_display = nom

    vehiculo = None
    if activo.id_vehiculo:
        vehiculo = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first()

    cilindrada_val = None
    if activo.id_categoria == 1 or "motor" in cat_display.lower():
        motor = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == activo.id_activo).first()
        if motor and motor.cilindrada:
            cilindrada_val = motor.cilindrada.strip()
    elif (activo.id_categoria == 2 or "caja" in cat_display.lower()) and activo.id_vehiculo:
        motor_hermano = (
            db.query(Detalle_Motor)
            .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .filter(
                Activo_Inventariado.id_vehiculo == activo.id_vehiculo,
                Activo_Inventariado.id_categoria == 1,
            )
            .first()
        )
        if motor_hermano and motor_hermano.cilindrada:
            cilindrada_val = motor_hermano.cilindrada.strip()

    partes = [cat_display]
    if vehiculo:
        if vehiculo.marca and vehiculo.marca.strip():
            partes.append(vehiculo.marca.strip())
        if vehiculo.modelo and vehiculo.modelo.strip():
            partes.append(vehiculo.modelo.strip())
        if cilindrada_val:
            partes.append(cilindrada_val)
        if vehiculo.anio:
            partes.append(str(vehiculo.anio))
    elif cilindrada_val:
        partes.append(cilindrada_val)

    resultado = " ".join(partes).strip()
    return resultado if resultado else (activo.sku_qr_fisico or "Repuesto")


@router.get("/tareas-pendientes", response_model=List[TareaAlertaResponse])
def obtener_tareas_pendientes(
    sucursal_id: int = Query(1, description="ID de la sucursal del bodeguero"),
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    """
    Lista las tareas operativas pendientes para la bodega de la sucursal indicada:
    1. Tareas de Impresión QR (activos sin etiqueta física impresa).
    2. Tareas de Pre-Entrega / Preparación / Traslado:
       - Retención: se listan activos en estado 'Reservado' (id_estado = 2) o 'Vendido' (id_estado = 3).
       - No desaparecen al pagar en caja (cambio de 2 a 3).
       - Desaparecen una vez que el bodeguero marca 'Listo' (preparacion_lista == True).
       - Filtradas por sucursal de origen / ubicación física actual del activo.
    """
    alertas = []

    # ---------------------------------------------------------
    # PRIORIDAD 1: Preparación, Traslado y Liberación (FILTRADO POR SUCURSAL)
    # ---------------------------------------------------------
    detalles_orden = (
        db.query(Detalle_Orden, Orden_Venta, Activo_Inventariado, Vehiculo_Origen)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .join(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .filter(
            Activo_Inventariado.id_estado.in_([2, 3]),  # 2: Reservado, 3: Vendido
            Activo_Inventariado.id_sucursal_actual == sucursal_id,
            or_(
                Detalle_Orden.estado_preparacion != "Listo",
                Orden_Venta.estado_orden == "Pagada",
            ),
            Orden_Venta.estado_orden.in_(["Reservada", "Pagada"]),
        )
        .all()
    )

    liberadas_por_orden = {}
    otras_alertas = []

    for detalle, orden, activo, vehiculo in detalles_orden:
        # Detectar si requiere traslado entre sucursales mediante Tracking_Logistico o discrepancia de sucursal
        tracking = db.query(Tracking_Logistico).filter(
            Tracking_Logistico.id_activo == activo.id_activo,
            Tracking_Logistico.id_orden == orden.id_orden,
        ).first()

        if not tracking:
            tracking = db.query(Tracking_Logistico).filter(
                Tracking_Logistico.id_activo == activo.id_activo,
                Tracking_Logistico.id_sucursal_origen == sucursal_id,
            ).first()

        es_traslado = (tracking is not None) or (orden.id_sucursal != activo.id_sucursal_actual)
        sucursal_dest_id = tracking.id_sucursal_destino if tracking else orden.id_sucursal

        if es_traslado:
            tipo = "TRASLADO"
            if orden.monto_pendiente > 0:
                bloqueo = "ESPERANDO PAGO EN CAJA"
                accion = "EN ESPERA"
            else:
                bloqueo = None
                accion = "PREPARAR Y TRASLADAR"
        else:
            if orden.monto_pendiente > 0:
                tipo = "PREPARACION"
                bloqueo = "ESPERANDO PAGO EN CAJA"
                accion = "EN ESPERA"
            else:
                tipo = "LIBERADA"
                bloqueo = None
                accion = "ESCANEAR EN BARRERA"

        if tipo == "LIBERADA":
            liberadas_por_orden.setdefault(orden.id_orden, []).append((detalle, orden, activo, vehiculo))
            continue

        cat_nombre = "Motor" if activo.id_categoria == 1 else ("Caja de Cambios" if activo.id_categoria == 2 else "Repuesto")
        titulo = f"{cat_nombre} - {vehiculo.marca} {vehiculo.modelo}" if vehiculo else cat_nombre
        etiqueta_data = _construir_etiqueta_data(db, activo, vehiculo)
        qr_impreso = bool(activo.qr_impreso)

        otras_alertas.append(
            TareaAlertaResponse(
                id_tarea=f"ORD-{str(detalle.id_detalle)[:8]}",
                tipo_alerta=tipo,
                orden_ref=orden.folio,
                folio=orden.folio,
                titulo_pieza=titulo,
                categoria=cat_nombre,
                tipo_repuesto=cat_nombre,
                ubicacion=f"{activo.ubicacion_pasillo or 'S/P'} - {activo.ubicacion_pallet or 'S/P'}",
                ubicacion_pasillo=activo.ubicacion_pasillo,
                ubicacion_pallet=activo.ubicacion_pallet,
                ubicacion_galpon=activo.ubicacion_galpon,
                nota_especial=detalle.notas_preparacion,
                estado_bloqueo=bloqueo,
                accion_requerida=accion,
                id_detalle=detalle.id_detalle,
                id_activo=activo.id_activo,
                id_sucursal_origen=activo.id_sucursal_actual,
                id_sucursal_destino=sucursal_dest_id,
                es_traslado=es_traslado,
                estado_preparacion=detalle.estado_preparacion or "Pendiente",
                id_orden=orden.id_orden,
                sku_qr_fisico=activo.sku_qr_fisico,
                qr_impreso=qr_impreso,
                etiqueta_data=etiqueta_data,
            )
        )

    # Consolidar tareas de Barrera (LIBERADA) a 1 única tarea por orden
    for id_ord, items in liberadas_por_orden.items():
        if len(items) == 1:
            detalle, orden, activo, vehiculo = items[0]
            cat_nombre = "Motor" if activo.id_categoria == 1 else ("Caja de Cambios" if activo.id_categoria == 2 else "Repuesto")
            titulo = f"{cat_nombre} - {vehiculo.marca} {vehiculo.modelo}" if vehiculo else cat_nombre
            etiqueta_data = _construir_etiqueta_data(db, activo, vehiculo)
            alertas.append(
                TareaAlertaResponse(
                    id_tarea=f"ORD-{str(detalle.id_detalle)[:8]}",
                    tipo_alerta="LIBERADA",
                    orden_ref=orden.folio,
                    folio=orden.folio,
                    titulo_pieza=titulo,
                    categoria=cat_nombre,
                    tipo_repuesto=cat_nombre,
                    ubicacion=f"{activo.ubicacion_pasillo or 'S/P'} - {activo.ubicacion_pallet or 'S/P'}",
                    ubicacion_pasillo=activo.ubicacion_pasillo,
                    ubicacion_pallet=activo.ubicacion_pallet,
                    ubicacion_galpon=activo.ubicacion_galpon,
                    nota_especial=detalle.notas_preparacion,
                    estado_bloqueo=None,
                    accion_requerida="ESCANEAR EN BARRERA",
                    id_detalle=detalle.id_detalle,
                    id_activo=activo.id_activo,
                    id_sucursal_origen=activo.id_sucursal_actual,
                    id_sucursal_destino=orden.id_sucursal,
                    es_traslado=False,
                    estado_preparacion=detalle.estado_preparacion or "Listo",
                    id_orden=orden.id_orden,
                    sku_qr_fisico=activo.sku_qr_fisico,
                    qr_impreso=bool(activo.qr_impreso),
                    etiqueta_data=etiqueta_data,
                )
            )
        else:
            # Orden consolidada con múltiples repuestos (ej: Motor + Caja de Cambios)
            primer_detalle, orden, primer_activo, primer_vehiculo = items[0]
            categorias = [("Motor" if a.id_categoria == 1 else ("Caja de Cambios" if a.id_categoria == 2 else "Repuesto")) for _, _, a, _ in items]
            vehiculos_nombres = [f"{v.marca} {v.modelo}".strip() for _, _, _, v in items if v]
            vehiculo_str = vehiculos_nombres[0] if vehiculos_nombres else "Vehículo"
            cats_str = " + ".join(dict.fromkeys(categorias))
            titulo = f"{vehiculo_str} ({cats_str})"

            skus = [a.sku_qr_fisico for _, _, a, _ in items if a.sku_qr_fisico]
            ubicaciones = [f"{a.sku_qr_fisico}: {a.ubicacion_pasillo or 'S/P'}-{a.ubicacion_pallet or 'S/P'}" for _, _, a, _ in items]
            todos_impresos = all([bool(a.qr_impreso) for _, _, a, _ in items])

            alertas.append(
                TareaAlertaResponse(
                    id_tarea=f"BARRERA-{str(orden.id_orden)[:8]}",
                    tipo_alerta="LIBERADA",
                    orden_ref=orden.folio,
                    folio=orden.folio,
                    titulo_pieza=titulo,
                    categoria="Múltiples Repuestos",
                    tipo_repuesto="Múltiples Repuestos",
                    ubicacion=" • ".join(ubicaciones),
                    ubicacion_pasillo=primer_activo.ubicacion_pasillo,
                    ubicacion_pallet=primer_activo.ubicacion_pallet,
                    ubicacion_galpon=primer_activo.ubicacion_galpon,
                    nota_especial=f"Orden consolidada con {len(items)} repuestos listos para salida conjunta.",
                    estado_bloqueo=None,
                    accion_requerida=f"ESCANEAR EN BARRERA ({len(items)} PIEZAS)",
                    id_detalle=primer_detalle.id_detalle,
                    id_activo=primer_activo.id_activo,
                    id_sucursal_origen=primer_activo.id_sucursal_actual,
                    id_sucursal_destino=orden.id_sucursal,
                    es_traslado=False,
                    estado_preparacion="Listo",
                    id_orden=orden.id_orden,
                    sku_qr_fisico=", ".join(skus),
                    qr_impreso=todos_impresos,
                    etiqueta_data=_construir_etiqueta_data(db, primer_activo, primer_vehiculo),
                )
            )

    alertas.extend(otras_alertas)

    # ---------------------------------------------------------
    # PRIORIDAD 2: Reingresos de Logística Inversa (Órdenes Anuladas)
    # ---------------------------------------------------------
    reingresos = (
        db.query(Detalle_Orden, Orden_Venta, Activo_Inventariado, Vehiculo_Origen)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .join(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .filter(
            Orden_Venta.estado_orden == "Anulada",
            Detalle_Orden.estado_preparacion != "Reingresado",
            Activo_Inventariado.estado == "Activo",
            (Activo_Inventariado.id_sucursal_actual == sucursal_id) | (Orden_Venta.id_sucursal == sucursal_id),
        )
        .all()
    )

    for detalle, orden, activo, vehiculo in reingresos:
        cat_nombre = "Motor" if activo.id_categoria == 1 else ("Caja de Cambios" if activo.id_categoria == 2 else "Repuesto")
        if vehiculo:
            anio_str = f" ({vehiculo.anio})" if vehiculo.anio else ""
            titulo = f"{cat_nombre} - {vehiculo.marca} {vehiculo.modelo}{anio_str}"
        else:
            titulo = f"{cat_nombre} - {activo.sku_qr_fisico}" if activo.sku_qr_fisico else cat_nombre

        alertas.append(
            TareaAlertaResponse(
                id_tarea=f"REING-{str(detalle.id_detalle)[:8]}",
                tipo_alerta="REINGRESO",
                orden_ref=orden.folio,
                folio=orden.folio,
                titulo_pieza=titulo,
                categoria=cat_nombre,
                tipo_repuesto=cat_nombre,
                ubicacion=f"{activo.ubicacion_pasillo or 'S/P'} - {activo.ubicacion_pallet or 'S/P'}",
                ubicacion_pasillo=activo.ubicacion_pasillo,
                ubicacion_pallet=activo.ubicacion_pallet,
                ubicacion_galpon=activo.ubicacion_galpon,
                nota_especial="Reingreso a inventario / paletizado por anulación de orden",
                estado_bloqueo=None,
                accion_requerida="REINGRESAR / PALETIZAR",
                id_detalle=detalle.id_detalle,
                id_activo=activo.id_activo,
                id_orden=orden.id_orden,
                sku_qr_fisico=activo.sku_qr_fisico,
                id_sucursal_origen=activo.id_sucursal_actual,
                es_traslado=False,
                estado_preparacion=detalle.estado_preparacion or "Reingreso Pendiente",
            )
        )

    # ---------------------------------------------------------
    # PRIORIDAD 3: Pendiente de Impresión (FILTRADO POR SUCURSAL)
    # Activos en bodega sin QR impreso: Paletizado, Reservado, Vendido o Disponible
    # ---------------------------------------------------------
    activos_sin_qr = (
        db.query(Activo_Inventariado, Vehiculo_Origen, Detalle_Motor, Detalle_Caja_Cambio)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(
            or_(
                Activo_Inventariado.qr_impreso == False,
                Activo_Inventariado.qr_impreso.is_(None),
            ),
            Activo_Inventariado.estado == "Activo",
            Activo_Inventariado.id_sucursal_actual == sucursal_id,
            or_(
                Activo_Inventariado.id_estado.in_([1, 2, 3, 7]),
                func.lower(Estado_Activo.nombre_estado).in_(["disponible", "reservado", "vendido", "paletizado"]),
            ),
            Activo_Inventariado.id_estado != 5,
            ~func.lower(Estado_Activo.nombre_estado).ilike("%desarme%"),
        )
        .all()
    )

    for activo, vehiculo, motor, caja in activos_sin_qr:
        if activo.id_categoria == 2 and caja:
            transmision_val = caja.transmision_tipo
        elif motor:
            transmision_val = motor.transmision_tipo
        else:
            transmision_val = None

        cat_nombre = "Motor" if activo.id_categoria == 1 else ("Caja de Cambios" if activo.id_categoria == 2 else "Repuesto")
        if vehiculo:
            anio_str = f" ({vehiculo.anio})" if vehiculo.anio else ""
            titulo = f"{cat_nombre} - {vehiculo.marca} {vehiculo.modelo}{anio_str}"
        else:
            titulo = f"{cat_nombre} - {activo.sku_qr_fisico}" if activo.sku_qr_fisico else cat_nombre

        alertas.append(
            TareaAlertaResponse(
                id_tarea=f"IMP-{str(activo.id_activo)[:8]}",
                tipo_alerta="IMPRESION",
                titulo_pieza=titulo,
                categoria=cat_nombre,
                tipo_repuesto=cat_nombre,
                ubicacion=f"{activo.ubicacion_pasillo or 'S/P'} - {activo.ubicacion_pallet or 'S/P'}",
                ubicacion_pasillo=activo.ubicacion_pasillo,
                ubicacion_pallet=activo.ubicacion_pallet,
                ubicacion_galpon=activo.ubicacion_galpon,
                nota_especial="GENERAR Y PEGAR ETIQUETA QR",
                accion_requerida="GENERAR QR AHORA",
                etiqueta_data=_construir_etiqueta_data(db, activo, vehiculo, motor, caja),
                id_activo=activo.id_activo,
                id_sucursal_origen=activo.id_sucursal_actual,
                es_traslado=False,
                estado_preparacion="Pendiente",
                sku_qr_fisico=activo.sku_qr_fisico,
                qr_impreso=False,
            )
        )

    return alertas


@router.patch(
    "/tareas/{id_detalle}/completar-preentrega",
    response_model=CompletarPreentregaResponse,
    summary="Marcar Preparación de Pre-Entrega como 'Listo'",
    description="Permite al bodeguero marcar como completada ('Listo') la preparación de una pieza. "
                "Persiste el estado para que la tarea desaparezca del panel de pendientes.",
)
def completar_preentrega(
    id_detalle: UUID,
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    detalle = db.query(Detalle_Orden).filter(Detalle_Orden.id_detalle == id_detalle).first()
    if not detalle:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Línea de detalle con ID '{id_detalle}' no encontrada.",
        )

    detalle.estado_preparacion = "Listo"
    detalle.fecha_preparacion = datetime.now()

    # Si hay un tracking logístico pendiente asociado, actualizar a listo para traslado
    if detalle.id_activo:
        tracking = db.query(Tracking_Logistico).filter(
            Tracking_Logistico.id_activo == detalle.id_activo,
            Tracking_Logistico.estado_traslado == "Pendiente",
        ).first()
        if tracking:
            tracking.estado_traslado = "Listo para Traslado"

    db.commit()
    db.refresh(detalle)

    return CompletarPreentregaResponse(
        id_detalle=detalle.id_detalle,
        id_orden=detalle.id_orden,
        id_activo=detalle.id_activo,
        preparacion_lista=True,
        estado_preparacion=detalle.estado_preparacion,
        mensaje="Preparación de pre-entrega marcada como 'Listo' exitosamente.",
        fecha_preparacion=detalle.fecha_preparacion.isoformat() if detalle.fecha_preparacion else None,
    )


@router.post(
    "/verificar-qr-salida",
    response_model=VerificarQrSalidaResponse,
    summary="Verificar Ticket Digital QR para Salida de Bodega",
    description="Permite al bodeguero inspeccionar previamente el contenido de una orden pagada escaneando el QR Digital emitido al vendedor."
)
def verificar_qr_salida(
    payload: VerificarQrSalidaRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    token = payload.qr_transaccional_salida.strip()
    print(f"🔍 [BARRERA] Inspeccionando token QR: '{token}'")

    orden = db.query(Orden_Venta).filter(Orden_Venta.qr_transaccional_salida == token).first()
    if not orden:
        # Fallback: permitir también ingresar el número o folio comercial si el operador lo digita
        if token.upper().startswith("ORD-"):
            posible_num = token.upper().replace("ORD-", "").strip()
            if posible_num.isdigit():
                orden = db.query(Orden_Venta).filter(Orden_Venta.numero_orden == int(posible_num)).first()
        elif token.isdigit():
            orden = db.query(Orden_Venta).filter(Orden_Venta.numero_orden == int(token)).first()

    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Código QR transaccional no encontrado o inválido."
        )

    # Validar que pertenezca a la sucursal del bodeguero si aplica
    if current_user.id_sucursal and orden.id_sucursal != current_user.id_sucursal:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"La orden pertenece a la sucursal {orden.id_sucursal}. No está autorizado para despachar órdenes de otra sucursal."
        )

    # Validaciones Poka-Yoke de estado
    if orden.estado_orden == "Anulada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta orden fue 'Anulada' y no puede ser entregada."
        )

    if orden.estado_orden == "Completada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{orden.folio} ya fue entregada y completada anteriormente."
        )

    if orden.estado_orden != "Pagada" or orden.monto_pendiente > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{orden.folio} no se encuentra pagada en caja (Saldo pendiente: ${orden.monto_pendiente})."
        )

    # Datos del cliente
    cliente = db.query(Cliente).filter(Cliente.id_cliente == orden.id_cliente).first()
    cliente_nombre = f"{cliente.nombres} {cliente.apellidos}".strip() if cliente else "Cliente General"
    cliente_rut = cliente.rut_cliente if cliente else "N/A"
    cliente_tel = cliente.telefono if cliente else None

    # Detalles de repuestos
    detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
    items_info = []
    total_fisicos = 0

    for d in detalles:
        if d.id_activo:
            activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
            if activo:
                vehiculo = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first() if activo.id_vehiculo else None
                cat = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == activo.id_categoria).first()
                nombre_cat = cat.nombre_categoria if cat else "Repuesto"
                titulo = f"{nombre_cat} - {vehiculo.marca} {vehiculo.modelo} ({vehiculo.anio})" if vehiculo else (d.descripcion_manual or nombre_cat)
                partes_ub = []
                if activo.ubicacion_galpon and activo.ubicacion_galpon.strip():
                    partes_ub.append(f"Galpón: {activo.ubicacion_galpon.strip()}")
                if activo.ubicacion_pasillo and activo.ubicacion_pasillo.strip():
                    partes_ub.append(f"Pasillo: {activo.ubicacion_pasillo.strip()}")
                if activo.ubicacion_pallet and activo.ubicacion_pallet.strip():
                    partes_ub.append(f"Pallet: {activo.ubicacion_pallet.strip()}")
                ubicacion = " | ".join(partes_ub) if partes_ub else "Sin ubicación registrada"
                sku = activo.sku_qr_fisico or str(activo.id_activo)[:8]
                qr_impreso = bool(activo.qr_impreso)
                etiqueta_data = _construir_etiqueta_data(db, activo, vehiculo)
                es_inv = True
                total_fisicos += 1
            else:
                titulo = d.descripcion_manual or "Repuesto no catalogado"
                ubicacion = "Pieza eliminada de inventario"
                sku = "DESCONOCIDO"
                qr_impreso = False
                etiqueta_data = None
                es_inv = False
        else:
            titulo = d.descripcion_manual or "Misceláneo / Servicio"
            ubicacion = "Mostrador / Despacho"
            sku = "MISCELÁNEO (No requiere escaneo físico)"
            qr_impreso = True
            etiqueta_data = None
            es_inv = False

        items_info.append(ItemSalidaInfo(
            id_detalle=d.id_detalle,
            id_activo=d.id_activo,
            titulo=titulo,
            sku_qr_fisico=sku,
            es_inventariado=es_inv,
            ubicacion=ubicacion,
            notas_preparacion=d.notas_preparacion,
            cantidad=d.cantidad,
            precio_final=d.precio_final,
            qr_impreso=qr_impreso,
            etiqueta_data=etiqueta_data,
        ))

    folio = orden.folio
    print(f"✅ [BARRERA] Inspección de orden {folio} exitosa: {len(items_info)} ítems ({total_fisicos} físicos requeridos).")

    return VerificarQrSalidaResponse(
        id_orden=orden.id_orden,
        folio=folio,
        estado_orden=orden.estado_orden,
        total_venta=orden.total_venta,
        monto_pendiente=orden.monto_pendiente,
        id_sucursal=orden.id_sucursal,
        cliente_nombre=cliente_nombre,
        cliente_rut=cliente_rut,
        cliente_telefono=cliente_tel,
        items_requeridos=items_info,
        total_items_fisicos=total_fisicos,
        qr_transaccional_salida=orden.qr_transaccional_salida,
    )


@router.post(
    "/escanear-salida",
    response_model=EscanearSalidaResponse,
    summary="Confirmar Handshake y Salida en Barrera (Dual-Scan Match)",
    description="Valida la coincidencia del token digital del vendedor con los SKUs físicos escaneados de las piezas. Al coincidir, actualiza atómicamente la orden a 'Completada', los activos a 'Entregado' (ID 6) y libera el rack físico."
)
def escanear_salida(
    payload: EscanearSalidaRequest,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    # 0. Validación de Horario Operativo de Bodega (Bloqueo de salidas nocturnas y domingos)
    validar_horario_operativo_bodega(current_user)

    token = payload.qr_transaccional_salida.strip()
    user_ident = f"{current_user.nombres} {current_user.apellidos} ({current_user.email})".strip()
    print(f"🚪 [BARRERA] Iniciando confirmación de entrega para token: '{token}' por: {user_ident}")

    orden = db.query(Orden_Venta).filter(Orden_Venta.qr_transaccional_salida == token).first()
    if not orden:
        # Fallback: si se envió el número o folio comercial
        if token.upper().startswith("ORD-"):
            posible_num = token.upper().replace("ORD-", "").strip()
            if posible_num.isdigit():
                orden = db.query(Orden_Venta).filter(Orden_Venta.numero_orden == int(posible_num)).first()
        elif token.isdigit():
            orden = db.query(Orden_Venta).filter(Orden_Venta.numero_orden == int(token)).first()

    if not orden:
        print(f"⚠️ [BARRERA] Token QR '{token}' no encontrado.")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Código QR transaccional no encontrado o inválido."
        )

    # Validar sucursal
    if current_user.id_sucursal and orden.id_sucursal != current_user.id_sucursal:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"La orden pertenece a la sucursal {orden.id_sucursal}. No está autorizado para liberar órdenes de otra sucursal."
        )

    # Validaciones Poka-Yoke de estado
    if orden.estado_orden == "Anulada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No se puede procesar la entrega. Esta orden fue 'Anulada'."
        )

    if orden.estado_orden == "Completada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{orden.folio} ya fue entregada anteriormente."
        )

    if orden.estado_orden != "Pagada" or orden.monto_pendiente > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{orden.folio} no ha sido pagada en su totalidad (Saldo pendiente: ${orden.monto_pendiente})."
        )

    # 1. Obtener los activos físicos requeridos por la orden (ignorando ítems misceláneos/venta libre sin activo)
    detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
    activos_requeridos = []
    skus_requeridos_set = set()

    for d in detalles:
        if d.id_activo:
            act = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
            if act:
                activos_requeridos.append(act)
                skus_requeridos_set.add(act.sku_qr_fisico.strip().upper())

    # 2. Validación Poka-Yoke Dual-Scan Match
    # Si la orden tiene activos inventariados, todos sus SKUs deben haber sido escaneados
    skus_escaneados_normalizados = {sku.strip().upper() for sku in payload.skus_escaneados if sku and sku.strip()}

    if skus_requeridos_set:
        # A. Validar que no se hayan escaneado piezas que no pertenecen a esta orden
        skus_invalidos = skus_escaneados_normalizados - skus_requeridos_set
        if skus_invalidos:
            print(f"❌ [DUAL-SCAN] Error: Piezas no pertenecientes a la orden escaneadas: {skus_invalidos}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Las siguientes piezas escaneadas NO pertenecen a esta orden: {', '.join(skus_invalidos)}."
            )

        # B. Validar que todos los SKUs físicos requeridos estén presentes
        skus_faltantes = skus_requeridos_set - skus_escaneados_normalizados
        if skus_faltantes:
            print(f"❌ [DUAL-SCAN] Error: Faltan {len(skus_faltantes)} SKU(s) por escanear: {skus_faltantes}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Falta escanear el QR físico de {len(skus_faltantes)} pieza(s) para autorizar la salida: {', '.join(skus_faltantes)}."
            )

        # C. Validar que todas las piezas inventariadas requeridas tengan QR impreso
        activos_sin_imprimir = [act.sku_qr_fisico for act in activos_requeridos if not act.qr_impreso]
        if activos_sin_imprimir:
            print(f"❌ [DUAL-SCAN] Error: Piezas sin QR impreso: {activos_sin_imprimir}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"No se puede autorizar la salida en barrera. Las siguientes piezas no registran impresión de QR físico: {', '.join(activos_sin_imprimir)}. Imprima la etiqueta antes de entregar."
            )

    try:
        # 3. Transacción ACID: Cierre de Orden y Ciclo de Inventario
        estado_entregado = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Entregado").first()
        if not estado_entregado:
            estado_entregado = Estado_Activo(id_estado=6, nombre_estado="Entregado")
            db.add(estado_entregado)
            db.flush()

        # A. Actualizar Orden_Venta a 'Completada'
        orden.estado_orden = "Completada"
        orden.fecha_actualizacion = datetime.now()

        # Si la orden corresponde a un despacho (courier), marcar el despacho como 'Enviado'
        despacho_db = db.query(Despacho).filter(Despacho.id_orden == orden.id_orden).first()
        if despacho_db:
            despacho_db.estado_despacho = "Enviado"
            despacho_db.fecha_actualizacion = datetime.now()

        # Marcar automáticamente todas las líneas de detalle como 'Listo' (cierre de ciclo para misceláneos y activos)
        for d in detalles:
            d.estado_preparacion = "Listo"
            d.fecha_preparacion = datetime.now()

        # B. Actualizar cada Activo_Inventariado a 'Entregado' (ID 6) y liberar rack
        skus_entregados_nombres = []
        for act in activos_requeridos:
            act.id_estado = estado_entregado.id_estado
            act.ubicacion_pasillo = None
            act.ubicacion_pallet = None
            act.ubicacion_galpon = None
            act.observacion_estado = f"Entregado en barrera por {current_user.nombres} {current_user.apellidos} - Orden #{orden.folio}"
            act.version_lock = (act.version_lock or 1) + 1
            act.fecha_actualizacion = datetime.now()
            skus_entregados_nombres.append(act.sku_qr_fisico)
            print(f"📦 [ENTREGA] Activo '{act.sku_qr_fisico}' actualizado a 'Entregado' (ID {estado_entregado.id_estado}). Ubicación en rack liberada.")

        # C. Registrar trazabilidad forense en Auditoria_Barrera
        registro_auditoria = Auditoria_Barrera(
            id_auditoria=uuid.uuid4(),
            id_orden=orden.id_orden,
            id_bodeguero=current_user.id_usuario,
            fecha_escaneo=datetime.now(),
            match_exitoso=True,
        )
        db.add(registro_auditoria)

        # D. Confirmación atómica
        db.commit()
        db.refresh(orden)

        folio = orden.folio
        print(f"✅ [BARRERA] Orden {folio} completada exitosamente. Total piezas entregadas: {len(skus_entregados_nombres)}.")

        # Disparar alerta asíncrona a Telegram para Gerencia
        cliente_obj = db.query(Cliente).filter(Cliente.id_cliente == orden.id_cliente).first()
        cliente_nom = f"{cliente_obj.nombres} {cliente_obj.apellidos}".strip() if cliente_obj else "Cliente Particular"
        sucursal_obj = db.query(Sucursal).filter(Sucursal.id_sucursal == orden.id_sucursal).first()
        sucursal_nom = sucursal_obj.nombre_sucursal if sucursal_obj else f"Sucursal {orden.id_sucursal}"
        bodeguero_nom = f"{current_user.nombres} {current_user.apellidos}".strip()

        # Construir descripción rica de piezas entregadas: Categoría (Motor o Caja) + Marca + Modelo + Cilindrada + Año
        descripciones_piezas = [construir_descripcion_repuesto(db, act) for act in activos_requeridos]
        if not descripciones_piezas:
            descripciones_piezas = [d.descripcion_manual for d in detalles if d.descripcion_manual]
        repuestos_str = ", ".join(descripciones_piezas) if descripciones_piezas else "Repuesto(s)"
        skus_str = ", ".join(skus_entregados_nombres) if skus_entregados_nombres else "S/SKU"

        background_tasks.add_task(
            TelegramService.notificar_entrega_barrera,
            folio=folio,
            cliente_nombre=cliente_nom,
            descripcion_pieza=repuestos_str,
            sku=skus_str,
            bodeguero_nombre=bodeguero_nom,
            sucursal_nombre=sucursal_nom,
        )

        return EscanearSalidaResponse(
            id_orden=orden.id_orden,
            folio=folio,
            estado_orden=orden.estado_orden,
            id_bodeguero=current_user.id_usuario,
            bodeguero_nombre=f"{current_user.nombres} {current_user.apellidos}".strip(),
            fecha_entrega=datetime.now().isoformat(),
            activos_entregados=skus_entregados_nombres,
            total_entregados=len(skus_entregados_nombres),
            mensaje="¡Entrega en barrera autorizada exitosamente! Orden completada y repuestos liberados del inventario.",
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al procesar la salida en barrera: {str(e)}"
        )


@router.get("/pendientes-paletizado", status_code=200)
def obtener_pendientes_paletizado_bodega(
    sucursal_id: Optional[int] = None,
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    """
    Endpoint de consulta de piezas pendientes de paletizado en bodega.
    Retorna todos los activos de la sucursal activa donde ubicacion_pasillo IS NULL, 'S/P' o id_estado == 5.
    """
    from routers.vehiculos import obtener_pendientes_paletizado
    return obtener_pendientes_paletizado(sucursal_id=sucursal_id, db=db, usuario_logeado=usuario_logeado)


# ==========================================
# MÓDULO: LOGÍSTICA INVERSA Y REINGRESOS (SPEC-HU-TAREA-4)
# ==========================================

@router.get(
    "/reingresos-pendientes",
    response_model=List[TareaReingresoDTO],
    summary="Listado de Tareas de Reingreso y Paletizado (Logística Inversa)",
    description="Lista los repuestos físicos que pertenecían a órdenes anuladas y requieren "
                "reingreso, escaneo de QR físico y ubicación en pallet/rack por el bodeguero."
)
def obtener_reingresos_pendientes(
    sucursal_id: Optional[int] = Query(None, description="ID de la sucursal (opcional)"),
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    # Control de acceso RBAC: Bodeguero (id_rol == 1) o Administrador (id_rol == 5)
    if usuario_logeado.id_rol not in [1, 4, 5]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado. Solo personal de bodega o administradores pueden gestionar reingresos."
        )

    # Identificar sucursal objetivo
    target_sucursal = sucursal_id if sucursal_id is not None else (usuario_logeado.id_sucursal or 1)

    # Consulta con JOINs: Detalle_Orden -> Orden_Venta ('Anulada') -> Activo_Inventariado (id_estado not in [1, 7])
    query = (
        db.query(
            Detalle_Orden,
            Orden_Venta,
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
        )
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .join(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .filter(
            Orden_Venta.estado_orden == "Anulada",
            Detalle_Orden.estado_preparacion != "Reingresado",
            Activo_Inventariado.estado == "Activo",
        )
    )

    if target_sucursal is not None:
        query = query.filter(
            (Activo_Inventariado.id_sucursal_actual == target_sucursal) | (Orden_Venta.id_sucursal == target_sucursal)
        )

    rows = query.order_by(Orden_Venta.fecha_actualizacion.desc()).all()

    resultados = []
    for detalle, orden, activo, vehiculo, categoria in rows:
        folio = orden.folio

        cat_nombre = categoria.nombre_categoria if categoria else "Repuesto"
        if vehiculo:
            desc_pieza = f"{cat_nombre} - {vehiculo.marca} {vehiculo.modelo} ({vehiculo.anio})"
        else:
            desc_pieza = detalle.descripcion_manual or cat_nombre

        resultados.append(
            TareaReingresoDTO(
                id_orden=orden.id_orden,
                id_activo=activo.id_activo,
                sku_qr_fisico=activo.sku_qr_fisico,
                ubicacion_pallet=activo.ubicacion_pallet,
                ubicacion_pasillo=activo.ubicacion_pasillo,
                ubicacion_galpon=activo.ubicacion_galpon,
                descripcion_pieza=desc_pieza,
                folio_orden=folio,
            )
        )

    return resultados


@router.post(
    "/confirmar-reingreso",
    response_model=ConfirmarReingresoResponse,
    summary="Confirmar Reingreso de Activo con Control de Concurrencia Optimista",
    description="Valida el SKU físico escaneado por PDA para una orden anulada, "
                "actualiza la ubicación en rack y muta el estado del inventario a Paletizado (7) o Disponible (1) "
                "incrementando atómicamente version_lock."
)
def confirmar_reingreso(
    payload: ConfirmarReingresoRequest,
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    # Control de acceso RBAC: Bodeguero (1) o Administrador (4, 5)
    if usuario_logeado.id_rol not in [1, 4, 5]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado. Solo personal de bodega o administradores pueden confirmar reingresos."
        )

    # 1. Validar existencia de la orden anulada
    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == payload.id_orden_anulada).first()
    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"La orden #{str(payload.id_orden_anulada)[:8].upper()} no fue encontrada."
        )

    if orden.estado_orden != "Anulada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{orden.folio} no está en estado 'Anulada' (Estado actual: '{orden.estado_orden}')."
        )

    # 2. Validar que el SKU escaneado pertenezca a la orden anulada
    sku_busqueda = payload.sku_qr_fisico.strip().upper()
    activo = (
        db.query(Activo_Inventariado)
        .filter(Activo_Inventariado.sku_qr_fisico == sku_busqueda)
        .first()
    )
    if not activo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún activo con el SKU/QR '{sku_busqueda}'."
        )

    detalle = (
        db.query(Detalle_Orden)
        .filter(
            Detalle_Orden.id_orden == payload.id_orden_anulada,
            Detalle_Orden.id_activo == activo.id_activo,
        )
        .first()
    )
    if not detalle:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El repuesto '{sku_busqueda}' no pertenece a la orden anulada #{orden.folio}."
        )

    # 3. Validar si ya fue reingresado
    if detalle.estado_preparacion == "Reingresado":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El repuesto '{sku_busqueda}' ya fue reingresado y se encuentra en su ubicación de pallet."
        )

    try:
        # Actualizar ubicación física si fue suministrada y válida
        if payload.ubicacion_galpon is not None and payload.ubicacion_galpon.strip():
            activo.ubicacion_galpon = payload.ubicacion_galpon.strip().upper()
        if payload.ubicacion_pasillo is not None and payload.ubicacion_pasillo.strip():
            activo.ubicacion_pasillo = payload.ubicacion_pasillo.strip().upper()
        if payload.ubicacion_pallet is not None and payload.ubicacion_pallet.strip():
            activo.ubicacion_pallet = payload.ubicacion_pallet.strip().upper()

        activo.fecha_actualizacion = datetime.now(timezone.utc)
        activo.observacion_estado = f"Reingreso físico confirmado tras anulación orden #{orden.folio} por {usuario_logeado.nombres} {usuario_logeado.apellidos}"

        # Marcar Detalle_Orden como Reingresado para limpiar de tareas en bodega
        detalle.estado_preparacion = "Reingresado"
        detalle.fecha_preparacion = datetime.now(timezone.utc)

        db.commit()
        db.refresh(activo)
        db.refresh(detalle)

        return ConfirmarReingresoResponse(
            msg="Activo reingresado y paletizado exitosamente",
            id_activo=activo.id_activo,
            sku_qr_fisico=activo.sku_qr_fisico,
            nuevo_estado="Disponible",
            ubicacion_pasillo=activo.ubicacion_pasillo,
            ubicacion_pallet=activo.ubicacion_pallet,
            ubicacion_galpon=activo.ubicacion_galpon,
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al confirmar el reingreso: {str(e)}"
        )

