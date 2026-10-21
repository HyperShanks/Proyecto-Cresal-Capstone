import uuid
import math
from typing import Optional, List
from datetime import datetime, timezone, time, timedelta, date
from uuid import UUID
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Depends, Query, HTTPException, status, BackgroundTasks
from sqlalchemy import or_, and_, func, select
from sqlalchemy.orm import Session, aliased

from database import get_db
from services.telegram_service import TelegramService
from models import (
    Usuario,
    Cliente,
    Orden_Venta,
    Detalle_Orden,
    Reservas_Backorder,
    Activo_Inventariado,
    Vehiculo_Origen,
    Categoria_Activo,
    Estado_Activo,
    Transaccion_Pago,
    Auditoria_Barrera,
    Detalle_Motor,
    Detalle_Caja_Cambio,
    Despacho,
)
from schemas import (
    CajaVerificarAccesoResponse,
    CobroPendienteItemResponse,
    CobroPendienteListResponse,
    ArticuloResumenDTO,
    BackorderEspecificacionesDTO,
    TipoOperacionEnum,
    ModalidadCobroEnum,
    RegistrarCobroRequest,
    RegistrarCobroResponse,
    ValidarActivoBackorderRequest,
    ValidarActivoBackorderResponse,
    ActivoDetalleBackorderDTO,
    HistorialAbonoItemDTO,
    HistorialPagoDetalleDTO,
    HistorialArticuloDTO,
    HistorialMovimientoDTO,
    ResumenCuadreCajaDTO,
    HistorialOrdenItemResponse,
    HistorialCajaResponse,
)
from core.security import require_caja_role
from core.policies import validar_horario_operativo_caja

router = APIRouter(
    prefix="/api/v1/caja",
    tags=["Caja"]
)

tz_chile = ZoneInfo("America/Santiago")


def format_chile_datetime(dt: Optional[datetime]) -> tuple[str, str, datetime]:
    if not dt:
        now_utc = datetime.now(timezone.utc)
        dt_chile = now_utc.astimezone(tz_chile)
        return dt_chile.strftime("%d/%m/%Y"), dt_chile.strftime("%H:%M"), now_utc
    if dt.tzinfo is None:
        dt_utc = dt.replace(tzinfo=timezone.utc)
    else:
        dt_utc = dt.astimezone(timezone.utc)
    dt_chile = dt_utc.astimezone(tz_chile)
    return dt_chile.strftime("%d/%m/%Y"), dt_chile.strftime("%H:%M"), dt_utc


def strip_accents(s: str) -> str:
    import unicodedata
    if not s:
        return ""
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn").lower()


@router.get(
    "/verificar-acceso",
    response_model=CajaVerificarAccesoResponse,
    summary="Verificar Acceso de Caja",
    description="Valida que el token JWT pertenezca a un usuario con rol de Caja (id_rol == 3) o Administrador (id_rol == 5)."
)
def verificar_acceso_caja(
    current_user: Usuario = Depends(require_caja_role)
):
    """
    Endpoint de sondeo y verificación de permisos para el módulo de caja.
    """
    rol_nombre = "Caja"
    if current_user.rol and current_user.rol.nombre_rol:
        rol_nombre = current_user.rol.nombre_rol
    elif current_user.id_rol == 5:
        rol_nombre = "Administrador"

    return CajaVerificarAccesoResponse(
        autorizado=True,
        rol=rol_nombre,
        id_sucursal=current_user.id_sucursal
    )


@router.get(
    "/pendientes",
    response_model=CobroPendienteListResponse,
    summary="Listado de Cobros Pendientes (Ventas y Backorders)",
    description="Retorna la bandeja consolidada de órdenes de venta con saldo pendiente "
                "y reservas backorder para la sucursal física activa del operario de caja."
)
def obtener_cobros_pendientes(
    sucursal_id: int = Query(..., description="ID de la sucursal activa"),
    busqueda: Optional[str] = Query(None, description="Término de búsqueda multicriterio (Folio, RUT, Cliente, Vendedor)"),
    tipo_operacion: Optional[str] = Query("TODOS", description="Filtro de tipo: 'TODOS', 'VENTA', 'BACKORDER'"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_caja_role),
):
    tipo_filtro = (tipo_operacion or "TODOS").strip().upper()
    items_resultado: List[CobroPendienteItemResponse] = []

    # ─────────────────────────────────────────────────────────────────────────
    # 1. CONSULTAR ÓRDENES DE VENTA PENDIENTES DE PAGO
    # ─────────────────────────────────────────────────────────────────────────
    if tipo_filtro in ["TODOS", "VENTA"]:
        # Excluir órdenes que corresponden a reservas backorder para evitar duplicidad en caja
        subq_backorders = (
            db.query(Reservas_Backorder.id_orden)
            .filter(Reservas_Backorder.id_orden.isnot(None))
        )

        ordenes_query = (
            db.query(Orden_Venta, Cliente, Usuario)
            .join(Cliente, Orden_Venta.id_cliente == Cliente.id_cliente)
            .join(Usuario, Orden_Venta.id_vendedor == Usuario.id_usuario)
            .filter(Orden_Venta.id_sucursal == sucursal_id)
            .filter(Orden_Venta.estado_orden.in_(["Reservada", "Pendiente"]))
            .filter(Orden_Venta.monto_pendiente > 0)
            .filter(~Orden_Venta.id_orden.in_(subq_backorders))
        ).all()

        for orden, cliente, vendedor in ordenes_query:
            # Obtener detalles de la orden enriquecidos con especificaciones tecnicas
            detalles_raw = (
                db.query(
                    Detalle_Orden,
                    Activo_Inventariado,
                    Vehiculo_Origen,
                    Categoria_Activo,
                    Detalle_Motor,
                    Detalle_Caja_Cambio,
                )
                .outerjoin(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
                .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
                .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
                .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
                .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
                .filter(Detalle_Orden.id_orden == orden.id_orden)
            ).all()

            articulos_dto: List[ArticuloResumenDTO] = []
            for det, activo, vehiculo, categoria, motor, caja in detalles_raw:
                cat_str = categoria.nombre_categoria if categoria else None
                marca_str = vehiculo.marca if vehiculo else None
                modelo_str = vehiculo.modelo if vehiculo else None
                anio_int = vehiculo.anio if vehiculo else None

                # Detalle técnico identificable (cilindrada, combustible, transmisión)
                tec_parts = []
                if motor:
                    if motor.cilindrada:
                        tec_parts.append(motor.cilindrada)
                    if motor.combustible:
                        tec_parts.append(motor.combustible)
                if caja and caja.transmision_tipo:
                    tec_parts.append(caja.transmision_tipo)
                detalle_tec_str = " • ".join(tec_parts) if tec_parts else None

                if activo:
                    tipo_art = "INVENTARIADO"
                    sku_art = activo.sku_qr_fisico

                    es_desc_antigua_solo_sku = bool(
                        det.descripcion_manual
                        and (f"- SKU: {activo.sku_qr_fisico}" in det.descripcion_manual or f"SKU: {activo.sku_qr_fisico}" in det.descripcion_manual)
                    )

                    if det.descripcion_manual and not es_desc_antigua_solo_sku:
                        desc_art = det.descripcion_manual
                    else:
                        cat_base = cat_str or "Repuesto"
                        veh_parts = [p for p in [marca_str, modelo_str, str(anio_int) if anio_int else None] if p]
                        veh_text = f" - {' '.join(veh_parts)}" if veh_parts else ""
                        tec_text = f" ({detalle_tec_str})" if detalle_tec_str else ""
                        desc_art = f"{cat_base}{veh_text}{tec_text}".strip() or "Repuesto Inventariado"
                else:
                    sku_art = None
                    desc_man = det.descripcion_manual or ""
                    if "[RESERVA EN VERDE]" in desc_man or "[BACKORDER]" in desc_man:
                        tipo_art = "RESERVA"
                        desc_art = desc_man.replace("[BACKORDER]", "[VENTA EN VERDE]").replace("[RESERVA EN VERDE]", "[VENTA EN VERDE]")
                    else:
                        tipo_art = "MISCELANEO"
                        desc_art = desc_man or "Ítem Misceláneo"

                precio_unit = det.precio_unitario if det.precio_unitario is not None else det.precio_final
                articulos_dto.append(
                    ArticuloResumenDTO(
                        cantidad=det.cantidad,
                        tipo=tipo_art,
                        descripcion=desc_art,
                        sku=sku_art,
                        precio=precio_unit,
                        subtotal=det.precio_final,
                        categoria=cat_str,
                        marca=marca_str,
                        modelo=modelo_str,
                        anio=anio_int,
                        detalle_tecnico=detalle_tec_str,
                    )
                )

            # Folio representativo
            folio_doc = orden.folio

            total_op = orden.total_venta + (getattr(orden, "descuento", 0) or 0)
            abono_req = getattr(orden, "abono_requerido", 0) or 0
            saldo_pendiente = orden.monto_pendiente

            # Consultar transacciones previas registradas para la orden
            pagos_query = (
                db.query(Transaccion_Pago)
                .filter(Transaccion_Pago.id_orden == orden.id_orden)
                .order_by(Transaccion_Pago.fecha_pago.asc())
                .all()
            )
            historial_dto: List[HistorialAbonoItemDTO] = []
            abono_acumulado = 0
            for p in pagos_query:
                f_pago_fmt, h_pago_fmt, dt_p_utc = format_chile_datetime(p.fecha_pago)
                historial_dto.append(
                    HistorialAbonoItemDTO(
                        id_pago=p.id_pago,
                        monto=p.monto,
                        metodo_pago=p.metodo_pago,
                        fecha_pago=dt_p_utc,
                        fecha_pago_formateada=f_pago_fmt,
                        hora_pago_formateada=h_pago_fmt,
                        estado_pago=p.estado_pago or "Procesado",
                    )
                )
                abono_acumulado += p.monto

            if orden.monto_pendiente == orden.total_venta:
                # El cliente no ha pagado nada aún
                abono_prev = 0
                if abono_req > 0 and abono_req < orden.total_venta:
                    # Se requiere un abono comercial acordado como sugerencia inicial
                    monto_cobrar = min(abono_req, orden.monto_pendiente)
                else:
                    # Venta estándar sin abono (o abono que cubre el 100%): se cobra el total pendiente
                    monto_cobrar = orden.monto_pendiente
            else:
                # El cliente ya abonó previamente
                abono_prev = abono_acumulado if abono_acumulado > 0 else max(0, orden.total_venta - orden.monto_pendiente)
                monto_cobrar = orden.monto_pendiente

            fecha_fmt, hora_fmt, dt_utc = format_chile_datetime(orden.fecha_creacion)
            cliente_nombre = f"{cliente.nombres} {cliente.apellidos}".strip()
            vendedor_nombre = f"{vendedor.nombres} {vendedor.apellidos}".strip()

            item_dto = CobroPendienteItemResponse(
                id_referencia=orden.id_orden,
                folio_documento=folio_doc,
                tipo_operacion="VENTA",
                estado_documento=orden.estado_orden,
                cliente_nombre=cliente_nombre,
                cliente_rut=cliente.rut_cliente,
                vendedor_nombre=vendedor_nombre,
                fecha_emision=dt_utc,
                fecha_emision_formateada=fecha_fmt,
                hora_emision_formateada=hora_fmt,
                total_operacion=total_op,
                descuento=getattr(orden, "descuento", 0) or 0,
                abono_previo=abono_prev,
                abono_requerido=abono_req if (abono_req > 0 and abono_req < orden.total_venta) else 0,
                saldo_pendiente=saldo_pendiente,
                monto_a_cobrar=monto_cobrar,
                historial_abonos=historial_dto,
                articulos=articulos_dto,
                especificaciones_backorder=None,
            )
            items_resultado.append(item_dto)

    # ─────────────────────────────────────────────────────────────────────────
    # 2. CONSULTAR RESERVAS BACKORDER PENDIENTES DE ABONO / CONFIRMACIÓN
    # ─────────────────────────────────────────────────────────────────────────
    if tipo_filtro in ["TODOS", "BACKORDER"]:
        reservas_query = (
            db.query(Reservas_Backorder, Cliente, Usuario, Categoria_Activo, Orden_Venta)
            .join(Cliente, Reservas_Backorder.id_cliente == Cliente.id_cliente)
            .join(Usuario, Reservas_Backorder.id_vendedor == Usuario.id_usuario)
            .outerjoin(Categoria_Activo, Reservas_Backorder.id_categoria_requerida == Categoria_Activo.id_categoria)
            .outerjoin(Orden_Venta, Reservas_Backorder.id_orden == Orden_Venta.id_orden)
            .filter(Reservas_Backorder.id_sucursal_registro == sucursal_id)
            .filter(Reservas_Backorder.estado_reserva.in_(["Pendiente", "Reservada", "Confirmada"]))
            .filter((Reservas_Backorder.precio_acordado - Reservas_Backorder.monto_abonado) > 0)
        ).all()

        for res, cliente, vendedor, categoria, orden_vinculada in reservas_query:
            folio_doc = (orden_vinculada.folio if orden_vinculada and orden_vinculada.folio else None) or f"RES-{str(res.id_reserva).replace('-', '')[:4].upper()}"
            desc_val = getattr(orden_vinculada, "descuento", 0) or 0 if orden_vinculada else 0
            
            # Subtotal Bruto antes de descuento
            if orden_vinculada and orden_vinculada.total_venta is not None:
                total_op = orden_vinculada.total_venta + desc_val
            else:
                total_op = res.precio_acordado

            abono_req = getattr(res, "abono_requerido", 0) or (getattr(orden_vinculada, "abono_requerido", 0) if orden_vinculada else 0) or 0
            
            # Total neto a liquidar deduciendo descuento
            total_neto = max(0, total_op - desc_val)
            saldo_pendiente = max(0, total_neto - res.monto_abonado)

            # Si la orden vinculada ya está saldada o el saldo pendiente es 0, no mostrar en pendientes
            if saldo_pendiente <= 0 or (orden_vinculada and (orden_vinculada.monto_pendiente == 0 or orden_vinculada.estado_orden == "Pagada")):
                continue

            # Consultar transacciones previas registradas para la reserva
            if res.id_orden is not None:
                filtro_pagos = (Transaccion_Pago.id_reserva == res.id_reserva) | (Transaccion_Pago.id_orden == res.id_orden)
            else:
                filtro_pagos = (Transaccion_Pago.id_reserva == res.id_reserva)

            pagos_reserva_query = (
                db.query(Transaccion_Pago)
                .filter(filtro_pagos)
                .order_by(Transaccion_Pago.fecha_pago.asc())
                .all()
            )
            historial_dto: List[HistorialAbonoItemDTO] = []
            abono_acumulado = 0
            for p in pagos_reserva_query:
                f_pago_fmt, h_pago_fmt, dt_p_utc = format_chile_datetime(p.fecha_pago)
                historial_dto.append(
                    HistorialAbonoItemDTO(
                        id_pago=p.id_pago,
                        monto=p.monto,
                        metodo_pago=p.metodo_pago,
                        fecha_pago=dt_p_utc,
                        fecha_pago_formateada=f_pago_fmt,
                        hora_pago_formateada=h_pago_fmt,
                        estado_pago=p.estado_pago or "Procesado",
                    )
                )
                abono_acumulado += p.monto

            if res.monto_abonado == 0:
                abono_prev = 0
                if abono_req > 0:
                    monto_cobrar = min(abono_req, saldo_pendiente)
                else:
                    monto_cobrar = saldo_pendiente
            else:
                abono_prev = res.monto_abonado if res.monto_abonado > 0 else abono_acumulado
                monto_cobrar = saldo_pendiente

            cat_nombre = categoria.nombre_categoria if categoria else "Repuesto Solicitado"
            transito_str = res.notas_preparacion or "Pendiente de Recepción"

            specs_dto = BackorderEspecificacionesDTO(
                marca=res.marca_requerida,
                modelo=res.modelo_requerido,
                anio=res.anio_requerido,
                categoria=cat_nombre,
                cilindrada=res.cilindrada_requerida,
                combustible=res.combustible_requerido,
                transito=transito_str,
            )

            # Cargar artículos adicionales (misceláneos o inventariados) de la orden híbrida si existen
            articulos_bo_dto: List[ArticuloResumenDTO] = []
            if orden_vinculada:
                detalles_bo_raw = (
                    db.query(
                        Detalle_Orden,
                        Activo_Inventariado,
                        Vehiculo_Origen,
                        Categoria_Activo,
                        Detalle_Motor,
                        Detalle_Caja_Cambio,
                    )
                    .outerjoin(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
                    .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
                    .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
                    .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
                    .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
                    .filter(Detalle_Orden.id_orden == orden_vinculada.id_orden)
                ).all()

                for det, act, veh, cat_a, mot, caj in detalles_bo_raw:
                    desc_man = det.descripcion_manual or ""
                    # Omitir la línea del backorder en la lista de artículos para que se vea exclusivamente en el grid de especificaciones
                    if "[RESERVA EN VERDE]" in desc_man or "[BACKORDER]" in desc_man:
                        continue

                    c_str = cat_a.nombre_categoria if cat_a else None
                    m_str = veh.marca if veh else None
                    mod_str = veh.modelo if veh else None
                    a_int = veh.anio if veh else None

                    tp = []
                    if mot and mot.cilindrada: tp.append(mot.cilindrada)
                    if mot and mot.combustible: tp.append(mot.combustible)
                    if caj and caj.transmision_tipo: tp.append(caj.transmision_tipo)
                    det_tec = " • ".join(tp) if tp else None

                    if act:
                        tipo_art = "INVENTARIADO"
                        sku_art = act.sku_qr_fisico
                        d_art = desc_man or f"{c_str or 'Repuesto'} ({sku_art})"
                    else:
                        tipo_art = "MISCELANEO"
                        sku_art = None
                        d_art = desc_man or "Ítem Misceláneo"

                    p_unit = det.precio_unitario if det.precio_unitario is not None else det.precio_final
                    articulos_bo_dto.append(
                        ArticuloResumenDTO(
                            cantidad=det.cantidad,
                            tipo=tipo_art,
                            descripcion=d_art,
                            sku=sku_art,
                            precio=p_unit,
                            subtotal=det.precio_final,
                            categoria=c_str,
                            marca=m_str,
                            modelo=mod_str,
                            anio=a_int,
                            detalle_tecnico=det_tec,
                        )
                    )

            fecha_fmt, hora_fmt, dt_utc = format_chile_datetime(res.fecha_creacion)
            cliente_nombre = f"{cliente.nombres} {cliente.apellidos}".strip()
            vendedor_nombre = f"{vendedor.nombres} {vendedor.apellidos}".strip()

            item_dto = CobroPendienteItemResponse(
                id_referencia=res.id_reserva,
                folio_documento=folio_doc,
                tipo_operacion="BACKORDER",
                estado_documento=res.estado_reserva,
                cliente_nombre=cliente_nombre,
                cliente_rut=cliente.rut_cliente,
                vendedor_nombre=vendedor_nombre,
                fecha_emision=dt_utc,
                fecha_emision_formateada=fecha_fmt,
                hora_emision_formateada=hora_fmt,
                total_operacion=total_op,
                descuento=desc_val,
                abono_previo=abono_prev,
                abono_requerido=abono_req,
                saldo_pendiente=saldo_pendiente,
                monto_a_cobrar=monto_cobrar,
                historial_abonos=historial_dto,
                articulos=articulos_bo_dto,
                especificaciones_backorder=specs_dto,
            )
            items_resultado.append(item_dto)

    # ─────────────────────────────────────────────────────────────────────────
    # 3. FILTRADO REACTIVO POR BÚSQUEDA MULTICRITERIO
    # ─────────────────────────────────────────────────────────────────────────
    if busqueda and busqueda.strip():
        q = busqueda.strip().lower()
        q_rut = q.replace(".", "").replace("-", "")

        def coincide(it: CobroPendienteItemResponse) -> bool:
            if q in it.folio_documento.lower():
                return True
            if q in it.cliente_nombre.lower():
                return True
            rut_clean = it.cliente_rut.lower().replace(".", "").replace("-", "")
            if q in it.cliente_rut.lower() or (q_rut and q_rut in rut_clean):
                return True
            if q in it.vendedor_nombre.lower():
                return True
            for art in it.articulos:
                if q in art.descripcion.lower():
                    return True
                if art.sku and q in art.sku.lower():
                    return True
            if it.especificaciones_backorder:
                bo = it.especificaciones_backorder
                if q in bo.marca.lower() or q in bo.modelo.lower() or q in bo.categoria.lower():
                    return True
            return False

        items_resultado = [it for it in items_resultado if coincide(it)]

    # Ordenar de más reciente a más antiguo
    items_resultado.sort(key=lambda x: x.fecha_emision, reverse=True)

    return CobroPendienteListResponse(
        total=len(items_resultado),
        sucursal_id=sucursal_id,
        items=items_resultado,
    )


@router.post(
    "/cobros/validar-activo-backorder",
    response_model=ValidarActivoBackorderResponse,
    summary="Validar Atributos de Activo para Backorder",
    description="Valida que el activo ingresado cumpla con los requisitos del backorder y retorna sus especificaciones técnicas."
)
def validar_activo_backorder(
    payload: ValidarActivoBackorderRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_caja_role),
):
    reserva = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_reserva == payload.id_documento).first()
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva Backorder no encontrada.")

    activo_raw = (
        db.query(Activo_Inventariado, Vehiculo_Origen, Detalle_Motor, Detalle_Caja_Cambio, Categoria_Activo, Estado_Activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .outerjoin(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(Activo_Inventariado.sku_qr_fisico == payload.sku_activo)
        .first()
    )

    if not activo_raw:
        raise HTTPException(status_code=404, detail=f"Activo con SKU {payload.sku_activo} no encontrado en inventario.")

    activo, vehiculo, motor, caja_cambio, categoria, estado_activo = activo_raw
    discrepancias = []

    estados_validos = ["disponible", "paletizado"]
    nombre_estado_actual = estado_activo.nombre_estado if estado_activo else ""
    if nombre_estado_actual.lower() not in estados_validos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El repuesto con SKU '{payload.sku_activo}' no está disponible (estado actual: '{nombre_estado_actual}'). Solo se pueden asignar repuestos en estado 'Disponible' o 'Paletizado'."
        )

    if vehiculo and reserva.marca_requerida and vehiculo.marca.lower() != reserva.marca_requerida.lower():
        discrepancias.append(f"Marca requerida: {reserva.marca_requerida}, Marca del repuesto: {vehiculo.marca}")

    if vehiculo and reserva.modelo_requerido and vehiculo.modelo.lower() != reserva.modelo_requerido.lower():
        discrepancias.append(f"Modelo requerido: {reserva.modelo_requerido}, Modelo del repuesto: {vehiculo.modelo}")

    if motor and reserva.cilindrada_requerida and motor.cilindrada:
        req_c = reserva.cilindrada_requerida.lower().replace("l","").replace("cc","").strip()
        act_c = motor.cilindrada.lower().replace("l","").replace("cc","").strip()
        if req_c != act_c:
            discrepancias.append(f"Cilindrada requerida: {reserva.cilindrada_requerida}, Cilindrada del repuesto: {motor.cilindrada}")

    if motor and reserva.combustible_requerido and motor.combustible and motor.combustible.lower() != reserva.combustible_requerido.lower():
        discrepancias.append(f"Combustible requerido: {reserva.combustible_requerido}, Combustible del repuesto: {motor.combustible}")

    transmision_act = None
    if caja_cambio and caja_cambio.transmision_tipo:
        transmision_act = caja_cambio.transmision_tipo
    elif motor and motor.transmision_tipo:
        transmision_act = motor.transmision_tipo

    if transmision_act and reserva.transmision_requerida and transmision_act.lower() != reserva.transmision_requerida.lower():
        discrepancias.append(f"Transmisión requerida: {reserva.transmision_requerida}, Transmisión del repuesto: {transmision_act}")

    coincide = len(discrepancias) == 0
    mensaje = "El repuesto cumple con todas las especificaciones solicitadas." if coincide else "Hay discrepancias en los atributos técnicos."

    ubicacion_partes = []
    if activo.ubicacion_galpon:
        ubicacion_partes.append(f"Galpón {activo.ubicacion_galpon}")
    if activo.ubicacion_pasillo:
        ubicacion_partes.append(f"Pasillo {activo.ubicacion_pasillo}")
    if activo.ubicacion_pallet:
        ubicacion_partes.append(f"Pallet {activo.ubicacion_pallet}")
    ubicacion_str = " • ".join(ubicacion_partes) if ubicacion_partes else None

    activo_detalle = ActivoDetalleBackorderDTO(
        sku=activo.sku_qr_fisico,
        categoria=categoria.nombre_categoria if categoria else None,
        marca=vehiculo.marca if vehiculo else None,
        modelo=vehiculo.modelo if vehiculo else None,
        anio=vehiculo.anio if vehiculo else None,
        cilindrada=motor.cilindrada if motor else None,
        combustible=motor.combustible if motor else None,
        transmision=transmision_act,
        patente=vehiculo.patente if vehiculo else None,
        vin=vehiculo.vin if vehiculo else None,
        ubicacion=ubicacion_str,
        precio_referencia=activo.precio_referencia,
        precio_minimo=activo.precio_minimo,
        precio_maximo=activo.precio_maximo,
        estado_conservacion=estado_activo.nombre_estado if estado_activo else (activo.observacion_estado or activo.estado),
    )

    return ValidarActivoBackorderResponse(
        coincide=coincide,
        discrepancias=discrepancias,
        mensaje=mensaje,
        activo_detalle=activo_detalle
    )


@router.post(
    "/cobros/registrar",
    response_model=RegistrarCobroResponse,
    status_code=status.HTTP_200_OK,
    summary="Registrar Cobro Único o Dividido",
    description="Procesa y persiste el pago de una orden de venta o reserva backorder "
                "validando la cuadratura matemática, rol de caja y atomicidad ACID."
)
def registrar_cobro(
    payload: RegistrarCobroRequest,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_caja_role),
):
    """
    Endpoint transaccional para registro de cobros en caja (SPEC-HU-03).
    Soporta pago único o dividido (split payment) sobre Orden_Venta y Reservas_Backorder.
    """
    # -1. Validación de Horario Comercial de Caja (bloquea cobros presenciales con local cerrado)
    validar_horario_operativo_caja(current_user)

    # 0. Validación de Métodos Seleccionados (SPEC-HU-07)
    if not payload.pagos or len(payload.pagos) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Selecciona un método de pago antes de procesar."
        )

    # 1. Validación de Cuadratura Matemática (CA-05 / SPEC-HU-07)
    total_pagos = sum(p.monto for p in payload.pagos)
    if total_pagos != payload.monto_declarado:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Descuadre financiero: El monto total ingresado no cubre el saldo pendiente de la orden (${payload.monto_declarado:,})."
        )

    # 1.1 Validación de Monto Declarado estrictamente positivo (Evita montos extremos <= 0)
    if payload.monto_declarado <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El monto a cobrar debe ser estrictamente mayor a $0."
        )

    # 2. Validación de montos individuales > 0 (CA-06)
    for p in payload.pagos:
        if p.monto <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Todos los métodos de pago deben registrar un monto estrictamente mayor a $0."
            )

    transacciones_creadas_ids: List[uuid.UUID] = []
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

    # 3. Bloque Transaccional ACID Obligatorio (RULES.md)
    try:
        if payload.tipo_operacion == TipoOperacionEnum.ORDEN:
            orden = db.query(Orden_Venta).filter(
                Orden_Venta.id_orden == payload.id_documento
            ).first()

            if not orden:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"No se encontró la Orden de Venta con ID {payload.id_documento}."
                )

            # Validación Anti-Sobrepago (CA-06)
            if payload.monto_declarado > orden.monto_pendiente:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Sobrepago rechazado: El monto a cobrar (${payload.monto_declarado:,}) "
                           f"supera el saldo pendiente de la orden (${orden.monto_pendiente:,})."
                )

            # Validación de Piso Comercial en Primer Abono:
            total_op = orden.total_venta
            abono_req = getattr(orden, "abono_requerido", 0) or 0
            es_primer_abono = (orden.monto_pendiente == total_op)
            if es_primer_abono and abono_req > 0:
                # Si es el primer abono y no está liquidando el 100% de la venta de contado
                if payload.monto_declarado < abono_req and payload.monto_declarado < orden.monto_pendiente:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"El primer abono no puede ser inferior al monto acordado de ${abono_req:,}."
                    )

            nuevo_saldo = orden.monto_pendiente - payload.monto_declarado
            qr_hash: Optional[str] = None

            # Transiciones de Estado y Hash QR (SPEC-HU-04 Sec 3.2 / Tarea 2)
            if nuevo_saldo == 0:
                tiene_activos_inventariados = db.query(Detalle_Orden).filter(
                    Detalle_Orden.id_orden == orden.id_orden,
                    Detalle_Orden.id_activo.isnot(None)
                ).first() is not None

                tiene_despacho = db.query(Despacho).filter(
                    Despacho.id_orden == orden.id_orden,
                    Despacho.estado == "Activo"
                ).first() is not None

                reserva_vinculada = db.query(Reservas_Backorder).filter(
                    Reservas_Backorder.id_orden == orden.id_orden
                ).first()

                if reserva_vinculada:
                    orden.estado_orden = "Pagada"
                    reserva_vinculada.monto_abonado = reserva_vinculada.precio_acordado
                    reserva_vinculada.fecha_actualizacion = now_utc
                    if payload.sku_activo_atribuido and payload.sku_activo_atribuido.strip():
                        activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.sku_qr_fisico == payload.sku_activo_atribuido.strip()).first()
                        if not activo:
                            raise HTTPException(status_code=404, detail=f"Activo con SKU {payload.sku_activo_atribuido} no encontrado.")
                        estados_validos = ["disponible", "paletizado"]
                        estado_obj = db.query(Estado_Activo).filter(Estado_Activo.id_estado == activo.id_estado).first()
                        if not estado_obj or estado_obj.nombre_estado.lower() not in estados_validos:
                            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="El activo no está Disponible o Paletizado.")
                        
                        estado_vendido = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
                        if not estado_vendido:
                            estado_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
                            db.add(estado_vendido)
                            db.flush()
                        activo.id_estado = estado_vendido.id_estado
                        activo.reservado_por = None
                        activo.reserva_expira_en = None
                        reserva_vinculada.id_activo_asignado = activo.id_activo
                        reserva_vinculada.estado_reserva = "Completada"

                        qr_hash = f"TX-QR-{uuid.uuid4()}"
                        orden.qr_transaccional_salida = qr_hash

                        detalles_bo = db.query(Detalle_Orden).filter(
                            Detalle_Orden.id_orden == orden.id_orden,
                            Detalle_Orden.id_activo.is_(None)
                        ).all()
                        if detalles_bo:
                            detalles_bo[0].id_activo = activo.id_activo
                            detalles_bo[0].estado_preparacion = "Listo"
                    else:
                        reserva_vinculada.id_activo_asignado = None
                        reserva_vinculada.estado_reserva = "Confirmada"
                        qr_hash = None
                        orden.qr_transaccional_salida = None
                elif tiene_activos_inventariados or tiene_despacho:
                    orden.estado_orden = "Pagada"
                    qr_hash = f"TX-QR-{uuid.uuid4()}"
                    orden.qr_transaccional_salida = qr_hash

                    # En órdenes mixtas (activos + misceláneos), marcar los misceláneos como 'Listo' y activos como 'Vendido'
                    detalles_orden = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
                    estado_vendido = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
                    if not estado_vendido:
                        estado_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
                        db.add(estado_vendido)
                        db.flush()

                    for d in detalles_orden:
                        if d.id_activo is None:
                            d.estado_preparacion = "Listo"
                            d.fecha_preparacion = now_utc
                        else:
                            act = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                            if act:
                                act.id_estado = estado_vendido.id_estado
                                act.version_lock = (act.version_lock or 1) + 1
                                act.fecha_actualizacion = now_utc
                else:
                    # Sin activos inventariados ni backorder (Solo misceláneos / servicios)
                    detalles_orden = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
                    for d in detalles_orden:
                        d.estado_preparacion = "Listo"
                        d.fecha_preparacion = now_utc

                    orden.estado_orden = "Completada"
                    qr_hash = None
                    orden.qr_transaccional_salida = None
            else:
                orden.estado_orden = "Reservada"
                orden.qr_transaccional_salida = None

            orden.monto_pendiente = nuevo_saldo
            orden.id_cajera = current_user.id_usuario
            orden.fecha_actualizacion = now_utc

            folio_doc = orden.folio or f"ORD-{str(orden.id_orden).replace('-', '')[:8].upper()}"
            estado_resultado = orden.estado_orden

            # Registrar cada método en Transaccion_Pago
            for pago_item in payload.pagos:
                id_transaccion = uuid.uuid4()
                transaccion = Transaccion_Pago(
                    id_pago=id_transaccion,
                    id_orden=orden.id_orden,
                    id_reserva=None,
                    monto=pago_item.monto,
                    metodo_pago=pago_item.metodo.value,
                    estado_pago="Procesado",
                    fecha_pago=now_utc,
                )
                db.add(transaccion)
                transacciones_creadas_ids.append(id_transaccion)

        elif payload.tipo_operacion == TipoOperacionEnum.BACKORDER:
            reserva = db.query(Reservas_Backorder).filter(
                Reservas_Backorder.id_reserva == payload.id_documento
            ).first()

            if not reserva:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"No se encontró la Reserva Backorder con ID {payload.id_documento}."
                )

            orden_vinculada = None
            if reserva.id_orden:
                orden_vinculada = db.query(Orden_Venta).filter(Orden_Venta.id_orden == reserva.id_orden).first()

            desc_val = getattr(orden_vinculada, "descuento", 0) or 0 if orden_vinculada else 0
            base_total = orden_vinculada.total_venta if (orden_vinculada and orden_vinculada.total_venta is not None) else max(0, reserva.precio_acordado - desc_val)
            saldo_pendiente_backorder = max(0, base_total - reserva.monto_abonado)

            if payload.monto_declarado > saldo_pendiente_backorder:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Sobrepago rechazado: El monto declarado (${payload.monto_declarado:,}) "
                           f"supera el saldo pendiente de la reserva (${saldo_pendiente_backorder:,})."
                )

            # Validación de Piso Comercial en Primer Abono:
            abono_req = getattr(reserva, "abono_requerido", 0) or (getattr(orden_vinculada, "abono_requerido", 0) if orden_vinculada else 0) or 0
            es_primer_abono = (reserva.monto_abonado == 0)
            if es_primer_abono and abono_req > 0:
                if payload.monto_declarado < abono_req and payload.monto_declarado < saldo_pendiente_backorder:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"El primer abono no puede ser inferior al monto acordado de ${abono_req:,}."
                    )

            reserva.monto_abonado += payload.monto_declarado
            reserva.fecha_actualizacion = now_utc
            nuevo_saldo = max(0, base_total - reserva.monto_abonado)
            if nuevo_saldo == 0:
                reserva.monto_abonado = reserva.precio_acordado
            
            target_id_orden = None
            if nuevo_saldo == 0:
                if payload.sku_activo_atribuido and payload.sku_activo_atribuido.strip():
                    sku_clean = payload.sku_activo_atribuido.strip()
                    activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.sku_qr_fisico == sku_clean).first()
                    if not activo:
                        raise HTTPException(status_code=404, detail=f"Activo con SKU {sku_clean} no encontrado.")
                    
                    estados_validos = ["disponible", "paletizado"]
                    estado_obj = db.query(Estado_Activo).filter(Estado_Activo.id_estado == activo.id_estado).first()
                    if not estado_obj or estado_obj.nombre_estado.lower() not in estados_validos:
                        raise HTTPException(
                            status_code=status.HTTP_409_CONFLICT,
                            detail=f"El activo ingresado está en estado '{estado_obj.nombre_estado if estado_obj else 'Desconocido'}'. Solo se permite asignar activos en estado Disponible o Paletizado."
                        )
                    
                    vehiculo = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first()
                    hay_discrepancia = False
                    if vehiculo:
                        if reserva.marca_requerida and vehiculo.marca.lower() != reserva.marca_requerida.lower(): hay_discrepancia = True
                        if reserva.modelo_requerido and vehiculo.modelo.lower() != reserva.modelo_requerido.lower(): hay_discrepancia = True
                    
                    if hay_discrepancia and not payload.forzar_atribucion:
                        raise HTTPException(status_code=400, detail="El activo físico no coincide con lo requerido por el Backorder. Active la sobreescritura si desea continuar.")

                    estado_vendido = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
                    if not estado_vendido:
                        estado_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
                        db.add(estado_vendido)
                        db.flush()
                    activo.id_estado = estado_vendido.id_estado
                    activo.reservado_por = None
                    activo.reserva_expira_en = None
                    
                    reserva.id_activo_asignado = activo.id_activo
                    reserva.estado_reserva = "Completada"

                    qr_hash = f"TX-QR-{uuid.uuid4()}"

                    orden_existente = None
                    if reserva.id_orden:
                        orden_existente = db.query(Orden_Venta).filter(Orden_Venta.id_orden == reserva.id_orden).first()

                    if orden_existente:
                        orden_existente.estado_orden = "Pagada"
                        orden_existente.monto_pendiente = 0
                        orden_existente.qr_transaccional_salida = qr_hash
                        orden_existente.id_cajera = current_user.id_usuario
                        orden_existente.fecha_actualizacion = now_utc
                        orden_operativa = orden_existente

                        # Asociar activo al detalle backorder de la orden
                        detalles_bo = db.query(Detalle_Orden).filter(
                            Detalle_Orden.id_orden == orden_existente.id_orden,
                            Detalle_Orden.id_activo.is_(None)
                        ).all()
                        if detalles_bo:
                            det_target = detalles_bo[0]
                            det_target.id_activo = activo.id_activo
                            det_target.estado_preparacion = "Listo"
                            det_target.descripcion_manual = f"[BACKORDER ASIGNADO] {activo.sku_qr_fisico} - {reserva.marca_requerida} {reserva.modelo_requerido}"
                        else:
                            detalle = Detalle_Orden(
                                id_orden=orden_existente.id_orden,
                                id_activo=activo.id_activo,
                                descripcion_manual=f"[BACKORDER] {reserva.marca_requerida} {reserva.modelo_requerido}",
                                notas_preparacion="Entregado en caja por backorder",
                                cantidad=1,
                                precio_unitario=reserva.precio_acordado,
                                precio_final=reserva.precio_acordado,
                                estado_preparacion="Listo",
                            )
                            db.add(detalle)
                    else:
                        nueva_orden = Orden_Venta(
                            id_cliente=reserva.id_cliente,
                            id_vendedor=reserva.id_vendedor,
                            id_cajera=current_user.id_usuario,
                            id_sucursal=reserva.id_sucursal_registro,
                            estado_orden="Pagada",
                            qr_transaccional_salida=qr_hash,
                            total_venta=reserva.precio_acordado,
                            monto_pendiente=0,
                            abono_requerido=0,
                            fecha_creacion=now_utc,
                            fecha_actualizacion=now_utc,
                        )
                        db.add(nueva_orden)
                        db.flush()
                        reserva.id_orden = nueva_orden.id_orden
                        orden_operativa = nueva_orden

                        detalle = Detalle_Orden(
                            id_orden=nueva_orden.id_orden,
                            id_activo=activo.id_activo,
                            descripcion_manual=f"[BACKORDER] {reserva.marca_requerida} {reserva.modelo_requerido}",
                            notas_preparacion="Entregado en caja por backorder",
                            cantidad=1,
                            precio_unitario=reserva.precio_acordado,
                            precio_final=reserva.precio_acordado,
                            estado_preparacion="Listo",
                        )
                        db.add(detalle)
                        db.flush()

                    db.query(Transaccion_Pago).filter(Transaccion_Pago.id_reserva == reserva.id_reserva).update({"id_orden": orden_operativa.id_orden})

                    folio_doc = orden_operativa.folio or f"ORD-{str(orden_operativa.id_orden).replace('-', '')[:4].upper()}"
                    estado_resultado = "Completada"
                    target_id_orden = orden_operativa.id_orden
                else:
                    # Pago total del Backorder sin atribuir activo aún (repuesto pendiente de arribar a bodega)
                    reserva.id_activo_asignado = None
                    reserva.estado_reserva = "Confirmada"
                    qr_hash = None

                    orden_existente = None
                    if reserva.id_orden:
                        orden_existente = db.query(Orden_Venta).filter(Orden_Venta.id_orden == reserva.id_orden).first()

                    if orden_existente:
                        orden_existente.estado_orden = "Pagada"
                        orden_existente.monto_pendiente = 0
                        orden_existente.qr_transaccional_salida = None  # No hay QR hasta que el vendedor asigne el activo
                        orden_existente.id_cajera = current_user.id_usuario
                        orden_existente.fecha_actualizacion = now_utc
                        orden_operativa = orden_existente

                        detalles_bo = db.query(Detalle_Orden).filter(
                            Detalle_Orden.id_orden == orden_existente.id_orden,
                            Detalle_Orden.id_activo.is_(None)
                        ).all()
                        for det in detalles_bo:
                            det.estado_preparacion = "No Aplica"
                    else:
                        nueva_orden = Orden_Venta(
                            id_cliente=reserva.id_cliente,
                            id_vendedor=reserva.id_vendedor,
                            id_cajera=current_user.id_usuario,
                            id_sucursal=reserva.id_sucursal_registro,
                            estado_orden="Pagada",
                            qr_transaccional_salida=None,
                            total_venta=reserva.precio_acordado,
                            monto_pendiente=0,
                            abono_requerido=0,
                            fecha_creacion=now_utc,
                            fecha_actualizacion=now_utc,
                        )
                        db.add(nueva_orden)
                        db.flush()
                        reserva.id_orden = nueva_orden.id_orden
                        orden_operativa = nueva_orden

                        detalle = Detalle_Orden(
                            id_orden=nueva_orden.id_orden,
                            id_activo=None,
                            descripcion_manual=f"[VENTA EN VERDE PENDIENTE DE ASIGNACIÓN] {reserva.marca_requerida} {reserva.modelo_requerido}",
                            notas_preparacion="Pagado sin asignar. Esperando arribo de activo a bodega.",
                            cantidad=1,
                            precio_unitario=reserva.precio_acordado,
                            precio_final=reserva.precio_acordado,
                            estado_preparacion="No Aplica",
                        )
                        db.add(detalle)
                        db.flush()

                    db.query(Transaccion_Pago).filter(Transaccion_Pago.id_reserva == reserva.id_reserva).update({"id_orden": orden_operativa.id_orden})

                    folio_doc = orden_operativa.folio or f"ORD-{str(orden_operativa.id_orden).replace('-', '')[:4].upper()}"
                    estado_resultado = "Pagada"
                    target_id_orden = orden_operativa.id_orden
            else:
                reserva.estado_reserva = "Confirmada"
                qr_hash = None
                folio_doc = (orden_vinculada.folio if orden_vinculada and orden_vinculada.folio else None) or f"RES-{str(reserva.id_reserva).replace('-', '')[:4].upper()}"
                estado_resultado = reserva.estado_reserva

                if orden_vinculada:
                    orden_vinculada.monto_pendiente = nuevo_saldo
                    orden_vinculada.id_cajera = current_user.id_usuario
                    orden_vinculada.fecha_actualizacion = now_utc
                    target_id_orden = orden_vinculada.id_orden

            # Registrar cada método en Transaccion_Pago
            for pago_item in payload.pagos:
                id_transaccion = uuid.uuid4()
                transaccion = Transaccion_Pago(
                    id_pago=id_transaccion,
                    id_orden=target_id_orden or reserva.id_orden,
                    id_reserva=reserva.id_reserva,
                    monto=pago_item.monto,
                    metodo_pago=pago_item.metodo.value,
                    estado_pago="Procesado",
                    fecha_pago=now_utc,
                )
                db.add(transaccion)
                transacciones_creadas_ids.append(id_transaccion)

        db.commit()

        # =========================================================================
        # NOTIFICACIÓN ASÍNCRONA A GERENCIA VÍA TELEGRAM
        # =========================================================================
        try:
            if nuevo_saldo <= 0:
                cajera_nombre = f"{current_user.nombres} {current_user.apellidos}".strip()
                medios_str = ", ".join(dict.fromkeys(p.metodo.value for p in payload.pagos))

                # Caso 1: Venta en Verde (Reserva Backorder pagada al 100%)
                reserva_obj = None
                if payload.tipo_operacion == TipoOperacionEnum.BACKORDER and 'reserva' in locals():
                    reserva_obj = reserva
                elif 'reserva_vinculada' in locals() and reserva_vinculada is not None:
                    reserva_obj = reserva_vinculada

                if reserva_obj is not None:
                    cli_obj = db.query(Cliente).filter(Cliente.id_cliente == reserva_obj.id_cliente).first()
                    vend_obj = db.query(Usuario).filter(Usuario.id_usuario == reserva_obj.id_vendedor).first()
                    cat_obj = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == reserva_obj.id_categoria_requerida).first() if reserva_obj.id_categoria_requerida else None

                    cli_nom = f"{cli_obj.nombres} {cli_obj.apellidos}".strip() if cli_obj else "Cliente Particular"
                    cli_rut = cli_obj.rut_cliente if cli_obj else "S/RUT"
                    cli_tel = cli_obj.telefono if cli_obj and cli_obj.telefono else "Sin teléfono registrado"
                    vend_nom = f"{vend_obj.nombres} {vend_obj.apellidos}".strip() if vend_obj else "Vendedor"
                    cat_nom = cat_obj.nombre_categoria if cat_obj else "Repuesto por Encargo"
                    marca_mod = f"{reserva_obj.marca_requerida or ''} {reserva_obj.modelo_requerido or ''}".strip() or "Genérico"

                    background_tasks.add_task(
                        TelegramService.notificar_venta_en_verde_pagada,
                        folio=folio_doc,
                        cliente_nombre=cli_nom,
                        rut_cliente=cli_rut,
                        telefono_contacto=cli_tel,
                        categoria_requerida=cat_nom,
                        marca_modelo=marca_mod,
                        vendedor_nombre=vend_nom,
                        cajero_nombre=cajera_nombre,
                        monto_pagado=payload.monto_declarado,
                        medio_pago=medios_str,
                    )

                # Caso 2: Venta Regular en Caja (Solo si tiene al menos un repuesto inventariado)
                elif 'orden' in locals() and orden is not None:
                    detalles_orden = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
                    items_inv = [d for d in detalles_orden if d.id_activo is not None]

                    if len(items_inv) > 0:
                        cli_obj = db.query(Cliente).filter(Cliente.id_cliente == orden.id_cliente).first()
                        vend_obj = db.query(Usuario).filter(Usuario.id_usuario == orden.id_vendedor).first()

                        cli_nom = f"{cli_obj.nombres} {cli_obj.apellidos}".strip() if cli_obj else "Cliente Particular"
                        cli_rut = cli_obj.rut_cliente if cli_obj else "S/RUT"
                        vend_nom = f"{vend_obj.nombres} {vend_obj.apellidos}".strip() if vend_obj else "Vendedor"

                        background_tasks.add_task(
                            TelegramService.notificar_venta_pagada,
                            folio=folio_doc,
                            cliente_nombre=cli_nom,
                            rut_cliente=cli_rut,
                            vendedor_nombre=vend_nom,
                            cajero_nombre=cajera_nombre,
                            total_venta=orden.total_venta,
                            medio_pago=medios_str,
                            cantidad_items_inventariados=len(items_inv),
                        )
        except Exception as e_notif:
            print(f"⚠️ [TELEGRAM] Error no bloqueante al preparar notificación: {e_notif}")

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al registrar el cobro: {str(e)}"
        )

    return RegistrarCobroResponse(
        success=True,
        mensaje=f"Cobro registrado exitosamente para el documento {folio_doc}.",
        folio=folio_doc,
        monto_cobrado=payload.monto_declarado,
        nuevo_saldo_pendiente=nuevo_saldo,
        estado_actualizado=estado_resultado,
        transacciones_ids=transacciones_creadas_ids,
        qr_generado=qr_hash,
    )


def format_clp(amount: int) -> str:
    """Formatea enteros a moneda CLP (ej: 420000 -> $420.000)."""
    return f"${amount:,}".replace(",", ".")


def parse_periodo_chile(
    periodo: Optional[str],
    fecha_desde: Optional[str] = None,
    fecha_hasta: Optional[str] = None,
) -> tuple[Optional[datetime], Optional[datetime]]:
    """
    Calcula los límites temporales en UTC correspondientes al huso horario de Chile (America/Santiago).
    """
    p = (periodo or "HOY").strip().upper()
    ahora_chile = datetime.now(tz_chile)

    if p == "HOY":
        start_local = datetime.combine(ahora_chile.date(), time.min, tzinfo=tz_chile)
        end_local = datetime.combine(ahora_chile.date(), time.max, tzinfo=tz_chile)
    elif p == "ESTA_SEMANA":
        lunes = ahora_chile.date() - timedelta(days=ahora_chile.weekday())
        domingo = lunes + timedelta(days=6)
        start_local = datetime.combine(lunes, time.min, tzinfo=tz_chile)
        end_local = datetime.combine(domingo, time.max, tzinfo=tz_chile)
    elif p == "ESTE_MES":
        primer_dia = ahora_chile.date().replace(day=1)
        if primer_dia.month == 12:
            prox_mes = primer_dia.replace(year=primer_dia.year + 1, month=1)
        else:
            prox_mes = primer_dia.replace(month=primer_dia.month + 1)
        ultimo_dia = prox_mes - timedelta(days=1)
        start_local = datetime.combine(primer_dia, time.min, tzinfo=tz_chile)
        end_local = datetime.combine(ultimo_dia, time.max, tzinfo=tz_chile)
    elif p == "RANGO":
        if not fecha_desde or not fecha_hasta:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="fecha_desde y fecha_hasta son obligatorias para el período RANGO.",
            )
        try:
            d_desde = datetime.strptime(str(fecha_desde).strip(), "%Y-%m-%d").date()
            d_hasta = datetime.strptime(str(fecha_hasta).strip(), "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Formato de fecha inválido. Debe ser YYYY-MM-DD.",
            )
        if d_desde > d_hasta:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="fecha_desde no puede ser posterior a fecha_hasta.",
            )
        start_local = datetime.combine(d_desde, time.min, tzinfo=tz_chile)
        end_local = datetime.combine(d_hasta, time.max, tzinfo=tz_chile)
    elif p == "TODOS":
        return None, None
    else:
        start_local = datetime.combine(ahora_chile.date(), time.min, tzinfo=tz_chile)
        end_local = datetime.combine(ahora_chile.date(), time.max, tzinfo=tz_chile)

    start_utc = start_local.astimezone(timezone.utc).replace(tzinfo=None)
    end_utc = end_local.astimezone(timezone.utc).replace(tzinfo=None)
    return start_utc, end_utc


@router.get(
    "/historial",
    response_model=HistorialCajaResponse,
    summary="Historial de Órdenes y Auditoría de Cobros",
    description="Retorna el historial paginado de órdenes y transacciones de caja, con filtros multicriterio, "
                "métricas agregadas de cuadre/arqueo y trazabilidad detallada de pagos e ítems."
)
def obtener_historial_caja(
    sucursal_id: int = Query(..., description="ID de la sucursal activa"),
    periodo: Optional[str] = Query("HOY", description="Atajo de período: 'HOY', 'ESTA_SEMANA', 'ESTE_MES', 'RANGO', 'TODOS'"),
    fecha_desde: Optional[str] = Query(None, description="Fecha de inicio YYYY-MM-DD (para período RANGO)"),
    fecha_hasta: Optional[str] = Query(None, description="Fecha de término YYYY-MM-DD (para período RANGO)"),
    estado_orden: Optional[str] = Query("TODOS", description="Filtro de estado: 'TODOS', 'Pagada', 'Completada', 'Anulada'"),
    metodo_pago: Optional[str] = Query("TODOS", description="Filtro de método: 'TODOS', 'Efectivo', 'Débito', 'Crédito', 'Transferencia', 'Cheque'"),
    busqueda: Optional[str] = Query(None, description="Búsqueda por Folio, RUT, Cliente, Vendedor o Cajera"),
    monto_min: Optional[int] = Query(None, description="Monto mínimo de venta"),
    monto_max: Optional[int] = Query(None, description="Monto máximo de venta"),
    id_cajera: Optional[UUID] = Query(None, description="ID del usuario cajera"),
    id_vendedor: Optional[UUID] = Query(None, description="ID del usuario vendedor"),
    pagina: int = Query(1, ge=1, description="Número de página"),
    limite: int = Query(20, ge=1, le=100, description="Registros por página"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_caja_role),
):
    start_utc, end_utc = parse_periodo_chile(periodo, fecha_desde, fecha_hasta)

    UsuarioVendedor = aliased(Usuario, name="vendedor")
    UsuarioCajera = aliased(Usuario, name="cajera")

    query = (
        db.query(Orden_Venta, Cliente, UsuarioVendedor, UsuarioCajera)
        .join(Cliente, Orden_Venta.id_cliente == Cliente.id_cliente)
        .join(UsuarioVendedor, Orden_Venta.id_vendedor == UsuarioVendedor.id_usuario)
        .outerjoin(UsuarioCajera, Orden_Venta.id_cajera == UsuarioCajera.id_usuario)
        .filter(Orden_Venta.id_sucursal == sucursal_id)
        .filter(
            or_(
                Orden_Venta.estado_orden != "Reservada",
                Orden_Venta.id_orden.in_(select(Transaccion_Pago.id_orden).filter(Transaccion_Pago.id_orden.isnot(None))),
            )
        )
    )

    if start_utc is not None and end_utc is not None:
        # Una orden pertenece al período contable de caja si:
        # a) Tiene transacciones de pago registradas dentro del período, ó
        # b) No tiene transacciones de pago pero su fecha_actualizacion o fecha_creacion está en el período (ej: anuladas)
        subq_pagos = (
            select(Transaccion_Pago.id_orden)
            .filter(
                Transaccion_Pago.id_orden.isnot(None),
                Transaccion_Pago.fecha_pago.between(start_utc, end_utc),
            )
        )
        subq_todos_pagos = (
            select(Transaccion_Pago.id_orden)
            .filter(Transaccion_Pago.id_orden.isnot(None))
        )

        cond_con_pago_en_periodo = Orden_Venta.id_orden.in_(subq_pagos)
        cond_sin_pagos_en_periodo = and_(
            Orden_Venta.id_orden.notin_(subq_todos_pagos),
            func.coalesce(Orden_Venta.fecha_actualizacion, Orden_Venta.fecha_creacion).between(start_utc, end_utc),
        )
        query = query.filter(or_(cond_con_pago_en_periodo, cond_sin_pagos_en_periodo))

    if estado_orden and estado_orden.strip().upper() != "TODOS":
        query = query.filter(Orden_Venta.estado_orden == estado_orden.strip())

    if id_cajera:
        query = query.filter(Orden_Venta.id_cajera == id_cajera)

    if id_vendedor:
        query = query.filter(Orden_Venta.id_vendedor == id_vendedor)

    if monto_min is not None:
        query = query.filter(Orden_Venta.total_venta >= monto_min)

    if monto_max is not None:
        query = query.filter(Orden_Venta.total_venta <= monto_max)

    resultados_raw = query.order_by(Orden_Venta.fecha_creacion.desc()).all()

    items_filtrados: List[HistorialOrdenItemResponse] = []

    for orden, cliente, vendedor, cajera in resultados_raw:
        # Obtener pagos
        pagos_db = (
            db.query(Transaccion_Pago)
            .filter(Transaccion_Pago.id_orden == orden.id_orden)
            .order_by(Transaccion_Pago.fecha_pago.asc())
            .all()
        )

        desglose_pagos = [
            HistorialPagoDetalleDTO(
                id_transaccion=p.id_pago,
                metodo_pago=p.metodo_pago,
                monto=p.monto,
                fecha_pago=p.fecha_pago,
            )
            for p in pagos_db
        ]

        # Filtro por método de pago normalizando tildes (Débito/Debito, Crédito/Credito)
        if metodo_pago and metodo_pago.strip().upper() != "TODOS":
            mp_filtro = strip_accents(metodo_pago.strip())
            encontrado = any(mp_filtro in strip_accents(p.metodo_pago or "") for p in pagos_db)
            if not encontrado:
                continue

        # Obtener detalles de repuestos/artículos
        detalles_raw = (
            db.query(
                Detalle_Orden,
                Activo_Inventariado,
                Vehiculo_Origen,
                Categoria_Activo,
                Detalle_Motor,
                Detalle_Caja_Cambio,
            )
            .outerjoin(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
            .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
            .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
            .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
            .filter(Detalle_Orden.id_orden == orden.id_orden)
        ).all()

        articulos_dto: List[HistorialArticuloDTO] = []
        for det, activo, vehiculo, categoria, motor, caja in detalles_raw:
            cat_str = categoria.nombre_categoria if categoria else None
            marca_str = vehiculo.marca if vehiculo else None
            modelo_str = vehiculo.modelo if vehiculo else None
            anio_int = vehiculo.anio if vehiculo else None

            tec_parts = []
            if motor:
                if motor.cilindrada:
                    tec_parts.append(motor.cilindrada)
                if motor.combustible:
                    tec_parts.append(motor.combustible)
            if caja and caja.transmision_tipo:
                tec_parts.append(caja.transmision_tipo)
            detalle_tec_str = " • ".join(tec_parts) if tec_parts else None

            if activo:
                tipo_art = "INVENTARIADO"
                sku_art = activo.sku_qr_fisico

                es_desc_antigua_solo_sku = bool(
                    det.descripcion_manual
                    and (f"- SKU: {activo.sku_qr_fisico}" in det.descripcion_manual or f"SKU: {activo.sku_qr_fisico}" in det.descripcion_manual)
                )

                if det.descripcion_manual and not es_desc_antigua_solo_sku:
                    desc_art = det.descripcion_manual
                else:
                    cat_base = cat_str or "Repuesto"
                    veh_parts = [p for p in [marca_str, modelo_str, str(anio_int) if anio_int else None] if p]
                    veh_text = f" - {' '.join(veh_parts)}" if veh_parts else ""
                    tec_text = f" ({detalle_tec_str})" if detalle_tec_str else ""
                    desc_art = f"{cat_base}{veh_text}{tec_text}".strip() or "Repuesto Inventariado"
            else:
                sku_art = None
                desc_man = det.descripcion_manual or ""
                if "[RESERVA EN VERDE]" in desc_man or "[BACKORDER]" in desc_man:
                    tipo_art = "RESERVA"
                    desc_art = desc_man.replace("[BACKORDER]", "[VENTA EN VERDE]").replace("[RESERVA EN VERDE]", "[VENTA EN VERDE]")
                else:
                    tipo_art = "MISCELANEO"
                    desc_art = desc_man or "Ítem Misceláneo"

            precio_unit = det.precio_unitario if det.precio_unitario is not None else det.precio_final
            articulos_dto.append(
                HistorialArticuloDTO(
                    cantidad=det.cantidad,
                    tipo=tipo_art,
                    descripcion=desc_art,
                    sku=sku_art,
                    precio=precio_unit,
                    subtotal=det.precio_final,
                    categoria=cat_str,
                    marca=marca_str,
                    modelo=modelo_str,
                    anio=anio_int,
                    detalle_tecnico=detalle_tec_str,
                )
            )

        # Folio
        folio_doc = orden.folio
        if not folio_doc or folio_doc.startswith("TX-QR-"):
            if orden.numero_orden:
                folio_doc = f"ORD-{orden.numero_orden:04d}"
            elif orden.id_orden:
                folio_doc = f"ORD-{str(orden.id_orden).replace('-', '')[:8].upper()}"
            else:
                folio_doc = "ORD-0000"

        # Fecha operativa de la orden en caja (momento del último pago registrado o actualización de estado)
        fecha_operativa = orden.fecha_creacion
        if pagos_db:
            fechas_pago = [p.fecha_pago for p in pagos_db if p.fecha_pago is not None]
            if fechas_pago:
                fecha_operativa = max(fechas_pago)
        elif orden.fecha_actualizacion:
            fecha_operativa = orden.fecha_actualizacion

        fecha_fmt, hora_fmt, dt_utc = format_chile_datetime(fecha_operativa)
        dt_chile = dt_utc.astimezone(tz_chile)
        fecha_iso = dt_chile.strftime("%Y-%m-%d")
        fecha_hora_fmt = f"{hora_fmt} - {fecha_fmt}"

        # Fechas y horas en formato estándar chileno con año en 2 dígitos (26) para trazabilidad
        dt_chile_creacion = (orden.fecha_creacion.replace(tzinfo=timezone.utc) if orden.fecha_creacion.tzinfo is None else orden.fecha_creacion).astimezone(tz_chile)
        fecha_creacion_fmt_26 = dt_chile_creacion.strftime("%d/%m/%y")
        hora_creacion_fmt = dt_chile_creacion.strftime("%H:%M")
        fecha_creacion_formateada = f"{fecha_creacion_fmt_26} a las {hora_creacion_fmt} hrs"

        dt_chile_op = (fecha_operativa.replace(tzinfo=timezone.utc) if fecha_operativa.tzinfo is None else fecha_operativa).astimezone(tz_chile)
        fecha_fmt_26 = dt_chile_op.strftime("%d/%m/%y")
        hora_fmt = dt_chile_op.strftime("%H:%M")

        cliente_nombre = f"{cliente.nombres} {cliente.apellidos}".strip()
        vendedor_nombre = f"{vendedor.nombres} {vendedor.apellidos}".strip()
        cajera_nombre = f"{cajera.nombres} {cajera.apellidos}".strip() if cajera else "Caja 01"

        # Métodos Resumen String
        if desglose_pagos:
            metodos_resumen = " + ".join([f"{p.metodo_pago}: {format_clp(p.monto)}" for p in desglose_pagos])
            modalidad = "split" if len(desglose_pagos) > 1 else "unico"
            total_liquidado = sum(p.monto for p in desglose_pagos)
        else:
            metodos_resumen = "Sin pagos registrados" if orden.estado_orden != "Anulada" else "Anulada"
            modalidad = "unico"
            total_liquidado = max(0, orden.total_venta - orden.monto_pendiente)

        abono_prev = max(0, orden.total_venta - orden.monto_pendiente - total_liquidado)

        # Historial de movimientos (auditoría cronológica con fecha y hora 24h, año 2 dígitos 26)
        movimientos: List[HistorialMovimientoDTO] = [
            HistorialMovimientoDTO(
                hora=f"{fecha_creacion_fmt_26} {hora_creacion_fmt} hrs",
                evento=f"Orden emitida en Mesón por {vendedor_nombre}",
            )
        ]

        if desglose_pagos:
            for idx, p in enumerate(desglose_pagos):
                p_dt = (p.fecha_pago.replace(tzinfo=timezone.utc) if p.fecha_pago and p.fecha_pago.tzinfo is None else p.fecha_pago or datetime.now(timezone.utc)).astimezone(tz_chile)
                p_fecha_26 = p_dt.strftime("%d/%m/%y")
                p_hora = p_dt.strftime("%H:%M")
                es_ultimo = (idx == len(desglose_pagos) - 1)
                if orden.estado_orden in ["Pagada", "Completada", "Despachada"] and es_ultimo and orden.monto_pendiente == 0:
                    evento_str = f"Pago liquidado en ventanilla: {p.metodo_pago} ({format_clp(p.monto)}) por {cajera_nombre}"
                else:
                    evento_str = f"Abono registrado en ventanilla: {p.metodo_pago} ({format_clp(p.monto)}) por {cajera_nombre}"
                movimientos.append(
                    HistorialMovimientoDTO(
                        hora=f"{p_fecha_26} {p_hora} hrs",
                        evento=evento_str,
                    )
                )

        if orden.qr_transaccional_salida:
            movimientos.append(
                HistorialMovimientoDTO(
                    hora=f"{fecha_fmt_26} {hora_fmt} hrs",
                    evento="QR Transaccional generado para barrera de salida",
                )
            )

        auditoria_barrera = (
            db.query(Auditoria_Barrera)
            .filter(Auditoria_Barrera.id_orden == orden.id_orden)
            .first()
        )
        if auditoria_barrera:
            b_dt = (auditoria_barrera.fecha_escaneo.replace(tzinfo=timezone.utc) if auditoria_barrera.fecha_escaneo.tzinfo is None else auditoria_barrera.fecha_escaneo).astimezone(tz_chile)
            b_fecha_26 = b_dt.strftime("%d/%m/%y")
            b_hora = b_dt.strftime("%H:%M")
            movimientos.append(
                HistorialMovimientoDTO(
                    hora=f"{b_fecha_26} {b_hora} hrs",
                    evento="Pieza entregada en mesón y validada en barrera de salida",
                )
            )

        if orden.estado_orden == "Anulada":
            anul_dt_raw = orden.fecha_actualizacion or orden.fecha_creacion
            anul_dt = (anul_dt_raw.replace(tzinfo=timezone.utc) if anul_dt_raw.tzinfo is None else anul_dt_raw).astimezone(tz_chile)
            anul_fecha_26 = anul_dt.strftime("%d/%m/%y")
            anul_hora = anul_dt.strftime("%H:%M")
            movimientos.append(
                HistorialMovimientoDTO(
                    hora=f"{anul_fecha_26} {anul_hora} hrs",
                    evento="Orden anulada en el sistema",
                )
            )

        item = HistorialOrdenItemResponse(
            id_orden=orden.id_orden,
            folio=folio_doc,
            tipo_operacion="VENTA",
            emite_qr=bool(orden.qr_transaccional_salida),
            fecha_iso=fecha_iso,
            hora=hora_fmt,
            fecha_hora_formateada=fecha_hora_fmt,
            fecha_creacion_formateada=fecha_creacion_formateada,
            cliente_nombre=cliente_nombre,
            cliente_rut=cliente.rut_cliente,
            vendedor_nombre=vendedor_nombre,
            cajera_nombre=cajera_nombre,
            estado_orden=orden.estado_orden,
            modalidad_pago=modalidad,
            metodos_resumen=metodos_resumen,
            total_venta=orden.total_venta,
            descuento=getattr(orden, "descuento", 0) or 0,
            abono_previo=abono_prev,
            total_liquidado=total_liquidado,
            desglose_pagos=desglose_pagos,
            articulos=articulos_dto,
            historial_movimientos=movimientos,
        )

        items_filtrados.append(item)

    # Filtro reactivo de búsqueda multicriterio
    if busqueda and busqueda.strip():

        q_raw = busqueda.strip().lower()
        q = strip_accents(q_raw)
        q_rut = q.replace(".", "").replace("-", "")

        def match_search(it: HistorialOrdenItemResponse) -> bool:
            if q in strip_accents(it.folio):
                return True
            if q in strip_accents(it.cliente_nombre):
                return True
            rut_clean = (it.cliente_rut or "").lower().replace(".", "").replace("-", "")
            if (it.cliente_rut and q in it.cliente_rut.lower()) or (q_rut and q_rut in rut_clean):
                return True
            if q in strip_accents(it.vendedor_nombre) or q in strip_accents(it.cajera_nombre):
                return True
            for art in it.articulos:
                if q in strip_accents(art.descripcion) or (art.sku and q in strip_accents(art.sku)):
                    return True
            return False

        items_filtrados = [it for it in items_filtrados if match_search(it)]

    # Cálculo exacto de resumen_cuadre (excluyendo órdenes en estado 'Anulada')
    tot_recaudado = 0
    tot_ordenes_pag = 0
    tot_efectivo = 0
    tot_debito = 0
    tot_credito = 0
    tot_transferencia = 0
    tot_cheque = 0

    for it in items_filtrados:
        if it.estado_orden == "Anulada":
            continue

        if it.estado_orden in ["Pagada", "Completada", "Despachada"]:
            tot_ordenes_pag += 1

        for p in it.desglose_pagos:
            mp = (p.metodo_pago or "").lower()
            if "efectivo" in mp:
                tot_efectivo += p.monto
            elif "débito" in mp or "debito" in mp:
                tot_debito += p.monto
            elif "crédito" in mp or "credito" in mp:
                tot_credito += p.monto
            elif "transferencia" in mp:
                tot_transferencia += p.monto
            elif "cheque" in mp:
                tot_cheque += p.monto
            else:
                tot_efectivo += p.monto

    tot_pos = tot_debito + tot_credito
    tot_recaudado = tot_efectivo + tot_pos + tot_transferencia + tot_cheque

    resumen = ResumenCuadreCajaDTO(
        total_recaudado=tot_recaudado,
        total_ordenes_pagadas=tot_ordenes_pag,
        total_efectivo=tot_efectivo,
        total_pos=tot_pos,
        total_debito=tot_debito,
        total_credito=tot_credito,
        total_transferencia=tot_transferencia,
        total_cheque=tot_cheque,
    )

    # Ordenar cronológicamente por fecha operativa de caja descendente
    items_filtrados.sort(key=lambda it: it.fecha_iso + " " + it.hora, reverse=True)

    # Paginación
    total_registros = len(items_filtrados)
    total_paginas = max(1, math.ceil(total_registros / limite))
    offset = (pagina - 1) * limite
    paginated_items = items_filtrados[offset: offset + limite]

    return HistorialCajaResponse(
        total_registros=total_registros,
        pagina_actual=pagina,
        limite_por_pagina=limite,
        total_paginas=total_paginas,
        resumen_cuadre=resumen,
        items=paginated_items,
    )
