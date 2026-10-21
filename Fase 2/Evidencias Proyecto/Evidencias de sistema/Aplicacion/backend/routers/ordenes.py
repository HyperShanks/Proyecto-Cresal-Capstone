# Router Transaccional de Órdenes de Venta (HU-3.4)
# Expone el endpoint POST /api/v1/ordenes para consolidar ventas del Carrito Híbrido,
# registrar datos de Micro-CRM, gestionar despacho y asegurar la consistencia ACID del inventario.

import uuid
from collections import defaultdict
from datetime import datetime, time as datetime_time, timezone, timedelta
from zoneinfo import ZoneInfo
from typing import List, Optional, Dict
from fastapi import APIRouter, Depends, HTTPException, Query, status, BackgroundTasks
from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_, and_, not_, func, cast, String, case

from database import get_db
from services.telegram_service import TelegramService
from models import (
    Usuario, Cliente, Region, Comuna, Orden_Venta, Detalle_Orden,
    Despacho, Activo_Inventariado, Estado_Activo,
    Vehiculo_Origen, Categoria_Activo, Transaccion_Pago,
    Tracking_Logistico, Sucursal, Reservas_Backorder,
    Detalle_Motor, Detalle_Caja_Cambio
)
from schemas import (
    OrdenCreateRequest, OrdenResponse,
    ClienteOrdenResumen, DespachoOrdenResumen,
    DetalleOrdenItemResponse, OrdenHistorialItemResponse,
    OrdenAnulacionResponse, AnularOrdenRequest, ReasignarVendedorRequest,
    ReasignarVendedorResponse, InstruccionesUpdateRequest,
    InstruccionesUpdateResponse, OrdenPagoRequest,
    OrdenPagoResponse, EntregaEnvioItemResponse,
    EntregaConfirmacionResponse, DespachoEnvioResponse,
    DespachoActualizarEstadoRequest, DespachoActualizarEstadoResponse,
    VendedorResumenResponse, CheckoutWizardRequest,
    CheckoutWizardResponse, ReservaBackorderDTO, DespachoDTO,
    HistorialCajaResponse, HistorialOrdenItemResponse,
    HistorialPagoDetalleDTO, HistorialArticuloDTO, HistorialMovimientoDTO,
    GeografiaResponseDTO, RegionGeografiaDTO, ComunaItemDTO,
    AsignarActivoBackorderRequest, AsignarActivoBackorderResponse,
    ValidarActivoBackorderResponse, ActivoDetalleBackorderDTO,
    ReservaSolicitadaBackorderDTO,
)
from core.security import get_current_user, require_auditoria_or_caja_role, require_caja_role
from core.policies import validar_horario_operativo_ordenes


router = APIRouter(
    prefix="/api/v1/ordenes",
    tags=["Órdenes de Venta"]
)


@router.get(
    "/comunas",
    response_model=GeografiaResponseDTO,
    summary="Obtener Regiones y Comunas Oficiales desde la BD",
    description="Retorna el listado completo y jerárquico de regiones y comunas cargadas en la Base de Datos para poblar los selectores de despacho y CRM."
)
def obtener_comunas_geografia(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    regiones = db.query(Region).order_by(Region.id_region.asc()).all()
    resultado = []
    for r in regiones:
        comunas_dto = [
            ComunaItemDTO(
                id_comuna=c.id_comuna,
                nombre_comuna=c.nombre_comuna,
                id_region=c.id_region,
            )
            for c in r.comunas
        ]
        comunas_dto.sort(key=lambda x: x.nombre_comuna)
        resultado.append(
            RegionGeografiaDTO(
                id_region=r.id_region,
                nombre_region=r.nombre_region,
                comunas=comunas_dto,
            )
        )
    return GeografiaResponseDTO(regiones=resultado)


@router.post(
    "",
    response_model=OrdenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear Orden de Venta Transaccional (ACID)",
    description="Procesa la orden de venta desde el carrito de compras. "
                "Registra cliente, cabecera de orden, despacho, detalle y "
                "reserva los repuestos inventariados en una transacción atómica."
)
@router.post(
    "/",
    response_model=OrdenResponse,
    status_code=status.HTTP_201_CREATED,
    include_in_schema=False
)
def crear_orden(
    orden_in: OrdenCreateRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Motor Transaccional de Creación de Órdenes:
    1. Validaciones previas de negocio (Consentimiento, ítems, despacho, stock disponible).
    2. Transacción ACID:
       - Paso A.1: Upsert / Registro del Cliente (Micro-CRM).
       - Paso A.2: Inserción de la Cabecera de Orden_Venta (estado='Reservada').
       - Paso A.3: Inserción de Despacho (si requiere_despacho == True).
       - Paso B: Inserción de líneas en Detalle_Orden (con notas de preparación para bodega).
       - Paso C: Actualización atómica de Activo_Inventariado a estado 'Reservado'.
    3. Rollback inmediato ante cualquier fallo.
    """
    # ── 1. Validaciones Previas de Negocio ──────────────────────────────────
    # 1.0 Control RBAC Zero-Trust: Bloqueo de emisión de órdenes para Auditor (Rol 8) y roles no comerciales
    if current_user.id_rol == 8 or current_user.id_rol not in [1, 2, 4, 5, 6, 7]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: El perfil de Auditoría no posee permisos para emitir órdenes de venta."
        )

    # 1.0.1 Validación de Horario Operativo y Periodo de Gracia por Rol
    validar_horario_operativo_ordenes(current_user, orden_in.items, db)

    if not orden_in.consentimiento_legal:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El consentimiento expreso para tratamiento de datos (Ley N° 21.719) es obligatorio."
        )

    if not orden_in.items or len(orden_in.items) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La orden debe contener al menos un ítem o repuesto."
        )

    if orden_in.requiere_despacho and not orden_in.despacho:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Debe proporcionar los datos de despacho si 'requiere_despacho' está activado."
        )

    # Determinar tipo de entrega y sucursales involucradas
    tipo_entrega_final = orden_in.tipo_entrega or "Retiro"
    if orden_in.despacho and orden_in.despacho.tipo_entrega:
        tipo_entrega_final = orden_in.despacho.tipo_entrega

    id_sucursal_orden = orden_in.id_sucursal or getattr(current_user, 'id_sucursal', 1) or 1
    id_sucursal_dest_traslado = orden_in.id_sucursal_destino or (orden_in.despacho.id_sucursal_destino if orden_in.despacho else None) or id_sucursal_orden

    # Validación de sucursales para traslados (1: Viña del Mar, 2: Limache)
    if tipo_entrega_final == "Traslado":
        if id_sucursal_dest_traslado not in [1, 2]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La sucursal de destino no es válida para traslados inter-sucursal (permitidas: 1 Viña del Mar, 2 Limache)."
            )

    # Calcular monto total
    total_calculado = sum(item.precio_final * item.cantidad for item in orden_in.items)
    if total_calculado <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El monto total de la orden debe ser mayor a $0."
        )

    # Validar disponibilidad de repuestos inventariados antes de iniciar escritura
    for item in orden_in.items:
        if item.id_activo:
            activo_db = (
                db.query(Activo_Inventariado, Estado_Activo)
                .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
                .filter(Activo_Inventariado.id_activo == item.id_activo)
                .first()
            )
            if not activo_db:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"El repuesto inventariado con ID '{item.id_activo}' no existe en el sistema."
                )

            activo, estado = activo_db
            if activo.estado != "Activo" or estado.nombre_estado != "Disponible":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"El repuesto '{activo.sku_qr_fisico}' no está disponible para venta. "
                           f"Estado actual: {estado.nombre_estado}."
                )

            # Validar rango de precios permitido por tasación (mínimo y máximo)
            min_permitido = activo.precio_minimo if activo.precio_minimo is not None else activo.precio_referencia
            max_permitido = activo.precio_maximo if activo.precio_maximo is not None else activo.precio_referencia

            if min_permitido is not None and max_permitido is not None:
                if item.precio_final < min_permitido or item.precio_final > max_permitido:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            f"El precio acordado (${item.precio_final}) para el repuesto '{activo.sku_qr_fisico}' "
                            f"está fuera del rango de tasación permitido (${min_permitido} - ${max_permitido})."
                        ),
                    )

            if tipo_entrega_final == "Traslado" and orden_in.id_sucursal_destino and activo.id_sucursal_actual == id_sucursal_dest_traslado:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="La sucursal de origen y destino no pueden ser iguales para un traslado."
                )

    # ── 2. Bloque Transaccional ACID ─────────────────────────────────────────
    try:
        # ── Paso A.1: Gestión de Cliente (Upsert / Find or Create) ───────────
        rut_limpio = orden_in.cliente.rut_cliente.strip()
        rut_normalizado = rut_limpio.replace(".", "").replace("-", "").upper()

        es_consumidor_final = rut_normalizado in ["66666666", "6666666"] or "CONSUMIDOR" in orden_in.cliente.nombres.upper()

        if es_consumidor_final:
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
                db.flush()
        else:
            cliente = db.query(Cliente).filter(
                (Cliente.rut_cliente == rut_limpio) | (Cliente.rut_cliente == rut_limpio.replace(".", ""))
            ).first()

            id_comuna_cliente = None
            if orden_in.cliente.comuna:
                comuna_obj = (
                    db.query(Comuna)
                    .filter(Comuna.nombre_comuna.ilike(orden_in.cliente.comuna.strip()))
                    .first()
                )
                if comuna_obj:
                    id_comuna_cliente = comuna_obj.id_comuna

            if not cliente:
                cliente = Cliente(
                    rut_cliente=rut_limpio,
                    nombres=orden_in.cliente.nombres.strip(),
                    apellidos=orden_in.cliente.apellidos.strip(),
                    telefono=orden_in.cliente.telefono.strip() if orden_in.cliente.telefono else None,
                    correo=orden_in.cliente.correo.strip() if orden_in.cliente.correo else None,
                    id_comuna=id_comuna_cliente,
                    consentimiento_legal=orden_in.consentimiento_legal,
                    estado="Activo",
                )
                db.add(cliente)
                db.flush()
            else:
                # Actualizar datos de contacto más recientes
                cliente.nombres = orden_in.cliente.nombres.strip()
                cliente.apellidos = orden_in.cliente.apellidos.strip()
                if orden_in.cliente.telefono:
                    cliente.telefono = orden_in.cliente.telefono.strip()
                if orden_in.cliente.correo:
                    cliente.correo = orden_in.cliente.correo.strip()
                if id_comuna_cliente:
                    cliente.id_comuna = id_comuna_cliente
                cliente.consentimiento_legal = orden_in.consentimiento_legal
                db.flush()

        # ── Paso A.2: Cabecera Orden_Venta ──────────────────────────────────
        # Tarea 2: Toda orden creada en Mesón nace en 'Reservada' con qr_transaccional_salida = NULL.
        # El acuerdo de abono comercial solo se registra como propuesta en abono_requerido sin restar del saldo pendiente (que sigue siendo el total) ni generar registros en Transaccion_Pago.
        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

        monto_abono_val = orden_in.monto_abono if (orden_in.monto_abono is not None and orden_in.monto_abono > 0) else 0
        desc_val = max(0, getattr(orden_in, "descuento", 0) or 0)
        total_con_descuento = max(0, total_calculado - desc_val)
        if monto_abono_val > total_con_descuento:
            monto_abono_val = total_con_descuento

        vendedor_comercial = current_user.id_usuario
        if getattr(orden_in, "id_vendedor_titular", None) is not None:
            if current_user.id_rol not in [1, 2, 5, 6]:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Acceso restringido: Solo el Jefe de Ventas, Vendedor o Administrador puede emitir órdenes a nombre de otro vendedor."
                )
            v_titular = db.query(Usuario).filter(Usuario.id_usuario == orden_in.id_vendedor_titular, Usuario.estado == "Activo").first()
            if not v_titular:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="El vendedor titular seleccionado no existe o no está activo."
                )
            vendedor_comercial = v_titular.id_usuario

        vendedor_asignado_final = orden_in.id_vendedor_asignado
        if orden_in.id_vendedor_titular is not None and vendedor_asignado_final is None:
            vendedor_asignado_final = current_user.id_usuario

        nueva_orden = Orden_Venta(
            id_cliente=cliente.id_cliente,
            id_vendedor=vendedor_comercial,
            id_vendedor_asignado=vendedor_asignado_final,
            id_sucursal=id_sucursal_orden,
            estado_orden="Reservada",
            qr_transaccional_salida=None,
            total_venta=total_con_descuento,
            descuento=desc_val,
            monto_pendiente=total_con_descuento,
            abono_requerido=monto_abono_val,
            fecha_creacion=now_utc,
            fecha_actualizacion=now_utc,
        )
        db.add(nueva_orden)
        db.flush()

        # ── Paso A.3: Despacho (Exclusivo para envíos a clientes a domicilio/taller) ──
        if orden_in.requiere_despacho and orden_in.despacho:
            desp_obj = orden_in.despacho
            dir_envio = desp_obj.direccion_envio.strip()
            rec_nombres = desp_obj.receptor_nombres.strip() if desp_obj.receptor_nombres else f"{cliente.nombres} {cliente.apellidos}".strip()
            rec_rut = desp_obj.receptor_rut.strip() if desp_obj.receptor_rut else cliente.rut_cliente
            rec_tel = desp_obj.receptor_telefono.strip() if desp_obj.receptor_telefono else (cliente.telefono or "S/T")

            id_comuna_dest = desp_obj.id_comuna_destino
            if not id_comuna_dest and desp_obj.comuna_destino:
                comuna_dest_obj = (
                    db.query(Comuna)
                    .filter(Comuna.nombre_comuna.ilike(desp_obj.comuna_destino.strip()))
                    .first()
                )
                if comuna_dest_obj:
                    id_comuna_dest = comuna_dest_obj.id_comuna

            if not id_comuna_dest:
                comuna_fallback = db.query(Comuna).first()
                id_comuna_dest = comuna_fallback.id_comuna if comuna_fallback else 1

            despacho = Despacho(
                id_orden=nueva_orden.id_orden,
                id_comuna_destino=id_comuna_dest,
                direccion_envio=dir_envio,
                receptor_nombres=rec_nombres,
                receptor_rut=rec_rut,
                receptor_telefono=rec_tel,
                empresa_transporte=desp_obj.empresa_transporte,
                costo_envio=desp_obj.costo_envio or 0,
                estado_despacho="Por Enviar",
                estado="Activo"
            )
            db.add(despacho)
            db.flush()

        # ── Paso B: Líneas en Detalle_Orden & Paso C: Update Activos ─────────
        estado_reservado = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Reservado").first()
        if not estado_reservado:
            estado_reservado = Estado_Activo(id_estado=2, nombre_estado="Reservado")
            db.add(estado_reservado)
            db.flush()

        for item in orden_in.items:
            activo = None

            # Si es inventariado, verificar si requiere traslado entre sucursales
            if item.id_activo:
                nota_final = item.notas_preparacion or orden_in.instrucciones_bodega
                estado_prep = "Pendiente"
                activo = (
                    db.query(Activo_Inventariado)
                    .filter(Activo_Inventariado.id_activo == item.id_activo)
                    .first()
                )
                if activo:
                    # Regla Traslado: Activo ubicado en Limache (2) vendido en Viña (1), o tipo_entrega='Traslado'
                    if (activo.id_sucursal_actual == 2 and id_sucursal_orden == 1) or tipo_entrega_final == "Traslado" or (activo.id_sucursal_actual != id_sucursal_orden):
                        dest_suc = (
                            id_sucursal_dest_traslado
                            if id_sucursal_dest_traslado != activo.id_sucursal_actual
                            else (1 if activo.id_sucursal_actual == 2 else 2)
                        )
                        tracking = Tracking_Logistico(
                            id_activo=activo.id_activo,
                            id_sucursal_origen=activo.id_sucursal_actual,
                            id_sucursal_destino=dest_suc,
                            id_usuario_gestor=current_user.id_usuario,
                            id_orden=nueva_orden.id_orden,
                            estado_traslado="Pendiente",
                        )
                        db.add(tracking)

                        nombre_origen = "Limache" if activo.id_sucursal_actual == 2 else "Viña del Mar"
                        nombre_dest = "Viña del Mar" if dest_suc == 1 else "Limache"
                        prefijo = f"[TRASLADO DESDE {nombre_origen.upper()} A {nombre_dest.upper()}] "
                        if nota_final:
                            if prefijo not in nota_final:
                                nota_final = f"{prefijo}{nota_final}"
                        else:
                            nota_final = f"{prefijo}Preparar repuesto para traslado inter-sucursal."
            else:
                # Ítems misceláneos / venta libre: no heredan instrucciones de bodega de los activos ni van a tareas de bodega
                nota_final = None
                estado_prep = "Listo"

            detalle = Detalle_Orden(
                id_orden=nueva_orden.id_orden,
                id_activo=item.id_activo,
                descripcion_manual=item.descripcion_manual,
                notas_preparacion=nota_final,
                cantidad=item.cantidad,
                precio_unitario=item.precio_unitario or item.precio_final,
                precio_final=item.precio_final,
                estado_preparacion=estado_prep,
            )
            db.add(detalle)

            # Paso C: Bloquear y actualizar estado de repuesto inventariado
            if item.id_activo and activo:
                activo.id_estado = estado_reservado.id_estado
                activo.reserva_expira_en = None
                activo.reservado_por = None
                activo.version_lock = (activo.version_lock or 1) + 1

        # ── 3. Commit Transaccional Atómico ─────────────────────────────────
        db.commit()
        db.refresh(nueva_orden)

        return OrdenResponse(
            id_orden=nueva_orden.id_orden,
            numero_orden=nueva_orden.numero_orden,
            folio=nueva_orden.folio,
            estado_orden=nueva_orden.estado_orden,
            total_venta=nueva_orden.total_venta,
            descuento=nueva_orden.descuento,
            monto_pendiente=nueva_orden.monto_pendiente,
            abono_requerido=nueva_orden.abono_requerido,
            qr_transaccional_salida=nueva_orden.qr_transaccional_salida,
            mensaje="Orden de venta generada exitosamente y derivada a caja.",
            fecha_creacion=nueva_orden.fecha_creacion.isoformat() if nueva_orden.fecha_creacion else None,
            total_items=len(orden_in.items),
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en la transacción de creación de la orden: {str(e)}"
        )


tz_chile_ordenes = ZoneInfo("America/Santiago")


def parse_periodo_ordenes_chile(
    periodo: Optional[str] = "TODOS",
    fecha_desde: Optional[str] = None,
    fecha_hasta: Optional[str] = None,
) -> tuple[Optional[datetime], Optional[datetime]]:
    """
    Calculo los rangos de fecha en horario chileno y los convierto a UTC
    para filtrar órdenes de manera consistente en base de datos.
    """
    p = (periodo or "TODOS").strip().upper()
    ahora_chile = datetime.now(tz_chile_ordenes)

    if p == "HOY":
        start_local = datetime.combine(ahora_chile.date(), datetime_time.min, tzinfo=tz_chile_ordenes)
        end_local = datetime.combine(ahora_chile.date(), datetime_time.max, tzinfo=tz_chile_ordenes)
    elif p in ["7D", "ESTA_SEMANA"]:
        lunes = ahora_chile.date() - timedelta(days=ahora_chile.weekday())
        start_local = datetime.combine(lunes, datetime_time.min, tzinfo=tz_chile_ordenes)
        end_local = datetime.combine(ahora_chile.date(), datetime_time.max, tzinfo=tz_chile_ordenes)
    elif p in ["30D", "ESTE_MES"]:
        primer_dia = ahora_chile.date().replace(day=1)
        start_local = datetime.combine(primer_dia, datetime_time.min, tzinfo=tz_chile_ordenes)
        end_local = datetime.combine(ahora_chile.date(), datetime_time.max, tzinfo=tz_chile_ordenes)
    elif p == "RANGO" or (fecha_desde and fecha_hasta):
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
        start_local = datetime.combine(d_desde, datetime_time.min, tzinfo=tz_chile_ordenes)
        end_local = datetime.combine(d_hasta, datetime_time.max, tzinfo=tz_chile_ordenes)
    elif p == "TODOS":
        return None, None
    else:
        return None, None

    start_utc = start_local.astimezone(timezone.utc).replace(tzinfo=None)
    end_utc = end_local.astimezone(timezone.utc).replace(tzinfo=None)
    return start_utc, end_utc


@router.get(
    "",
    response_model=HistorialCajaResponse,
    summary="Visor Histórico Centralizado de Órdenes y Auditoría (HU-5.2)",
    description="Consulta el historial multidimensional de órdenes de venta para auditoría gerencial y de caja. "
                "Permite filtrar por sucursal, estado, rango temporal, método de pago y búsqueda predictiva tolerante."
)
@router.get(
    "/",
    response_model=HistorialCajaResponse,
    include_in_schema=False
)
def listar_ordenes_auditoria(
    id_sucursal: Optional[int] = Query(None, description="ID de la sucursal (None para consolidado)"),
    sucursal_id: Optional[int] = Query(None, description="Alias para id_sucursal"),
    estado: Optional[str] = Query(None, description="Filtro por estado de orden"),
    estado_orden: Optional[str] = Query(None, description="Alias para estado"),
    periodo: Optional[str] = Query("TODOS", description="Atajo de período: HOY, 7D, ESTA_SEMANA, 30D, ESTE_MES, RANGO, TODOS"),
    fecha_inicio: Optional[str] = Query(None, description="Fecha inicio YYYY-MM-DD"),
    fecha_fin: Optional[str] = Query(None, description="Fecha término YYYY-MM-DD"),
    fecha_desde: Optional[str] = Query(None, description="Alias para fecha_inicio"),
    fecha_hasta: Optional[str] = Query(None, description="Alias para fecha_fin"),
    metodo_pago: Optional[str] = Query(None, description="Filtro por método de pago"),
    tipo_activo: Optional[str] = Query(None, description="Filtro por tipo de activo: 'TODOS', 'MOTORES_CAJAS'"),
    tipo: Optional[str] = Query(None, description="Alias para tipo_activo"),
    search: Optional[str] = Query(None, description="Búsqueda predictiva (Folio, RUT, Cliente, Vendedor)"),
    busqueda: Optional[str] = Query(None, description="Alias para search"),
    pagina: int = Query(1, ge=1, description="Número de página"),
    limite: int = Query(20, ge=1, le=100, description="Registros por página"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_auditoria_or_caja_role),
):
    """
    Endpoint centralizado para auditoría de órdenes de venta (HU-5.2).
    Permito a Gerentes (4), Administradores (5) y Cajeros (3) auditar órdenes
    aplicando filtros combinados con optimización de consultas.
    """
    UsuarioVendedor = aliased(Usuario, name="vendedor_auditoria")
    UsuarioCajera = aliased(Usuario, name="cajera_auditoria")

    query = (
        db.query(Orden_Venta, Cliente, UsuarioVendedor, UsuarioCajera, Sucursal)
        .join(Cliente, Orden_Venta.id_cliente == Cliente.id_cliente)
        .join(UsuarioVendedor, Orden_Venta.id_vendedor == UsuarioVendedor.id_usuario)
        .outerjoin(UsuarioCajera, Orden_Venta.id_cajera == UsuarioCajera.id_usuario)
        .outerjoin(Sucursal, Orden_Venta.id_sucursal == Sucursal.id_sucursal)
    )

    # 1. Filtro por Sucursal (None = consolidado global)
    target_sucursal = id_sucursal or sucursal_id
    if target_sucursal is not None:
        query = query.filter(Orden_Venta.id_sucursal == target_sucursal)

    # 2. Filtro por Estado Oficial
    est_target = estado or estado_orden
    if est_target and est_target.strip().lower() not in ["todos", ""]:
        query = query.filter(Orden_Venta.estado_orden.ilike(est_target.strip()))

    # 3. Filtro Temporal (Zona Horaria Chile -> UTC)
    f_ini = fecha_inicio or fecha_desde
    f_fin = fecha_fin or fecha_hasta
    start_utc, end_utc = parse_periodo_ordenes_chile(periodo, f_ini, f_fin)
    if start_utc is not None and end_utc is not None:
        query = query.filter(Orden_Venta.fecha_creacion.between(start_utc, end_utc))

    # 4. Filtro por Método de Pago
    if metodo_pago and metodo_pago.strip().lower() not in ["todos", ""]:
        metodo_clean = metodo_pago.strip()
        subq_pagos = (
            db.query(Transaccion_Pago.id_orden)
            .filter(
                Transaccion_Pago.metodo_pago.ilike(f"%{metodo_clean}%"),
                Transaccion_Pago.estado_pago == "Procesado"
            )
        )
        query = query.filter(Orden_Venta.id_orden.in_(subq_pagos))

    # 5. Filtro por Motores y Cajas (únicos activos inventariados en Cresal)
    target_tipo = tipo_activo or tipo
    if target_tipo and target_tipo.strip().upper() not in ["TODOS", ""]:
        tipo_act_clean = target_tipo.strip().upper()
        if tipo_act_clean in ["MOTORES_CAJAS", "MOTOR_CAJA", "MOTORES", "CAJAS", "INVENTARIADO", "INVENTARIADOS"]:
            # Filtro semántico estricto para evitar falsos positivos
            desc_lower = func.lower(Detalle_Orden.descripcion_manual)

            # Exclusiones estrictas para Motores (accesorios y periféricos secundarios)
            exclusiones_motor_sql = and_(
                not_(desc_lower.like("%cremallera%")),
                not_(desc_lower.like("%partida%")),
                not_(desc_lower.like("%arranque%")),
                not_(desc_lower.like("%limpiaparabris%")),
                not_(desc_lower.like("%limpia parabris%")),
                not_(desc_lower.like("%limpiavidrio%")),
                not_(desc_lower.like("%limpia vidrio%")),
                not_(desc_lower.like("%alzavidrio%")),
                not_(desc_lower.like("%alza vidrio%")),
                not_(desc_lower.like("%calefacci%")),
                not_(desc_lower.like("%ventilador%")),
                not_(desc_lower.like("%electroventilador%")),
                not_(desc_lower.like("%soplador%")),
                not_(desc_lower.like("%blower%")),
                not_(desc_lower.like("%espejo%")),
                not_(desc_lower.like("%antena%")),
                not_(desc_lower.like("%bomba%")),
                not_(desc_lower.like("%paso a paso%")),
                not_(desc_lower.like("%ralent%")),
                not_(desc_lower.like("%sunroof%")),
                not_(desc_lower.like("%techo%")),
                not_(desc_lower.like("%actuador%")),
                not_(desc_lower.like("%regulador%")),
            )

            # Exclusiones estrictas para Cajas (elementos auxiliares ajenos a la transmisión)
            exclusiones_caja_sql = and_(
                not_(desc_lower.like("%fusible%")),
                not_(desc_lower.like("%fusilera%")),
                not_(desc_lower.like("%direcci%")),
                not_(desc_lower.like("%filtro%")),
                not_(desc_lower.like("%evaporador%")),
                not_(desc_lower.like("%bateria%")),
                not_(desc_lower.like("%batería%")),
                not_(desc_lower.like("%rele%")),
                not_(desc_lower.like("%relé%")),
                not_(desc_lower.like("%mariposa%")),
                not_(desc_lower.like("%termostato%")),
                not_(desc_lower.like("%herramienta%")),
            )

            # Condiciones positivas
            cond_motor_miscelaneo = and_(
                or_(desc_lower.like("%motor%"), desc_lower.like("%block%")),
                exclusiones_motor_sql,
            )

            cond_caja_miscelaneo = and_(
                or_(
                    desc_lower.like("%caja de cambio%"),
                    desc_lower.like("%caja cambio%"),
                    desc_lower.like("%caja manual%"),
                    desc_lower.like("%caja mecanica%"),
                    desc_lower.like("%caja mecánica%"),
                    desc_lower.like("%caja automatica%"),
                    desc_lower.like("%caja automática%"),
                    desc_lower.like("%caja cvt%"),
                    desc_lower.like("%caja secuencial%"),
                    desc_lower.like("%transmisi%"),
                    and_(desc_lower.like("%caja%"), exclusiones_caja_sql),
                ),
                exclusiones_caja_sql,
            )

            cond_verde_backorder = and_(
                or_(desc_lower.like("%verde%"), desc_lower.like("%backorder%")),
                exclusiones_motor_sql,
                exclusiones_caja_sql,
            )

            cond_activo_inventariado = or_(
                Activo_Inventariado.id_categoria.in_([1, 2]),
                func.lower(Categoria_Activo.nombre_categoria).like("%motor%"),
                func.lower(Categoria_Activo.nombre_categoria).like("%caja%"),
                func.lower(Categoria_Activo.nombre_categoria).like("%transmisi%"),
                func.lower(Activo_Inventariado.sku_qr_fisico).like("mot%"),
                func.lower(Activo_Inventariado.sku_qr_fisico).like("caj%"),
            )

            subq_motores_cajas = (
                db.query(Detalle_Orden.id_orden)
                .outerjoin(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
                .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
                .filter(
                    or_(
                        cond_activo_inventariado,
                        cond_motor_miscelaneo,
                        cond_caja_miscelaneo,
                        cond_verde_backorder,
                    )
                )
            )
            query = query.filter(Orden_Venta.id_orden.in_(subq_motores_cajas))

    # 6. Búsqueda Predictiva y Tolerante
    term = (search or busqueda or "").strip()
    if term:
        term_clean_rut = term.replace(".", "").replace("-", "").strip()
        rut_db_limpio = func.replace(
            func.replace(Cliente.rut_cliente, ".", ""), "-", ""
        )
        query = query.filter(
            or_(
                cast(Orden_Venta.numero_orden, String).ilike(f"%{term.upper().replace('ORD-', '').lstrip('0')}%") if term.upper().replace('ORD-', '').lstrip('0').isdigit() else cast(Orden_Venta.numero_orden, String).ilike(f"%{term}%"),
                Orden_Venta.qr_transaccional_salida.ilike(f"%{term}%"),
                cast(Orden_Venta.id_orden, String).ilike(f"%{term}%"),
                Cliente.nombres.ilike(f"%{term}%"),
                Cliente.apellidos.ilike(f"%{term}%"),
                Cliente.rut_cliente.ilike(f"%{term}%"),
                rut_db_limpio.ilike(f"%{term_clean_rut}%"),
                UsuarioVendedor.nombres.ilike(f"%{term}%"),
                UsuarioVendedor.apellidos.ilike(f"%{term}%"),
            )
        )

    total_registros = query.count()
    total_paginas = max(1, (total_registros + limite - 1) // limite)

    # Cálculo consolidado del monto efectivamente recaudado/abonado en la consulta (sin ORDER BY para evitar GroupingError en PostgreSQL)
    # - Si la orden está 'Anulada': $0 recaudado.
    # - Para órdenes con abono (ej. Reservada) o pagadas: suma lo efectivamente abonado/pagado: (total_venta - monto_pendiente)
    monto_recaudado_expr = case(
        (Orden_Venta.estado_orden.ilike("Anulada"), 0),
        (
            Orden_Venta.total_venta > func.coalesce(Orden_Venta.monto_pendiente, 0),
            Orden_Venta.total_venta - func.coalesce(Orden_Venta.monto_pendiente, 0),
        ),
        else_=0,
    )
    total_monto_consolidado = (
        query.order_by(None)
        .with_entities(func.coalesce(func.sum(monto_recaudado_expr), 0))
        .scalar()
        or 0
    )

    # Paginación con orden cronológico descendente
    resultados_paginados = (
        query.order_by(Orden_Venta.fecha_creacion.desc())
        .offset((pagina - 1) * limite)
        .limit(limite)
        .all()
    )

    # Optimización de Rendimiento (Resolución de problema N+1):
    # Pre-cargamos en lote los pagos y artículos de todas las órdenes de la página
    # mediante 2 consultas IN(orden_ids), evitando 40 viajes individuales de red a Supabase.
    orden_ids = [orden.id_orden for orden, *_ in resultados_paginados]
    pagos_por_orden: Dict[int, List[Transaccion_Pago]] = defaultdict(list)
    articulos_por_orden: Dict[int, List[HistorialArticuloDTO]] = defaultdict(list)

    # Resolución de cajera activa por sucursal para órdenes históricas que requieran fallback
    cajeras_db = db.query(Usuario).filter(Usuario.id_rol == 3, Usuario.estado == "Activo").all()
    cajeras_activas_por_sucursal = {u.id_sucursal: f"{u.nombres} {u.apellidos or ''}".strip() for u in cajeras_db}
    cajera_general = next(iter(cajeras_activas_por_sucursal.values()), None) or "Caja"

    if orden_ids:
        todos_pagos = (
            db.query(Transaccion_Pago)
            .filter(Transaccion_Pago.id_orden.in_(orden_ids))
            .order_by(Transaccion_Pago.fecha_pago.asc())
            .all()
        )
        for p in todos_pagos:
            pagos_por_orden[p.id_orden].append(p)

        todos_detalles = (
            db.query(Detalle_Orden, Activo_Inventariado, Vehiculo_Origen, Categoria_Activo, Detalle_Motor, Detalle_Caja_Cambio)
            .outerjoin(Activo_Inventariado, Detalle_Orden.id_activo == Activo_Inventariado.id_activo)
            .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
            .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
            .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
            .filter(Detalle_Orden.id_orden.in_(orden_ids))
            .all()
        )
        for det, act, veh, cat, d_mot, d_caj in todos_detalles:
            sku_val = act.sku_qr_fisico if act else None
            detalle_tec = None
            if d_mot:
                partes_tec = [p for p in [d_mot.cilindrada, d_mot.combustible, d_mot.transmision_tipo] if p]
                detalle_tec = " ".join(partes_tec) if partes_tec else None
            elif d_caj and d_caj.transmision_tipo:
                detalle_tec = d_caj.transmision_tipo
            elif veh and veh.traccion:
                detalle_tec = veh.traccion

            if det.descripcion_manual:
                desc = det.descripcion_manual
            elif act:
                cat_str = cat.nombre_categoria if cat else "Repuesto"
                veh_str = f"{veh.marca} {veh.modelo}" if veh else ""
                desc = f"{cat_str} {veh_str}".strip() or "Repuesto Inventariado"
            else:
                desc = "Repuesto"
            articulos_por_orden[det.id_orden].append(
                HistorialArticuloDTO(
                    cantidad=det.cantidad or 1,
                    tipo="INVENTARIADO" if act else "DESARME",
                    descripcion=desc,
                    sku=sku_val,
                    precio=det.precio_unitario or 0,
                    subtotal=det.precio_final or ((det.precio_unitario or 0) * (det.cantidad or 1)),
                    categoria=cat.nombre_categoria if cat else None,
                    marca=veh.marca if veh else None,
                    modelo=veh.modelo if veh else None,
                    anio=veh.anio if veh else None,
                    detalle_tecnico=detalle_tec,
                )
            )

    items: List[HistorialOrdenItemResponse] = []
    for orden, cliente, vendedor, cajera, sucursal in resultados_paginados:
        # Fechas en formato chileno
        if orden.fecha_creacion:
            dt_utc = orden.fecha_creacion.replace(tzinfo=timezone.utc)
            dt_chile = dt_utc.astimezone(tz_chile_ordenes)
        else:
            dt_chile = datetime.now(tz_chile_ordenes)

        fecha_iso = dt_chile.strftime("%Y-%m-%d")
        hora = dt_chile.strftime("%H:%M")
        fecha_creacion_fmt_26 = dt_chile.strftime("%d/%m/%y")
        fecha_hora_formateada = dt_chile.strftime("%H:%M - %d/%m/%Y")
        fecha_creacion_formateada = f"{fecha_creacion_fmt_26} a las {hora} hrs"

        # Pagos asociados recuperados desde memoria (O(1))
        pagos_db = pagos_por_orden.get(orden.id_orden, [])
        desglose_pagos = [
            HistorialPagoDetalleDTO(
                id_transaccion=p.id_pago,
                metodo_pago=p.metodo_pago,
                monto=p.monto,
                fecha_pago=p.fecha_pago,
            )
            for p in pagos_db
        ]

        if desglose_pagos:
            metodos_resumen = " + ".join(
                f"{p.metodo_pago}: ${p.monto:,.0f}".replace(",", ".")
                for p in desglose_pagos
            )
        else:
            metodos_resumen = "Sin pagos"

        # Artículos recuperados desde memoria (O(1))
        articulos_dto = articulos_por_orden.get(orden.id_orden, [])

        # Timeline de movimientos (con año en 2 dígitos 26)
        vendedor_nom = f"{vendedor.nombres} {vendedor.apellidos or ''}".strip()
        if cajera:
            cajera_nom = f"{cajera.nombres} {cajera.apellidos or ''}".strip()
        elif orden.estado_orden and orden.estado_orden.lower() == "anulada":
            cajera_nom = "Sin cobro"
        elif pagos_db or (orden.estado_orden and orden.estado_orden.lower() in ["completada", "pagada", "entregada"]):
            cajera_nom = cajeras_activas_por_sucursal.get(orden.id_sucursal, cajera_general)
        else:
            cajera_nom = "Pendiente de cobro"

        movimientos = [
            HistorialMovimientoDTO(
                hora=f"{fecha_creacion_fmt_26} {hora} hrs",
                evento=f"Orden emitida en Mesón por {vendedor_nom}",
            )
        ]
        for p in pagos_db:
            if p.fecha_pago:
                p_dt = p.fecha_pago if p.fecha_pago.tzinfo else p.fecha_pago.replace(tzinfo=timezone.utc)
                p_dt_chile = p_dt.astimezone(tz_chile_ordenes)
                p_hora_str = f"{p_dt_chile.strftime('%d/%m/%y')} {p_dt_chile.strftime('%H:%M')} hrs"
            else:
                p_hora_str = f"{fecha_creacion_fmt_26} {hora} hrs"
            movimientos.append(
                HistorialMovimientoDTO(
                    hora=p_hora_str,
                    evento=f"Pago liquidado en ventanilla ({p.metodo_pago}: ${p.monto:,.0f})".replace(",", "."),
                )
            )
        if orden.qr_transaccional_salida:
            movimientos.append(
                HistorialMovimientoDTO(
                    hora=f"{fecha_creacion_fmt_26} {hora} hrs",
                    evento="QR Transaccional generado para barrera de salida",
                )
            )

        # Asegurar formato comercial ORD-XXXX si el folio viniera como TX-QR-... o nulo
        folio_display = orden.folio
        if not folio_display or folio_display.startswith("TX-QR-"):
            if orden.numero_orden:
                folio_display = f"ORD-{orden.numero_orden:04d}"
            elif orden.id_orden:
                folio_display = f"ORD-{str(orden.id_orden).replace('-', '')[:8].upper()}"
            else:
                folio_display = "ORD-0000"

        items.append(
            HistorialOrdenItemResponse(
                id_orden=orden.id_orden,
                folio=folio_display,
                tipo_operacion="VENTA",
                emite_qr=bool(orden.qr_transaccional_salida) or (orden.monto_pendiente <= 0),
                fecha_iso=fecha_iso,
                hora=hora,
                fecha_hora_formateada=fecha_hora_formateada,
                fecha_creacion_formateada=fecha_creacion_formateada,
                cliente_nombre=f"{cliente.nombres} {cliente.apellidos or ''}".strip(),
                cliente_rut=cliente.rut_cliente,
                vendedor_nombre=vendedor_nom,
                cajera_nombre=cajera_nom,
                sucursal_nombre=sucursal.nombre_sucursal if sucursal else f"Sucursal {orden.id_sucursal}",
                id_sucursal=orden.id_sucursal,
                estado_orden=orden.estado_orden,
                modalidad_pago="split" if len(pagos_db) > 1 else "unico",
                metodos_resumen=metodos_resumen,
                total_venta=orden.total_venta,
                descuento=getattr(orden, "descuento", 0) or 0,
                abono_previo=0,
                monto_pendiente=orden.monto_pendiente or 0,
                total_liquidado=sum(p.monto for p in pagos_db),
                desglose_pagos=desglose_pagos,
                articulos=articulos_dto,
                historial_movimientos=movimientos,
            )
        )

    return HistorialCajaResponse(
        total_registros=total_registros,
        pagina_actual=pagina,
        limite_por_pagina=limite,
        total_paginas=total_paginas,
        total_monto_consolidado=total_monto_consolidado,
        items=items,
    )


@router.get(
    "/mis-ventas",
    response_model=List[OrdenHistorialItemResponse],
    summary="Historial y Monitoreo de Ventas del Vendedor (HU-3.5)",
    description="Consulta las órdenes generadas por el usuario actual. "
                "Por defecto filtra solo las ventas de la fecha actual (hoy). "
                "Permite segmentar por sección: 'normal' u 'por_asignar'. "
                "Incluye estado de la orden, datos del cliente, despacho y desglose de líneas."
)
def obtener_mis_ventas(
    fecha: Optional[str] = None,
    todas: bool = False,
    estado: Optional[str] = None,
    incluir_anuladas: bool = Query(True, description="Si es False y estado no es 'Anulada', oculta órdenes anuladas"),
    seccion: Optional[str] = Query("normal", description="Sección: 'normal' u 'por_asignar'"),
    limit: Optional[int] = Query(None, description="Límite de elementos por página"),
    offset: int = Query(0, ge=0, description="Desplazamiento para paginación"),
    mes: Optional[int] = Query(None, ge=1, le=12, description="Filtro por mes específico (1 a 12)"),
    anio: Optional[int] = Query(None, description="Filtro por año específico (ej. 2026)"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    subquery_por_asignar = (
        db.query(Reservas_Backorder.id_orden)
        .filter(
            Reservas_Backorder.id_orden.isnot(None),
            Reservas_Backorder.id_activo_asignado.is_(None),
            func.lower(Reservas_Backorder.estado_reserva) != "anulada",
            func.lower(Reservas_Backorder.estado_reserva) != "cancelada",
        )
    )

    # Identificar el ID del usuario comercial Limache para la regla de persistencia de órdenes referidas (Tarea 24)
    usuario_limache = db.query(Usuario).filter(
        Usuario.estado == "Activo",
        or_(
            func.lower(Usuario.email) == "limache@cresal.cl",
            func.lower(Usuario.apellidos).like("%limache%"),
        )
    ).first()
    id_limache = usuario_limache.id_usuario if usuario_limache else None

    # Regla de Visibilidad en Mis Órdenes:
    # 1. Órdenes propias donde current_user es el titular comercial.
    # 2. Excepción Exclusiva Limache: Órdenes asignadas comercialmente a Limache pero emitidas operativamente por current_user.
    if id_limache:
        filtro_vendedor = or_(
            Orden_Venta.id_vendedor == current_user.id_usuario,
            and_(
                Orden_Venta.id_vendedor == id_limache,
                Orden_Venta.id_vendedor_asignado == current_user.id_usuario,
            ),
        )
    else:
        filtro_vendedor = (Orden_Venta.id_vendedor == current_user.id_usuario)

    if seccion == "por_asignar":
        # Apartado exclusivo: Ventas en verde pagadas que están pendientes de asignación física de activo
        query = db.query(Orden_Venta).filter(
            filtro_vendedor,
            Orden_Venta.monto_pendiente == 0,
            Orden_Venta.qr_transaccional_salida.is_(None),
            Orden_Venta.id_orden.in_(subquery_por_asignar),
            func.lower(Orden_Venta.estado_orden).notin_(["anulada", "cancelada"])
        )
        if fecha and fecha.strip():
            try:
                tz_chile = ZoneInfo("America/Santiago")
            except Exception:
                tz_chile = timezone(timedelta(hours=-4))
            try:
                target_date = datetime.strptime(fecha.strip(), "%Y-%m-%d").date()
                dt_start_chile = datetime.combine(target_date, datetime_time.min, tzinfo=tz_chile)
                dt_end_chile = datetime.combine(target_date, datetime_time.max, tzinfo=tz_chile)
                inicio_utc = dt_start_chile.astimezone(timezone.utc).replace(tzinfo=None)
                fin_utc = dt_end_chile.astimezone(timezone.utc).replace(tzinfo=None)
                query = query.filter(
                    Orden_Venta.fecha_creacion >= inicio_utc,
                    Orden_Venta.fecha_creacion <= fin_utc
                )
            except ValueError:
                pass
    else:
        # Apartado normal: Excluir estrictamente órdenes pendientes de asignación para evitar duplicidad o botones Ver QR inválidos
        query = db.query(Orden_Venta).filter(
            filtro_vendedor,
            ~and_(
                Orden_Venta.monto_pendiente == 0,
                Orden_Venta.qr_transaccional_salida.is_(None),
                Orden_Venta.id_orden.in_(subquery_por_asignar)
            )
        )

        # Filtro de Rendimiento: Por defecto solo órdenes de hoy, salvo que se pida historial completo o mes/año específico
        if not todas and mes is None and anio is None:
            try:
                tz_chile = ZoneInfo("America/Santiago")
            except Exception:
                tz_chile = timezone(timedelta(hours=-4))

            if fecha and fecha.strip():
                try:
                    target_date = datetime.strptime(fecha.strip(), "%Y-%m-%d").date()
                    dt_start_chile = datetime.combine(target_date, datetime_time.min, tzinfo=tz_chile)
                    dt_end_chile = datetime.combine(target_date, datetime_time.max, tzinfo=tz_chile)
                    inicio_utc = dt_start_chile.astimezone(timezone.utc).replace(tzinfo=None)
                    fin_utc = dt_end_chile.astimezone(timezone.utc).replace(tzinfo=None)
                except ValueError:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Formato de fecha no válido. Use 'YYYY-MM-DD'."
                    )
            else:
                ahora_chile = datetime.now(tz_chile)
                inicio_dia_chile = datetime.combine(ahora_chile.date(), datetime_time.min, tzinfo=tz_chile)
                fin_dia_chile = datetime.combine(ahora_chile.date(), datetime_time.max, tzinfo=tz_chile)
                inicio_utc = inicio_dia_chile.astimezone(timezone.utc).replace(tzinfo=None)
                fin_utc = fin_dia_chile.astimezone(timezone.utc).replace(tzinfo=None)

            query = query.filter(
                Orden_Venta.fecha_creacion >= inicio_utc,
                Orden_Venta.fecha_creacion <= fin_utc
            )

        if estado and estado.strip():
            query = query.filter(Orden_Venta.estado_orden == estado.strip())
        elif not incluir_anuladas:
            query = query.filter(func.lower(Orden_Venta.estado_orden) != "anulada")

    # Filtros separados de Mes y Año
    if anio is not None:
        query = query.filter(func.extract("year", Orden_Venta.fecha_creacion) == anio)
    if mes is not None:
        query = query.filter(func.extract("month", Orden_Venta.fecha_creacion) == mes)

    query_ordered = query.order_by(
        case(
            (func.lower(Orden_Venta.estado_orden) == "anulada", 2),
            (func.lower(Orden_Venta.estado_orden) == "completada", 1),
            (func.lower(Orden_Venta.estado_orden) == "entregada", 1),
            else_=0,
        ),
        Orden_Venta.fecha_creacion.desc(),
    )

    if offset > 0:
        query_ordered = query_ordered.offset(offset)
    if limit is not None and limit > 0:
        query_ordered = query_ordered.limit(limit)

    ordenes = query_ordered.all()

    if not ordenes:
        return []

    orden_ids = [orden.id_orden for orden in ordenes]
    cliente_ids = list({orden.id_cliente for orden in ordenes if orden.id_cliente})

    # Carga por lotes para eliminar el cuello de botella N+1
    clientes_map: Dict[uuid.UUID, Cliente] = {}
    if cliente_ids:
        clientes = db.query(Cliente).filter(Cliente.id_cliente.in_(cliente_ids)).all()
        clientes_map = {c.id_cliente: c for c in clientes}

    despachos = db.query(Despacho).filter(Despacho.id_orden.in_(orden_ids)).all()
    despachos_map: Dict[uuid.UUID, Despacho] = {d.id_orden: d for d in despachos}

    comuna_ids = set()
    for c in clientes_map.values():
        if c.id_comuna:
            comuna_ids.add(c.id_comuna)
    for d in despachos:
        if d.id_comuna_destino:
            comuna_ids.add(d.id_comuna_destino)

    comunas_map: Dict[int, str] = {}
    if comuna_ids:
        comunas = db.query(Comuna).filter(Comuna.id_comuna.in_(comuna_ids)).all()
        comunas_map = {c.id_comuna: c.nombre_comuna for c in comunas}

    reservas = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_orden.in_(orden_ids)).all()
    reservas_map: Dict[uuid.UUID, Reservas_Backorder] = {r.id_orden: r for r in reservas}
    reserva_cat_ids = {r.id_categoria_requerida for r in reservas if r.id_categoria_requerida}

    detalles = (
        db.query(Detalle_Orden)
        .filter(Detalle_Orden.id_orden.in_(orden_ids))
        .order_by(Detalle_Orden.id_detalle.asc())
        .all()
    )
    detalles_map: Dict[uuid.UUID, List[Detalle_Orden]] = defaultdict(list)
    for d in detalles:
        detalles_map[d.id_orden].append(d)

    activo_ids = list({d.id_activo for d in detalles if d.id_activo})
    activos_map = {}
    if activo_ids:
        activos_info = (
            db.query(Activo_Inventariado, Vehiculo_Origen, Categoria_Activo)
            .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
            .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
            .filter(Activo_Inventariado.id_activo.in_(activo_ids))
            .all()
        )
        for act, veh, cat in activos_info:
            activos_map[act.id_activo] = (act, veh, cat)

    categorias_map: Dict[int, Categoria_Activo] = {}
    if reserva_cat_ids:
        cats = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria.in_(reserva_cat_ids)).all()
        categorias_map = {c.id_categoria: c for c in cats}

    resultado = []
    for orden in ordenes:
        # Cliente
        cliente_db = clientes_map.get(orden.id_cliente)
        cliente_resumen = None
        if cliente_db:
            comuna_nombre = comunas_map.get(cliente_db.id_comuna) if cliente_db.id_comuna else None
            cliente_resumen = ClienteOrdenResumen(
                rut_cliente=cliente_db.rut_cliente,
                nombres=cliente_db.nombres,
                apellidos=cliente_db.apellidos,
                telefono=cliente_db.telefono,
                correo=cliente_db.correo,
                comuna=comuna_nombre,
            )

        # Despacho
        despacho_db = despachos_map.get(orden.id_orden)
        despacho_resumen = None
        if despacho_db:
            comuna_dest_nombre = comunas_map.get(despacho_db.id_comuna_destino) if despacho_db.id_comuna_destino else None
            despacho_resumen = DespachoOrdenResumen(
                id_despacho=despacho_db.id_despacho,
                direccion_envio=despacho_db.direccion_envio,
                receptor_nombres=despacho_db.receptor_nombres,
                receptor_rut=despacho_db.receptor_rut,
                receptor_telefono=despacho_db.receptor_telefono,
                empresa_transporte=despacho_db.empresa_transporte,
                costo_envio=despacho_db.costo_envio or 0,
                estado_despacho=despacho_db.estado_despacho,
                comuna_destino=comuna_dest_nombre,
            )

        # Detalle de líneas
        reserva_asociada = reservas_map.get(orden.id_orden)
        detalles_db = detalles_map.get(orden.id_orden, [])
        detalles_resumen = []
        for d in detalles_db:
            sku_fisico = None
            titulo_item = d.descripcion_manual or "Repuesto Misceláneo"
            es_inv = False

            id_cat = None
            nom_cat = None
            if d.id_activo:
                es_inv = True
                activo_db = activos_map.get(d.id_activo)
                if activo_db:
                    act, veh, cat = activo_db
                    sku_fisico = act.sku_qr_fisico
                    id_cat = cat.id_categoria if cat else None
                    nom_cat = cat.nombre_categoria if cat else None
                    nombre_cat = cat.nombre_categoria if cat else "Repuesto"
                    if veh:
                        titulo_item = f"{nombre_cat} - {veh.marca} {veh.modelo} {veh.anio or ''}".strip()
                    else:
                        titulo_item = f"{nombre_cat} ({sku_fisico})"
            elif reserva_asociada:
                cat_bo = categorias_map.get(reserva_asociada.id_categoria_requerida)
                id_cat = cat_bo.id_categoria if cat_bo else None
                nom_cat = cat_bo.nombre_categoria if cat_bo else "Venta en Verde"
                if not d.descripcion_manual or "VENTA EN VERDE" in d.descripcion_manual.upper() or "BACKORDER" in d.descripcion_manual.upper():
                    titulo_item = f"{nom_cat}: {reserva_asociada.marca_requerida} {reserva_asociada.modelo_requerido} ({reserva_asociada.anio_requerido or 'Año N/A'})"

            if not d.id_activo and not reserva_asociada:
                # Ítems misceláneos / venta libre: no tienen notas de preparación técnica para bodega
                notas_final = None
            else:
                notas_final = d.notas_preparacion
                if reserva_asociada and (not notas_final or "PAGADO" in notas_final.upper() or "ESPERANDO" in notas_final.upper()):
                    especs = []
                    if reserva_asociada.cilindrada_requerida: especs.append(f"Cil: {reserva_asociada.cilindrada_requerida}")
                    if reserva_asociada.transmision_requerida: especs.append(f"Trans: {reserva_asociada.transmision_requerida}")
                    if reserva_asociada.combustible_requerido: especs.append(f"Comb: {reserva_asociada.combustible_requerido}")
                    if especs:
                        notas_final = f"Requerido: {' • '.join(especs)}"

            detalles_resumen.append(
                DetalleOrdenItemResponse(
                    id_detalle=d.id_detalle,
                    id_activo=d.id_activo,
                    id_categoria=id_cat,
                    nombre_categoria=nom_cat,
                    titulo=titulo_item,
                    sku_qr_fisico=sku_fisico,
                    descripcion_manual=d.descripcion_manual,
                    notas_preparacion=notas_final,
                    cantidad=d.cantidad,
                    precio_unitario=d.precio_unitario,
                    precio_final=d.precio_final,
                    subtotal=d.precio_final * d.cantidad,
                    es_inventariado=es_inv,
                    preparacion_lista=d.preparacion_lista,
                    estado_preparacion=d.estado_preparacion,
                )
            )

        es_limache_asig = bool(
            id_limache
            and orden.id_vendedor == id_limache
            and orden.id_vendedor_asignado == current_user.id_usuario
        )

        resultado.append(
            OrdenHistorialItemResponse(
                id_orden=orden.id_orden,
                numero_orden=orden.numero_orden,
                folio=orden.folio,
                estado_orden=orden.estado_orden,
                total_venta=orden.total_venta,
                descuento=getattr(orden, "descuento", 0) or 0,
                monto_pendiente=orden.monto_pendiente,
                qr_transaccional_salida=orden.qr_transaccional_salida,
                fecha_creacion=orden.fecha_creacion.isoformat() if orden.fecha_creacion else None,
                fecha_actualizacion=orden.fecha_actualizacion.isoformat() if orden.fecha_actualizacion else None,
                total_items=len(detalles_resumen),
                cliente=cliente_resumen,
                despacho=despacho_resumen,
                detalles=detalles_resumen,
                id_vendedor_asignado=orden.id_vendedor_asignado,
                es_asignada_limache=es_limache_asig,
            )
        )

    return resultado


@router.post(
    "/{id_orden}/validar-activo-backorder",
    response_model=ValidarActivoBackorderResponse,
    summary="Validar Activo para Backorder desde Mis Ventas",
    description="Permite al vendedor validar un SKU físico antes de asignarlo a una venta en verde pagada."
)
def validar_activo_backorder_orden(
    id_orden: uuid.UUID,
    payload: AsignarActivoBackorderRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada.")

    reserva = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_orden == id_orden).first()
    if not reserva:
        raise HTTPException(status_code=404, detail="No se encontró una reserva en verde para esta orden.")

    sku_clean = payload.sku_activo.strip().upper()
    prefijo_cat = "MOT-" if reserva.id_categoria_requerida == 1 else "CAJ-"
    candidatos_sku = [sku_clean]
    if not (sku_clean.startswith("MOT-") or sku_clean.startswith("CAJ-")):
        candidatos_sku.append(f"{prefijo_cat}{sku_clean}")

    print(f"🔍 [BACKORDER-VALIDAR] Validando SKU/Ingreso '{sku_clean}' (Candidatos: {candidatos_sku}) para orden {id_orden} por usuario {current_user.email}...")

    activo_raw = (
        db.query(Activo_Inventariado, Vehiculo_Origen, Detalle_Motor, Detalle_Caja_Cambio, Categoria_Activo, Estado_Activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .outerjoin(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(
            or_(
                func.upper(Activo_Inventariado.sku_qr_fisico).in_(candidatos_sku),
                and_(
                    Vehiculo_Origen.numero_ingreso == sku_clean,
                    Activo_Inventariado.id_categoria == reserva.id_categoria_requerida
                )
            )
        )
        .first()
    )

    if not activo_raw:
        tipo_esperado = "Motor" if reserva.id_categoria_requerida == 1 else "Caja de Cambios"
        print(f"⚠️ [BACKORDER-VALIDAR] Repuesto {sku_clean} ({tipo_esperado}) no encontrado en inventario para orden {id_orden}.")
        raise HTTPException(status_code=404, detail=f"No se encontró un {tipo_esperado} asociado al ingreso o SKU '{payload.sku_activo}' en inventario.")

    activo, vehiculo, motor, caja_cambio, categoria, estado_activo = activo_raw
    discrepancias = []

    estados_validos = ["disponible", "paletizado"]
    nombre_estado_actual = estado_activo.nombre_estado if estado_activo else ""
    if nombre_estado_actual.lower() not in estados_validos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El repuesto con SKU '{activo.sku_qr_fisico}' no está disponible (estado actual: '{nombre_estado_actual}'). Solo se pueden asignar repuestos en estado 'Disponible' o 'Paletizado'."
        )

    if vehiculo and reserva.marca_requerida and vehiculo.marca.lower() != reserva.marca_requerida.lower():
        discrepancias.append(f"Marca requerida: {reserva.marca_requerida}, Marca del repuesto: {vehiculo.marca}")

    if vehiculo and reserva.modelo_requerido and vehiculo.modelo.lower() != reserva.modelo_requerido.lower():
        discrepancias.append(f"Modelo requerido: {reserva.modelo_requerido}, Modelo del repuesto: {vehiculo.modelo}")

    if motor and reserva.cilindrada_requerida and motor.cilindrada:
        req_c = reserva.cilindrada_requerida.lower().replace("l", "").replace("cc", "").strip()
        act_c = motor.cilindrada.lower().replace("l", "").replace("cc", "").strip()
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
    mensaje = "El repuesto cumple con todas las especificaciones solicitadas." if coincide else "Hay discrepancias en los atributos técnicos o de estado."

    ubicacion_partes = []
    if activo.ubicacion_galpon:
        ubicacion_partes.append(f"Galpón {activo.ubicacion_galpon}")
    if activo.ubicacion_pasillo:
        ubicacion_partes.append(f"Pasillo {activo.ubicacion_pasillo}")
    if activo.ubicacion_pallet:
        ubicacion_partes.append(f"Pallet {activo.ubicacion_pallet}")
    ubicacion_str = " • ".join(ubicacion_partes) if ubicacion_partes else None

    num_motor = (motor.numero_motor if motor and motor.numero_motor else (vehiculo.numero_motor if vehiculo else None))
    if num_motor and num_motor.strip().upper() == "S/A":
        num_motor = None

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
        numero_motor=num_motor,
        numero_ingreso=vehiculo.numero_ingreso if vehiculo else None,
    )

    tipo_pieza = "Motor" if reserva.id_categoria_requerida == 1 else "Caja de Cambios"
    cat_db = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == reserva.id_categoria_requerida).first()
    if cat_db and cat_db.nombre_categoria:
        tipo_pieza = cat_db.nombre_categoria

    solicitado_detalle = ReservaSolicitadaBackorderDTO(
        categoria=tipo_pieza,
        id_categoria=reserva.id_categoria_requerida,
        marca=reserva.marca_requerida,
        modelo=reserva.modelo_requerido,
        anio=reserva.anio_requerido,
        cilindrada=reserva.cilindrada_requerida,
        combustible=reserva.combustible_requerido,
        transmision=reserva.transmision_requerida,
        notas=reserva.notas_preparacion,
        precio_acordado=reserva.precio_acordado,
    )

    print(f"📊 [BACKORDER-VALIDAR] Comparación para orden {id_orden}: Activo={activo.sku_qr_fisico}, Coincide={coincide}, Discrepancias={len(discrepancias)}")

    return ValidarActivoBackorderResponse(
        coincide=coincide,
        discrepancias=discrepancias,
        mensaje=mensaje,
        activo_detalle=activo_detalle,
        solicitado_detalle=solicitado_detalle,
    )


@router.post(
    "/{id_orden}/asignar-activo-backorder",
    response_model=AsignarActivoBackorderResponse,
    summary="Asignar Activo Físico Paletizado a Venta en Verde Pagada",
    description="Permite al vendedor asignar un activo físico (Disponible o Paletizado) a una venta en verde ya pagada, generando el QR transaccional para la Barrera de Salida."
)
def asignar_activo_backorder(
    id_orden: uuid.UUID,
    payload: AsignarActivoBackorderRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    if current_user.id_rol == 8:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: El perfil de Auditoría no posee permisos para asignar repuestos a órdenes."
        )

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden de venta no encontrada.")

    reserva = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_orden == id_orden).first()
    if not reserva:
        raise HTTPException(status_code=404, detail="No se encontró una Venta en Verde asociada a esta orden.")

    if reserva.id_activo_asignado is not None:
        raise HTTPException(status_code=400, detail="Esta orden ya tiene un activo físico asignado.")

    if orden.monto_pendiente > 0 or orden.estado_orden != "Pagada":
        raise HTTPException(status_code=400, detail="La orden debe estar totalmente pagada antes de asignar el activo físico.")

    sku_clean = payload.sku_activo.strip().upper()
    prefijo_cat = "MOT-" if reserva.id_categoria_requerida == 1 else "CAJ-"
    candidatos_sku = [sku_clean]
    if not (sku_clean.startswith("MOT-") or sku_clean.startswith("CAJ-")):
        candidatos_sku.append(f"{prefijo_cat}{sku_clean}")

    print(f"📦 [BACKORDER-ASIGNAR] Solicitud de asignación orden {id_orden} con input '{sku_clean}' (Candidatos: {candidatos_sku}) por usuario {current_user.email} (Forzado: {payload.forzar_atribucion})...")

    activo_raw = (
        db.query(Activo_Inventariado, Vehiculo_Origen, Detalle_Motor, Detalle_Caja_Cambio, Categoria_Activo, Estado_Activo)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .outerjoin(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .outerjoin(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(
            or_(
                func.upper(Activo_Inventariado.sku_qr_fisico).in_(candidatos_sku),
                and_(
                    Vehiculo_Origen.numero_ingreso == sku_clean,
                    Activo_Inventariado.id_categoria == reserva.id_categoria_requerida
                )
            )
        )
        .first()
    )

    if not activo_raw:
        tipo_esperado = "Motor" if reserva.id_categoria_requerida == 1 else "Caja de Cambios"
        print(f"❌ [BACKORDER-ASIGNAR] Repuesto {sku_clean} ({tipo_esperado}) no encontrado en inventario para orden {id_orden}.")
        raise HTTPException(status_code=404, detail=f"No se encontró un {tipo_esperado} asociado al ingreso o SKU '{payload.sku_activo}' en inventario.")

    activo, vehiculo, motor, caja_cambio, categoria, estado_activo = activo_raw

    estados_validos = ["disponible", "paletizado"]
    nombre_estado = estado_activo.nombre_estado if estado_activo else ""
    if nombre_estado.lower() not in estados_validos:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"El repuesto con SKU {activo.sku_qr_fisico} está en estado '{nombre_estado}'. Solo se pueden asignar piezas en estado 'Disponible' o 'Paletizado'."
        )

    discrepancias = []
    if vehiculo and reserva.marca_requerida and vehiculo.marca.lower() != reserva.marca_requerida.lower():
        discrepancias.append(f"Marca requerida: {reserva.marca_requerida}, Marca repuesto: {vehiculo.marca}")
    if vehiculo and reserva.modelo_requerido and vehiculo.modelo.lower() != reserva.modelo_requerido.lower():
        discrepancias.append(f"Modelo requerido: {reserva.modelo_requerido}, Modelo repuesto: {vehiculo.modelo}")

    if discrepancias and not payload.forzar_atribucion:
        raise HTTPException(
            status_code=400,
            detail=f"Discrepancia técnica: {'; '.join(discrepancias)}. Confirme 'forzar atribución' si desea continuar."
        )

    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

    # Actualizar estado del activo a Vendido
    estado_vendido = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
    if not estado_vendido:
        estado_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        db.add(estado_vendido)
        db.flush()

    activo.id_estado = estado_vendido.id_estado
    activo.reservado_por = None
    activo.reserva_expira_en = None
    activo.fecha_actualizacion = now_utc

    # Asignar a la reserva y marcarla como completada
    reserva.id_activo_asignado = activo.id_activo
    reserva.estado_reserva = "Completada"
    reserva.fecha_actualizacion = now_utc

    # Generar QR transaccional para la orden
    qr_hash = f"TX-QR-{uuid.uuid4()}"
    orden.qr_transaccional_salida = qr_hash
    orden.fecha_actualizacion = now_utc
    print(f"✅ [BACKORDER-ASIGNAR] Activo {activo.sku_qr_fisico} vinculado exitosamente a orden {id_orden}. QR de salida emitido: {qr_hash}")

    # Actualizar línea de Detalle_Orden
    detalles_bo = db.query(Detalle_Orden).filter(
        Detalle_Orden.id_orden == orden.id_orden,
        Detalle_Orden.id_activo.is_(None)
    ).all()
    if detalles_bo:
        det = detalles_bo[0]
        det.id_activo = activo.id_activo
        det.estado_preparacion = "Listo"
        det.descripcion_manual = f"[VENTA EN VERDE ASIGNADA] {activo.sku_qr_fisico} - {reserva.marca_requerida} {reserva.modelo_requerido}"
        det.notas_preparacion = f"Asignado físicamente por vendedor {current_user.nombres} {current_user.apellidos}"
    else:
        detalle = Detalle_Orden(
            id_orden=orden.id_orden,
            id_activo=activo.id_activo,
            descripcion_manual=f"[VENTA EN VERDE ASIGNADA] {activo.sku_qr_fisico} - {reserva.marca_requerida} {reserva.modelo_requerido}",
            notas_preparacion=f"Asignado físicamente por vendedor {current_user.nombres} {current_user.apellidos}",
            cantidad=1,
            precio_unitario=reserva.precio_acordado,
            precio_final=reserva.precio_acordado,
            estado_preparacion="Listo",
        )
        db.add(detalle)

    db.commit()

    folio_doc = orden.folio or f"ORD-{str(orden.id_orden).replace('-', '')[:4].upper()}"

    return AsignarActivoBackorderResponse(
        success=True,
        mensaje="Activo físico asignado exitosamente a la orden. QR de salida generado para Barrera de Salida.",
        id_orden=orden.id_orden,
        folio=folio_doc,
        sku_asignado=activo.sku_qr_fisico,
        qr_transaccional_salida=qr_hash
    )


@router.get(
    "/vendedores",
    response_model=List[VendedorResumenResponse],
    summary="Listado de Vendedores Activos por Sucursal",
    description="Retorna los vendedores activos para la delegación de entregas o ventas online.",
)
def listar_vendedores_sucursal(
    sucursal_id: Optional[int] = Query(None, description="ID de la sucursal activa (opcional)"),
    incluir_online: bool = Query(True, description="Incluir también rol 7 (Vendedor Online) para atribución de ventas"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    roles = [2, 6, 7] if incluir_online else [2, 6]
    query = db.query(Usuario).filter(
        Usuario.estado == "Activo",
        Usuario.id_rol.in_(roles),
    )
    if sucursal_id is not None:
        query = query.filter(
            or_(
                Usuario.id_sucursal == sucursal_id,
                func.lower(Usuario.email) == "limache@cresal.cl",
                func.lower(Usuario.apellidos).like("%limache%"),
            )
        )
    usuarios = query.order_by(Usuario.id_rol.desc(), Usuario.nombres).all()
    return [
        VendedorResumenResponse(
            id_usuario=u.id_usuario,
            nombre_completo=f"{u.nombres} {u.apellidos or ''}".strip(),
            rut=u.rut_usuario,
            id_sucursal=u.id_sucursal,
            correo=u.email,
            id_rol=u.id_rol,
            rol_nombre=(
                "Vendedor Limache"
                if (u.email and u.email.lower() == "limache@cresal.cl") or (u.apellidos and "limache" in u.apellidos.lower())
                else ("Jefe de Ventas" if u.id_rol == 6 else ("Vendedora Online" if u.id_rol == 7 else "Vendedor Mesón"))
            ),
        )
        for u in usuarios
    ]


# ==========================================
# MÓDULO: ENTREGAS Y ENVÍOS (VENTAS PRESENCIALES Y ONLINE)
# ==========================================

@router.get(
    "/entregas-envios",
    response_model=List[EntregaEnvioItemResponse],
    summary="Listado Colaborativo de Entregas en Tienda y Despachos Externos",
    description="Consulta colaborativa de pedidos con filtros por cliente, vendedor, tipo y reglas de privacidad.",
)
def listar_entregas_envios(
    sucursal_id: int = Query(1, description="ID de la sucursal activa"),
    tipo: Optional[str] = Query(None, description="Filtro por tipo: 'retiro' o 'despacho'"),
    busqueda_cliente: Optional[str] = Query(None, description="Filtro por Nombre, RUT o Teléfono del cliente"),
    busqueda_vendedor: Optional[str] = Query(None, description="Filtro por Vendedor creador o asignado"),
    busqueda: Optional[str] = Query(None, description="Término general de búsqueda"),
    estado_pago: Optional[str] = Query(None, description="Filtro de pago: 'todos', 'pagados', 'pendientes'"),
    solo_activas: Optional[bool] = Query(True, description="Filtra exclusivamente órdenes de la jornada operativa pendientes de entrega/despacho"),
    limit: Optional[int] = Query(None, description="Límite de registros para carga progresiva"),
    offset: int = Query(0, description="Offset de inicio para paginación"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    tipo_filtro = (tipo.strip().lower() if tipo else None)
    estados_filtro = ["Reservada", "Pagada"] if (solo_activas is not False) else ["Reservada", "Pagada", "Completada", "Despachada"]

    # A. Consulta de Retiros en Tienda (sin registro en Despacho)
    retiros_raw = []
    if tipo_filtro in [None, "retiro", "traslado", "todos", ""]:
        retiros_raw = (
            db.query(Orden_Venta)
            .outerjoin(Despacho, Orden_Venta.id_orden == Despacho.id_orden)
            .filter(
                Orden_Venta.id_sucursal == sucursal_id,
                Orden_Venta.estado_orden.in_(estados_filtro),
                Despacho.id_despacho == None,
            )
            .all()
        )

    # B. Consulta de Despachos Externos y Traslados (con registro en Despacho)
    despachos_raw = []
    if tipo_filtro in [None, "despacho", "traslado", "todos", ""]:
        despachos_raw = (
            db.query(Orden_Venta, Despacho)
            .join(Despacho, Orden_Venta.id_orden == Despacho.id_orden)
            .filter(
                Orden_Venta.id_sucursal == sucursal_id,
                Orden_Venta.estado_orden.in_(estados_filtro),
            )
            .all()
        )

    all_raw_ids = [o.id_orden for o in retiros_raw] + [o.id_orden for o, _ in despachos_raw]
    if not all_raw_ids:
        return []

    # Carga por lote de tracking logístico para clasificar Traslado sin queries N+1
    tracking_set = set(
        r[0] for r in db.query(Tracking_Logistico.id_orden)
        .filter(Tracking_Logistico.id_orden.in_(all_raw_ids))
        .all()
    )

    ordenes_resultado = []
    for o in retiros_raw:
        tiene_traslado = o.id_orden in tracking_set
        tipo_label = "Traslado" if tiene_traslado else "Retiro"
        if tipo_filtro == "retiro" and tiene_traslado:
            continue
        if tipo_filtro == "traslado" and not tiene_traslado:
            continue
        ordenes_resultado.append((tipo_label, o, None))

    for o, desp in despachos_raw:
        es_traslado = (
            (desp.empresa_transporte or "").lower() == "interno"
            or "traslado" in (desp.direccion_envio or "").lower()
            or o.id_orden in tracking_set
        )
        tipo_label = "Traslado" if es_traslado else "Despacho"
        if tipo_filtro == "despacho" and es_traslado:
            continue
        if tipo_filtro == "traslado" and not es_traslado:
            continue
        ordenes_resultado.append((tipo_label, o, desp))

    # Ordenar cronológicamente descendente
    ordenes_resultado.sort(key=lambda x: x[1].fecha_creacion, reverse=True)

    if not ordenes_resultado:
        return []

    es_admin_o_jefe = current_user.id_rol in [1, 5, 6]
    candidatos_filtrados = []
    for tipo_entrega_item, orden, desp in ordenes_resultado:
        # 1. Regla de Privacidad y Visibilidad:
        if not es_admin_o_jefe and orden.id_vendedor_asignado is not None:
            if orden.id_vendedor_asignado != current_user.id_usuario and orden.id_vendedor != current_user.id_usuario:
                continue

        # 2. Filtro por Estado de Pago
        if estado_pago:
            ep = estado_pago.strip().lower()
            if ep == "pagados" and orden.monto_pendiente > 0:
                continue
            elif ep in ["pendientes", "con saldo pendiente"] and orden.monto_pendiente == 0:
                continue

        candidatos_filtrados.append((tipo_entrega_item, orden, desp))

    if not candidatos_filtrados:
        return []

    candidatos_ids = [orden.id_orden for _, orden, _ in candidatos_filtrados]

    # Carga por lotes (Batch Loading) de todas las entidades relacionadas para rendimiento < 300ms
    reservas = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_orden.in_(candidatos_ids)).all()
    reservas_map = {r.id_orden: r for r in reservas}
    reserva_ids_set = set(reservas_map.keys())

    detalles = (
        db.query(Detalle_Orden)
        .filter(Detalle_Orden.id_orden.in_(candidatos_ids))
        .order_by(Detalle_Orden.id_detalle.asc())
        .all()
    )
    detalles_by_orden = defaultdict(list)
    for d in detalles:
        detalles_by_orden[d.id_orden].append(d)

    cliente_ids = list({orden.id_cliente for _, orden, _ in candidatos_filtrados if orden.id_cliente})
    clientes_map: Dict[uuid.UUID, Cliente] = {}
    if cliente_ids:
        clientes = db.query(Cliente).filter(Cliente.id_cliente.in_(cliente_ids)).all()
        clientes_map = {c.id_cliente: c for c in clientes}

    despachos_map: Dict[uuid.UUID, Despacho] = {
        orden.id_orden: desp for _, orden, desp in candidatos_filtrados if desp is not None
    }

    comuna_ids = set()
    for c in clientes_map.values():
        if c.id_comuna:
            comuna_ids.add(c.id_comuna)
    for d in despachos_map.values():
        if d.id_comuna_destino:
            comuna_ids.add(d.id_comuna_destino)

    comunas_map: Dict[int, str] = {}
    if comuna_ids:
        comunas = db.query(Comuna).filter(Comuna.id_comuna.in_(comuna_ids)).all()
        comunas_map = {c.id_comuna: c.nombre_comuna for c in comunas}

    usuario_ids = set()
    for _, orden, _ in candidatos_filtrados:
        if orden.id_vendedor:
            usuario_ids.add(orden.id_vendedor)
        if orden.id_vendedor_asignado:
            usuario_ids.add(orden.id_vendedor_asignado)

    usuarios_map: Dict[uuid.UUID, Usuario] = {}
    if usuario_ids:
        usuarios = db.query(Usuario).filter(Usuario.id_usuario.in_(usuario_ids)).all()
        usuarios_map = {u.id_usuario: u for u in usuarios}

    activo_ids = list({d.id_activo for d in detalles if d.id_activo})
    activos_map = {}
    if activo_ids:
        activos_info = (
            db.query(Activo_Inventariado, Vehiculo_Origen, Categoria_Activo)
            .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
            .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
            .filter(Activo_Inventariado.id_activo.in_(activo_ids))
            .all()
        )
        for act, veh, cat in activos_info:
            activos_map[act.id_activo] = (act, veh, cat)

    items_response = []
    term_busqueda = busqueda.strip().upper() if busqueda and busqueda.strip() else None

    for tipo_entrega_item, orden, desp in candidatos_filtrados:
        detalles_db = detalles_by_orden.get(orden.id_orden, [])
        reserva_asociada = reservas_map.get(orden.id_orden)

        # Regla de Venta en Verde:
        tiene_reserva_verde = (orden.id_orden in reserva_ids_set) or any(
            "[RESERVA EN VERDE]" in (d.descripcion_manual or "").upper() or
            "VENTA EN VERDE" in (d.descripcion_manual or "").upper()
            for d in detalles_db
        )

        if tiene_reserva_verde and (orden.monto_pendiente > 0 or not orden.qr_transaccional_salida):
            continue

        # Cliente
        cliente_db = clientes_map.get(orden.id_cliente)
        cliente_resumen = None
        if cliente_db:
            comuna_nombre = comunas_map.get(cliente_db.id_comuna) if cliente_db.id_comuna else None
            cliente_resumen = ClienteOrdenResumen(
                rut_cliente=cliente_db.rut_cliente,
                nombres=cliente_db.nombres,
                apellidos=cliente_db.apellidos,
                telefono=cliente_db.telefono,
                correo=cliente_db.correo,
                comuna=comuna_nombre,
            )

        # Despacho
        despacho_db = despachos_map.get(orden.id_orden)
        despacho_resumen = None
        if despacho_db:
            comuna_dest_nombre = comunas_map.get(despacho_db.id_comuna_destino) if despacho_db.id_comuna_destino else None
            despacho_resumen = DespachoOrdenResumen(
                id_despacho=despacho_db.id_despacho,
                direccion_envio=despacho_db.direccion_envio,
                receptor_nombres=despacho_db.receptor_nombres,
                receptor_rut=despacho_db.receptor_rut,
                receptor_telefono=despacho_db.receptor_telefono,
                empresa_transporte=despacho_db.empresa_transporte,
                costo_envio=despacho_db.costo_envio or 0,
                estado_despacho=despacho_db.estado_despacho,
                comuna_destino=comuna_dest_nombre,
            )

        # Detalles
        detalles_resumen = []
        for d in detalles_db:
            sku_fisico = None
            titulo_item = d.descripcion_manual or "Repuesto Misceláneo"
            es_inv = False
            id_cat = None
            nom_cat = None

            if d.id_activo:
                es_inv = True
                activo_db = activos_map.get(d.id_activo)
                if activo_db:
                    act, veh, cat = activo_db
                    sku_fisico = act.sku_qr_fisico
                    id_cat = cat.id_categoria if cat else None
                    nom_cat = cat.nombre_categoria if cat else None
                    nombre_cat = cat.nombre_categoria if cat else "Repuesto"
                    if veh:
                        titulo_item = f"{nombre_cat} - {veh.marca} {veh.modelo} {veh.anio or ''}".strip()
                    else:
                        titulo_item = f"{nombre_cat} ({sku_fisico})"

            notas_item = None if (not d.id_activo and not reserva_asociada) else d.notas_preparacion

            detalles_resumen.append(
                DetalleOrdenItemResponse(
                    id_detalle=d.id_detalle,
                    id_activo=d.id_activo,
                    id_categoria=id_cat,
                    nombre_categoria=nom_cat,
                    titulo=titulo_item,
                    sku_qr_fisico=sku_fisico,
                    descripcion_manual=d.descripcion_manual,
                    notas_preparacion=notas_item,
                    cantidad=d.cantidad,
                    precio_unitario=d.precio_unitario,
                    precio_final=d.precio_final,
                    subtotal=d.precio_final * d.cantidad,
                    es_inventariado=es_inv,
                    preparacion_lista=d.preparacion_lista,
                    estado_preparacion=d.estado_preparacion or "Pendiente",
                )
            )

        # Vendedor Responsable (Creador)
        vendedor_db = usuarios_map.get(orden.id_vendedor)
        vendedor_nombre = (
            f"{vendedor_db.nombres} {vendedor_db.apellidos or ''}".strip()
            if vendedor_db
            else "Vendedor Central"
        )

        # Vendedor Asignado
        vendedor_asignado_nombre = "Mesón General (Todos)"
        if orden.id_vendedor_asignado:
            v_asig_db = usuarios_map.get(orden.id_vendedor_asignado)
            if v_asig_db:
                vendedor_asignado_nombre = f"{v_asig_db.nombres} {v_asig_db.apellidos or ''}".strip()

        todos_listos = all(d.estado_preparacion == "Listo" for d in detalles_resumen) if detalles_resumen else True
        folio = orden.folio

        # Filtro Específico: Cliente (Nombre, RUT, Teléfono)
        if busqueda_cliente and busqueda_cliente.strip():
            bc = busqueda_cliente.strip().upper()
            rut_c = (cliente_resumen.rut_cliente if cliente_resumen and cliente_resumen.rut_cliente else "").upper()
            nom_c = f"{cliente_resumen.nombres or ''} {cliente_resumen.apellidos or ''}".strip().upper() if cliente_resumen else ""
            tel_c = (cliente_resumen.telefono if cliente_resumen and cliente_resumen.telefono else "").upper()
            rec_rut = (despacho_resumen.receptor_rut if despacho_resumen and despacho_resumen.receptor_rut else "").upper()
            rec_nom = (despacho_resumen.receptor_nombres if despacho_resumen and despacho_resumen.receptor_nombres else "").upper()
            rec_tel = (despacho_resumen.receptor_telefono if despacho_resumen and despacho_resumen.receptor_telefono else "").upper()

            if not (bc in rut_c or bc in nom_c or bc in tel_c or bc in rec_rut or bc in rec_nom or bc in rec_tel):
                continue

        # Filtro Específico: Vendedor (Creador o Asignado)
        if busqueda_vendedor and busqueda_vendedor.strip():
            bv = busqueda_vendedor.strip().upper()
            vend_c = vendedor_nombre.upper()
            vend_a = (vendedor_asignado_nombre or "").upper()
            if not (bv in vend_c or bv in vend_a):
                continue

        # Filtro General (Compatibilidad)
        if term_busqueda:
            folio_upper = folio.upper()
            numero_str = str(orden.numero_orden) if orden.numero_orden is not None else ""
            rut_upper = (cliente_resumen.rut_cliente if cliente_resumen else "").upper()
            nom_upper = f"{cliente_resumen.nombres if cliente_resumen else ''} {cliente_resumen.apellidos if cliente_resumen else ''}".upper()
            rec_rut_upper = (despacho_resumen.receptor_rut if despacho_resumen else "").upper()
            rec_nom_upper = (despacho_resumen.receptor_nombres if despacho_resumen else "").upper()
            vend_upper = vendedor_nombre.upper()
            vend_asig_upper = (vendedor_asignado_nombre or "").upper()

            matches = (
                term_busqueda in folio_upper
                or (bool(numero_str) and term_busqueda in numero_str)
                or (bool(orden.qr_transaccional_salida) and term_busqueda in orden.qr_transaccional_salida.upper())
                or term_busqueda in rut_upper
                or term_busqueda in nom_upper
                or term_busqueda in rec_rut_upper
                or term_busqueda in rec_nom_upper
                or term_busqueda in vend_upper
                or term_busqueda in vend_asig_upper
                or any(term_busqueda in (d.titulo or "").upper() for d in detalles_resumen)
            )
            if not matches:
                continue

        items_response.append(
            EntregaEnvioItemResponse(
                id_orden=orden.id_orden,
                numero_orden=orden.numero_orden,
                folio=folio,
                tipo_entrega=tipo_entrega_item,
                estado_orden=orden.estado_orden,
                total_venta=orden.total_venta,
                descuento=getattr(orden, "descuento", 0) or 0,
                monto_pendiente=orden.monto_pendiente,
                qr_transaccional_salida=orden.qr_transaccional_salida,
                fecha_creacion=orden.fecha_creacion.isoformat() if orden.fecha_creacion else None,
                fecha_actualizacion=orden.fecha_actualizacion.isoformat() if orden.fecha_actualizacion else None,
                total_items=len(detalles_resumen),
                cliente=cliente_resumen,
                despacho=despacho_resumen,
                detalles=detalles_resumen,
                vendedor_nombre=vendedor_nombre,
                id_vendedor_asignado=orden.id_vendedor_asignado,
                vendedor_asignado_nombre=vendedor_asignado_nombre,
                preparacion_lista=todos_listos,
                todos_preparados=todos_listos,
            )
        )

    if limit is not None:
        return items_response[offset : offset + limit]
    elif offset > 0:
        return items_response[offset:]

    return items_response


@router.patch(
    "/{id_orden}/entregar",
    response_model=EntregaConfirmacionResponse,
    status_code=200,
    summary="Confirmar Entrega de Pedido en Tienda (Cierre de Ciclo)",
)
def confirmar_entrega_tienda(
    id_orden: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden de venta no encontrada.")

    if orden.monto_pendiente > 0:
        raise HTTPException(
            status_code=400,
            detail=f"No se puede confirmar la entrega. La orden presenta un saldo pendiente de ${orden.monto_pendiente} que debe ser saldado en caja."
        )

    if orden.estado_orden in ["Despachada", "Completada"]:
        folio = orden.folio
        return EntregaConfirmacionResponse(
            id_orden=orden.id_orden,
            folio=folio,
            estado_orden=orden.estado_orden,
            mensaje=f"¡Entrega ya confirmada previamente! (Estado: {orden.estado_orden})",
            activos_finalizados=0,
            fecha_entrega=datetime.now().isoformat(),
        )

    detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
    activos_sin_imprimir = []
    for d in detalles:
        if d.id_activo:
            act = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
            if act and not act.qr_impreso:
                activos_sin_imprimir.append(act.sku_qr_fisico or str(act.id_activo)[:8])

    if activos_sin_imprimir:
        raise HTTPException(
            status_code=400,
            detail=f"No se puede confirmar la entrega. Las siguientes piezas no tienen su código QR impreso: {', '.join(activos_sin_imprimir)}. Imprima la etiqueta antes de entregar."
        )

    try:
        # Actualizar Orden a 'Completada'
        orden.estado_orden = "Completada"
        orden.fecha_actualizacion = datetime.now()

        # Obtener o crear estado 'Entregado' / 'Finalizado'
        estado_final = db.query(Estado_Activo).filter(
            Estado_Activo.nombre_estado.in_(["Entregado", "Finalizado"])
        ).first()
        if not estado_final:
            estado_final = Estado_Activo(id_estado=6, nombre_estado="Entregado")
            db.add(estado_final)
            db.flush()

        detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
        activos_actualizados = 0

        for d in detalles:
            d.estado_preparacion = "Listo"
            d.fecha_preparacion = datetime.now()
            if d.id_activo:
                activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                if activo:
                    activo.id_estado = estado_final.id_estado
                    activo.ubicacion_pasillo = None
                    activo.ubicacion_pallet = None
                    activo.ubicacion_galpon = None
                    activo.observacion_estado = f"Entregado en tienda por {current_user.nombres} {current_user.apellidos} - Orden #{str(orden.id_orden)[:8].upper()}"
                    activo.version_lock = (activo.version_lock or 1) + 1
                    activo.fecha_actualizacion = datetime.now()
                    activos_actualizados += 1

        db.commit()
        db.refresh(orden)

        folio = orden.folio
        return EntregaConfirmacionResponse(
            id_orden=orden.id_orden,
            folio=folio,
            estado_orden=orden.estado_orden,
            mensaje="¡Entrega en tienda confirmada exitosamente! Orden actualizada a Completada.",
            activos_finalizados=activos_actualizados,
            fecha_entrega=datetime.now().isoformat(),
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al confirmar la entrega en tienda: {str(e)}"
        )


@router.patch(
    "/despachos/{id_despacho}/enviar",
    response_model=DespachoEnvioResponse,
    status_code=200,
    summary="Marcar Despacho como Enviado (Cierre de Ciclo)",
)
def marcar_despacho_enviado(
    id_despacho: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    despacho = db.query(Despacho).filter(Despacho.id_despacho == id_despacho).first()
    if not despacho:
        raise HTTPException(status_code=404, detail="Registro de despacho no encontrado.")

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == despacho.id_orden).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden asociada al despacho no encontrada.")

    if despacho.estado_despacho == "Enviado" or orden.estado_orden == "Despachada":
        folio = orden.folio
        return DespachoEnvioResponse(
            id_despacho=despacho.id_despacho,
            id_orden=orden.id_orden,
            folio=folio,
            estado_despacho=despacho.estado_despacho,
            estado_orden=orden.estado_orden,
            mensaje=f"¡Despacho #{str(despacho.id_despacho)[:8].upper()} ya se encontraba marcado como Enviado!",
            activos_finalizados=0,
            fecha_envio=datetime.now().isoformat(),
        )

    detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
    activos_sin_imprimir = []
    for d in detalles:
        if d.id_activo:
            act = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
            if act and not act.qr_impreso:
                activos_sin_imprimir.append(act.sku_qr_fisico or str(act.id_activo)[:8])

    if activos_sin_imprimir:
        raise HTTPException(
            status_code=400,
            detail=f"No se puede despachar el envío. Las siguientes piezas no tienen su código QR impreso: {', '.join(activos_sin_imprimir)}. Imprima la etiqueta antes de despachar."
        )

    try:
        despacho.estado_despacho = "Enviado"
        despacho.fecha_actualizacion = datetime.now()

        orden.estado_orden = "Despachada"
        orden.fecha_actualizacion = datetime.now()

        estado_final = db.query(Estado_Activo).filter(
            Estado_Activo.nombre_estado.in_(["Entregado", "Finalizado"])
        ).first()
        if not estado_final:
            estado_final = Estado_Activo(id_estado=6, nombre_estado="Entregado")
            db.add(estado_final)
            db.flush()

        detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
        activos_actualizados = 0

        for d in detalles:
            d.estado_preparacion = "Listo"
            d.fecha_preparacion = datetime.now()
            if d.id_activo:
                activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                if activo:
                    activo.id_estado = estado_final.id_estado
                    activo.ubicacion_pasillo = None
                    activo.ubicacion_pallet = None
                    activo.ubicacion_galpon = None
                    activo.observacion_estado = f"Despachado con transporte '{despacho.empresa_transporte or 'Externo'}' - Orden #{str(orden.id_orden)[:8].upper()}"
                    activo.version_lock = (activo.version_lock or 1) + 1
                    activo.fecha_actualizacion = datetime.now()
                    activos_actualizados += 1

        db.commit()
        db.refresh(despacho)
        db.refresh(orden)

        folio = orden.folio
        return DespachoEnvioResponse(
            id_despacho=despacho.id_despacho,
            id_orden=orden.id_orden,
            folio=folio,
            estado_despacho=despacho.estado_despacho,
            estado_orden=orden.estado_orden,
            mensaje=f"¡Despacho #{str(despacho.id_despacho)[:8].upper()} marcado como Enviado exitosamente!",
            activos_finalizados=activos_actualizados,
            fecha_envio=datetime.now().isoformat(),
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al marcar despacho como enviado: {str(e)}"
        )


@router.patch(
    "/despachos/{id_despacho}/estado",
    response_model=DespachoActualizarEstadoResponse,
    status_code=200,
    summary="Actualizar Estado del Despacho (Independiente del estado de la orden)",
)
def actualizar_estado_despacho(
    id_despacho: uuid.UUID,
    payload: DespachoActualizarEstadoRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Actualiza exclusivamente el estado logístico del despacho ('Por Enviar' o 'Enviado').
    REGLA: No altera el estado de la orden (Orden_Venta.estado_orden) ni libera activos en bodega.
    La barrera de salida sigue siendo la única que completa la orden.
    """
    despacho = db.query(Despacho).filter(Despacho.id_despacho == id_despacho).first()
    if not despacho:
        raise HTTPException(status_code=404, detail="Registro de despacho no encontrado.")

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == despacho.id_orden).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden asociada al despacho no encontrada.")

    nuevo_estado = payload.nuevo_estado.strip()
    if nuevo_estado.lower() in ["enviado", "enviada"]:
        estado_normalizado = "Enviado"
    elif nuevo_estado.lower() in ["por enviar", "pendiente", "por_enviar"]:
        estado_normalizado = "Por Enviar"
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Estado de despacho '{nuevo_estado}' no válido. Opciones permitidas: 'Por Enviar', 'Enviado'."
        )

    if despacho.estado_despacho == estado_normalizado:
        folio = orden.folio
        return DespachoActualizarEstadoResponse(
            id_despacho=despacho.id_despacho,
            id_orden=orden.id_orden,
            folio=folio,
            estado_despacho=despacho.estado_despacho,
            estado_orden=orden.estado_orden,
            mensaje=f"Estado de despacho ya se encontraba como '{despacho.estado_despacho}'.",
            fecha_actualizacion=datetime.now().isoformat(),
        )

    try:
        despacho.estado_despacho = estado_normalizado
        despacho.fecha_actualizacion = datetime.now()
        db.commit()
        db.refresh(despacho)

        folio = orden.folio
        return DespachoActualizarEstadoResponse(
            id_despacho=despacho.id_despacho,
            id_orden=orden.id_orden,
            folio=folio,
            estado_despacho=despacho.estado_despacho,
            estado_orden=orden.estado_orden,
            mensaje=f"Estado de despacho actualizado a '{despacho.estado_despacho}'.",
            fecha_actualizacion=datetime.now().isoformat(),
        )
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al actualizar estado de despacho: {str(e)}"
        )


@router.post(
    "/{id_orden}/pagar",
    response_model=OrdenPagoResponse,
    status_code=status.HTTP_200_OK,
    summary="Confirmar Pago de Orden y Generar QR Transaccional (HU-3.6)",
    description="Procesa la confirmación de pago por parte de la cajera. "
                "Crea el registro en Transaccion_Pago, liquida el monto pendiente, "
                "actualiza la orden a 'Pagada', asigna la cajera y genera el código "
                "QR transaccional único para el handshake con bodega."
)
@router.post(
    "/{id_orden}/pagar/",
    response_model=OrdenPagoResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False
)
def pagar_orden(
    id_orden: uuid.UUID,
    pago_in: Optional[OrdenPagoRequest] = None,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_caja_role),
):
    """
    Motor Transaccional de Pago y Generación de QR (ACID):
    1. Bloqueo y verificación de existencia de la orden.
    2. Validaciones de negocio:
       - No permite pagar órdenes en estado 'Pagada', 'Completada' o 'Anulada'.
       - Valida que la orden tenga saldo pendiente y que esté en estado 'Reservada'.
    3. Transacción atómica:
       - Generación del hash criptográfico único `qr_transaccional_salida`.
       - Registro de la transacción en la tabla `Transaccion_Pago`.
       - Actualización de `Orden_Venta`: estado_orden='Pagada', monto_pendiente=0, id_cajera, qr_transaccional_salida.
    4. Commit y emisión de respuesta para la App del Vendedor y habilitación en Bodega.
    """
    if pago_in is None:
        pago_in = OrdenPagoRequest()

    user_ident = f"{current_user.nombres} {current_user.apellidos or ''}".strip()
    print(f"\n💳 [PAGO] Iniciando procesamiento de pago para orden ID: {id_orden} por usuario: {user_ident} ({current_user.email})")

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        print(f"❌ [PAGO] Error: Orden con ID '{id_orden}' no encontrada.")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Orden con ID '{id_orden}' no encontrada."
        )

    # Validación de estados
    if orden.estado_orden in ["Pagada", "Completada"]:
        print(f"⚠️ [PAGO] Rechazo: La orden {id_orden} ya se encuentra en estado '{orden.estado_orden}'.")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden ya se encuentra en estado '{orden.estado_orden}' y cuenta con pago confirmado."
        )

    if orden.estado_orden == "Anulada":
        print(f"⚠️ [PAGO] Rechazo: La orden {id_orden} está 'Anulada'.")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No se puede registrar un pago en una orden que ha sido 'Anulada'."
        )

    if orden.estado_orden != "Reservada":
        print(f"⚠️ [PAGO] Rechazo: Estado inválido '{orden.estado_orden}'.")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"No se puede pagar una orden en estado '{orden.estado_orden}'. Debe estar en estado 'Reservada'."
        )

    if orden.monto_pendiente <= 0:
        print(f"⚠️ [PAGO] Rechazo: La orden {id_orden} no tiene saldo pendiente (monto_pendiente={orden.monto_pendiente}).")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La orden no tiene saldo pendiente por pagar."
        )

    try:
        monto_a_pagar = pago_in.monto if pago_in.monto is not None else orden.monto_pendiente
        if monto_a_pagar <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El monto a pagar debe ser mayor a 0."
            )

        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)

        # 1. Registrar la transacción de pago en PostgreSQL
        nuevo_pago = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=orden.id_orden,
            monto=monto_a_pagar,
            metodo_pago=pago_in.metodo_pago or "Efectivo",
            estado_pago="Procesado",
            fecha_pago=now_utc,
        )
        db.add(nuevo_pago)
        print(f"📝 [PAGO] Registro de Transaccion_Pago creado: ID {nuevo_pago.id_pago} - Monto: ${monto_a_pagar} ({nuevo_pago.metodo_pago})")

        # 2. Actualizar la cabecera de la orden
        nuevo_saldo = max(0, orden.monto_pendiente - monto_a_pagar)
        orden.monto_pendiente = nuevo_saldo
        orden.id_cajera = current_user.id_usuario
        orden.fecha_actualizacion = now_utc

        detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == orden.id_orden).all()
        tiene_activo_fisico = any(d.id_activo is not None for d in detalles)

        despacho_asociado = db.query(Despacho).filter(
            Despacho.id_orden == orden.id_orden
        ).first()
        despacho_pendiente = despacho_asociado if (despacho_asociado and despacho_asociado.estado_despacho == "Por Enviar") else None

        if nuevo_saldo == 0:
            if tiene_activo_fisico:
                orden.estado_orden = "Pagada"
                token_entropy = uuid.uuid4().hex[:12].upper()
                qr_token = f"TX-QR-{str(orden.id_orden)[:8].upper()}-{token_entropy}"
                orden.qr_transaccional_salida = qr_token
                print(f"🔑 [PAGO] QR Transaccional generado: {qr_token}")
                # En orden mixta, los misceláneos de mesón quedan listos inmediatamente
                for d in detalles:
                    if d.id_activo is None:
                        d.estado_preparacion = "Listo"
                        d.fecha_preparacion = now_utc
            else:
                orden.qr_transaccional_salida = None
                for d in detalles:
                    d.estado_preparacion = "Listo"
                    d.fecha_preparacion = now_utc

                # Si es una venta online (vendedor online o tiene responsable asignado),
                # o requiere despacho/retiro en sucursal con entrega física pendiente:
                # debe quedar en 'Pagada' para que el responsable en sucursal la vea
                # en 'Entregas y Envíos' y pueda marcar la entrega física cuando el cliente retire.
                es_pendiente_entrega = False
                if orden.id_vendedor_asignado is not None or despacho_asociado is not None:
                    es_pendiente_entrega = True
                else:
                    v_creador = db.query(Usuario).filter(Usuario.id_usuario == orden.id_vendedor).first()
                    if v_creador and v_creador.id_rol == 7:
                        es_pendiente_entrega = True

                if es_pendiente_entrega:
                    orden.estado_orden = "Pagada"
                    print("📦 [PAGO] Orden con entrega/despacho pendiente de misceláneos: queda en 'Pagada'.")
                else:
                    orden.estado_orden = "Completada"
                    print("✅ [PAGO] Orden presencial de solo misceláneos saldada: completada automáticamente.")
        else:
            orden.estado_orden = "Reservada"
            orden.qr_transaccional_salida = None

        # 3. Actualizar los repuestos físicos inventariados a estado 'Vendido' (ID 3) si está pagada
        if orden.estado_orden == "Pagada":
            estado_vendido = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
            if not estado_vendido:
                estado_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
                db.add(estado_vendido)
                db.flush()

            activos_vendidos = 0
            for d in detalles:
                if d.id_activo:
                    activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                    if activo:
                        activo.id_estado = estado_vendido.id_estado
                        activo.version_lock = (activo.version_lock or 1) + 1
                        activo.fecha_actualizacion = now_utc
                        activos_vendidos += 1

            print(f"📦 [PAGO] {activos_vendidos} repuesto(s) físico(s) actualizados a estado 'Vendido' (ID {estado_vendido.id_estado}).")

        # 4. Confirmación atómica ACID
        db.commit()
        db.refresh(orden)
        db.refresh(nuevo_pago)

        print(f"✅ [PAGO] Pago procesado exitosamente para orden #{str(orden.id_orden)[:8].upper()}. "
              f"Estado: {orden.estado_orden}, Cajera: {user_ident}, Saldo pendiente: ${orden.monto_pendiente}")

        return OrdenPagoResponse(
            id_orden=orden.id_orden,
            numero_orden=orden.numero_orden,
            folio=orden.folio,
            id_pago=nuevo_pago.id_pago,
            estado_orden=orden.estado_orden,
            total_venta=orden.total_venta,
            monto_pagado=nuevo_pago.monto,
            monto_pendiente=orden.monto_pendiente,
            metodo_pago=nuevo_pago.metodo_pago,
            qr_transaccional_salida=orden.qr_transaccional_salida,
            id_cajera=orden.id_cajera,
            mensaje=(
                "Pago registrado exitosamente. Orden completada y repuestos misceláneos entregados en mostrador."
                if orden.estado_orden == "Completada"
                else (
                    "Pago registrado exitosamente. Código QR transaccional emitido para entrega en bodega."
                    if orden.qr_transaccional_salida
                    else "Pago registrado exitosamente."
                )
            ),
            fecha_pago=nuevo_pago.fecha_pago.isoformat() if nuevo_pago.fecha_pago else datetime.now().isoformat(),
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        print(f"💥 [PAGO] Error crítico durante la transacción de pago: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en la transacción de pago de la orden: {str(e)}"
        )


@router.post(
    "/{id_orden}/anular",
    response_model=OrdenAnulacionResponse,
    summary="Anular Orden, Reversar Pagos y Generar Logística Inversa (SPEC-HU-TAREA-4)",
    description="Anula una orden en el Mesón de Ventas, propaga la reversa de transacciones de pago "
                "y genera automáticamente tareas de reingreso (Logística Inversa) para PDA Bodega."
)
def anular_orden_post(
    id_orden: uuid.UUID,
    payload: Optional[AnularOrdenRequest] = None,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    if current_user.id_rol == 8:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: El perfil de Auditoría no posee permisos para anular órdenes de venta."
        )

    rol_nombre = (current_user.nombre_rol or "").lower()
    es_vendedor_o_admin = current_user.id_rol in [2, 4, 5, 6, 7] or (
        "vendedor" in rol_nombre or "admin" in rol_nombre or "jefe" in rol_nombre or "gerente" in rol_nombre
    )
    if not es_vendedor_o_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tienes permisos de ventas o administración para anular órdenes."
        )

    # Validación Poka-Yoke: Motivo y observación obligatoria (>= 10 chars)
    motivo_final = (payload.motivo or payload.motivo_anulacion) if payload else None
    observacion_final = (payload.observacion or payload.observacion_anulacion) if payload else None

    if not motivo_final or not motivo_final.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El motivo de anulación es obligatorio."
        )
    if not observacion_final or len(observacion_final.strip()) < 10:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La justificación u observación debe contener al menos 10 caracteres explicativos."
        )

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Orden con ID '{id_orden}' no encontrada."
        )

    if orden.estado_orden == "Anulada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"La orden #{str(orden.id_orden)[:8].upper()} ya se encuentra anulada."
        )

    if orden.estado_orden == "Completada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"No es posible anular la orden #{str(orden.id_orden)[:8].upper()} porque ya fue entregada/completada."
        )

    try:
        # Paso A: Cambiar estado de la orden a 'Anulada' y persistir auditoría forense
        orden.estado_orden = "Anulada"
        orden.monto_pendiente = 0
        orden.motivo_anulacion = motivo_final.strip()
        orden.observacion_anulacion = observacion_final.strip()
        orden.id_usuario_anulacion = current_user.id_usuario
        orden.fecha_anulacion = datetime.now(timezone.utc)
        orden.fecha_actualizacion = datetime.now(timezone.utc)

        # Paso B: Reversar pagos asociados
        pagos = db.query(Transaccion_Pago).filter(Transaccion_Pago.id_orden == id_orden).all()
        pagos_reversados = 0
        monto_reversado = 0
        for pago in pagos:
            if pago.estado_pago != "Anulado":
                monto_reversado += int(pago.monto or 0)
                pago.estado_pago = "Anulado"
                pagos_reversados += 1

        # Paso C: Obtener activos físicos de la orden para cola de reingreso
        detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == id_orden).all()
        activos_afectados = 0

        estado_disponible = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Disponible").first()
        if not estado_disponible:
            estado_disponible = Estado_Activo(id_estado=1, nombre_estado="Disponible")
            db.add(estado_disponible)
            db.flush()

        for d in detalles:
            if d.id_activo:
                activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                if activo:
                    activo.id_estado = estado_disponible.id_estado
                    activo.version_lock = (activo.version_lock or 1) + 1
                    activo.fecha_actualizacion = datetime.now(timezone.utc)
                    activos_afectados += 1
                d.estado_preparacion = "Reingreso Pendiente"

        db.commit()
        db.refresh(orden)

        # Disparar alerta asíncrona a Telegram para Gerencia (no bloqueante)
        nombre_usuario = f"{current_user.nombres} {current_user.apellidos}".strip()
        background_tasks.add_task(
            TelegramService.notificar_orden_anulada,
            folio=orden.folio,
            total_venta=orden.total_venta,
            usuario_nombre=nombre_usuario,
            rol_nombre=current_user.nombre_rol or "Vendedor",
            motivo_anulacion=motivo_final,
            observacion_anulacion=observacion_final,
            cantidad_items_liberados=activos_afectados,
        )

        mensaje = "Orden anulada, pagos reversados y tareas de reingreso generadas"
        return OrdenAnulacionResponse(
            id_orden=orden.id_orden,
            estado_orden=orden.estado_orden,
            mensaje=mensaje,
            msg=mensaje,
            activos_liberados=activos_afectados,
            pagos_reversados=pagos_reversados,
            monto_reversado=monto_reversado,
            motivo_anulacion=orden.motivo_anulacion,
            observacion_anulacion=orden.observacion_anulacion,
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al anular la orden: {str(e)}"
        )


@router.patch(
    "/{id_orden}/anular",
    response_model=OrdenAnulacionResponse,
    summary="Anular Orden y Liberar Stock Directo (HU-3.5 Retrocompatibilidad)",
    description="Anula una orden en estado 'Reservada' y devuelve repuestos a 'Disponible'."
)
def anular_orden_patch(
    id_orden: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    if current_user.id_rol == 8:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: El perfil de Auditoría no posee permisos para anular órdenes de venta."
        )

    rol_nombre = (current_user.nombre_rol or "").lower()
    es_vendedor_o_admin = current_user.id_rol in [2, 4, 5, 6, 7] or (
        "vendedor" in rol_nombre or "admin" in rol_nombre or "jefe" in rol_nombre or "gerente" in rol_nombre
    )
    if not es_vendedor_o_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tienes permisos de ventas o administración para anular órdenes."
        )

    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Orden con ID '{id_orden}' no encontrada."
        )

    if orden.estado_orden != "Reservada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Solo se pueden anular órdenes en estado 'Reservada' (Pendientes de pago). "
                   f"La orden actual está en estado '{orden.estado_orden}'."
        )

    try:
        orden.estado_orden = "Anulada"
        orden.monto_pendiente = 0
        orden.fecha_actualizacion = datetime.now(timezone.utc)

        estado_disponible = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Disponible").first()
        if not estado_disponible:
            estado_disponible = Estado_Activo(id_estado=1, nombre_estado="Disponible")
            db.add(estado_disponible)
            db.flush()

        detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == id_orden).all()
        activos_liberados = 0

        for d in detalles:
            if d.id_activo:
                activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == d.id_activo).first()
                if activo:
                    activo.id_estado = estado_disponible.id_estado
                    activo.version_lock = (activo.version_lock or 1) + 1
                    activos_liberados += 1
                d.estado_preparacion = "Reingreso Pendiente"

        db.commit()
        db.refresh(orden)

        mensaje = "Orden anulada exitosamente. Los repuestos inventariados han sido devueltos al catálogo como disponibles."
        return OrdenAnulacionResponse(
            id_orden=orden.id_orden,
            estado_orden=orden.estado_orden,
            mensaje=mensaje,
            msg=mensaje,
            activos_liberados=activos_liberados,
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al anular la orden: {str(e)}"
        )


@router.patch(
    "/{id_orden}/reasignar-vendedor",
    response_model=ReasignarVendedorResponse,
    summary="Reasignar Titularidad Comercial de una Orden a otro Vendedor",
    description="Permite que el vendedor titular actual (o un Administrador / Jefe de Ventas) "
                "transfiera la titularidad comercial de una orden a otro vendedor activo de la empresa.",
)
def reasignar_vendedor_orden(
    id_orden: uuid.UUID,
    payload: ReasignarVendedorRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Orden con ID '{id_orden}' no encontrada."
        )

    if orden.estado_orden and orden.estado_orden.lower() == "anulada":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No es posible reasignar una orden que se encuentra Anulada."
        )

    # Validar permisos: Propietario de la venta O rol jerárquico (Admin: 1, Gerente: 5, Jefe Ventas: 6)
    rol_nombre = (current_user.nombre_rol or "").lower()
    es_propietario = str(orden.id_vendedor) == str(current_user.id_usuario)
    es_jefatura = current_user.id_rol in [1, 5, 6] or ("admin" in rol_nombre or "jefe" in rol_nombre or "gerente" in rol_nombre)

    if not (es_propietario or es_jefatura):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tienes permisos para reasignar esta orden. Solo el vendedor titular o una jefatura puede transferirla."
        )

    if str(orden.id_vendedor) == str(payload.id_nuevo_vendedor):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La orden ya está asignada a este vendedor."
        )

    # Validar que el nuevo vendedor exista, esté activo y pertenezca a un rol comercial (2: Mesón, 6: Jefe Ventas, 7: Online, 1: Admin, 5: Gerente)
    nuevo_vendedor = db.query(Usuario).filter(Usuario.id_usuario == payload.id_nuevo_vendedor).first()
    if not nuevo_vendedor or nuevo_vendedor.estado != "Activo":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El vendedor seleccionado no existe o no se encuentra activo."
        )

    vendedor_anterior = db.query(Usuario).filter(Usuario.id_usuario == orden.id_vendedor).first()
    nombre_anterior = f"{vendedor_anterior.nombres} {vendedor_anterior.apellidos or ''}".strip() if vendedor_anterior else "Desconocido"
    nombre_nuevo = f"{nuevo_vendedor.nombres} {nuevo_vendedor.apellidos or ''}".strip()

    id_anterior = orden.id_vendedor
    orden.id_vendedor = nuevo_vendedor.id_usuario
    orden.fecha_actualizacion = datetime.now(timezone.utc)

    # Si se reasigna al usuario comercial Limache, preservar al usuario actual como emisor/asignado operativo
    if (nuevo_vendedor.email and nuevo_vendedor.email.lower() == "limache@cresal.cl") or (nuevo_vendedor.apellidos and "limache" in nuevo_vendedor.apellidos.lower()):
        orden.id_vendedor_asignado = current_user.id_usuario

    db.commit()
    db.refresh(orden)

    print(
        f"🔄 [REASIGNACIÓN] Orden {orden.folio} reasignada de '{nombre_anterior}' a '{nombre_nuevo}' "
        f"por usuario {current_user.nombres} ({current_user.email}). Motivo: {payload.motivo or 'Sin motivo'}"
    )

    return ReasignarVendedorResponse(
        id_orden=orden.id_orden,
        folio=orden.folio,
        id_vendedor_anterior=id_anterior,
        nombre_vendedor_anterior=nombre_anterior,
        id_nuevo_vendedor=nuevo_vendedor.id_usuario,
        nombre_nuevo_vendedor=nombre_nuevo,
        mensaje=f"Orden {orden.folio} reasignada exitosamente a {nombre_nuevo}."
    )


@router.patch(
    "/{id_orden}/instrucciones",
    response_model=InstruccionesUpdateResponse,
    summary="Actualizar Instrucciones Técnicas para Bodega",
    description="Modifica las notas de preparación técnica asociadas a los detalles de una orden."
)
def actualizar_instrucciones_bodega(
    id_orden: uuid.UUID,
    payload: InstruccionesUpdateRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    orden = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
    if not orden:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Orden con ID '{id_orden}' no encontrada."
        )

    if orden.estado_orden in ["Anulada", "Completada"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"No se pueden modificar instrucciones en una orden con estado '{orden.estado_orden}'."
        )

    try:
        query_detalles = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == id_orden)

        if payload.id_detalle:
            query_detalles = query_detalles.filter(Detalle_Orden.id_detalle == payload.id_detalle)
            detalle = query_detalles.first()
            if not detalle:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Detalle con ID '{payload.id_detalle}' no encontrado en esta orden."
                )
            if detalle.id_activo is not None:
                detalle.notas_preparacion = payload.notas_preparacion.strip()
            detalles_actualizados = 1
        else:
            detalles = query_detalles.all()
            if not detalles:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="La orden no contiene líneas de detalle para actualizar."
                )
            for d in detalles:
                if d.id_activo is not None:
                    d.notas_preparacion = payload.notas_preparacion.strip()
            detalles_actualizados = len(detalles)

        orden.fecha_actualizacion = datetime.now()
        db.commit()

        return InstruccionesUpdateResponse(
            id_orden=orden.id_orden,
            mensaje="Instrucciones técnicas de preparación actualizadas exitosamente.",
            notas_preparacion=payload.notas_preparacion.strip(),
            detalles_actualizados=detalles_actualizados,
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al actualizar las instrucciones de la orden: {str(e)}"
        )


@router.get(
    "/{id_orden}",
    summary="Obtener Detalle de Orden de Venta",
    description=(
        "Consulta la información completa de una orden específica por su "
        "UUID incluyendo pagos y detalle de piezas."
    )
)
def obtener_orden(
    id_orden: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    orden = db.query(Orden_Venta).filter(
        Orden_Venta.id_orden == id_orden
    ).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada")

    cliente = db.query(Cliente).filter(
        Cliente.id_cliente == orden.id_cliente
    ).first()
    detalles = db.query(Detalle_Orden).filter(
        Detalle_Orden.id_orden == id_orden
    ).all()
    despacho = db.query(Despacho).filter(
        Despacho.id_orden == id_orden
    ).first()
    pagos = (
        db.query(Transaccion_Pago)
        .filter(Transaccion_Pago.id_orden == id_orden)
        .order_by(Transaccion_Pago.fecha_pago.asc())
        .all()
    )
    vendedor = db.query(Usuario).filter(
        Usuario.id_usuario == orden.id_vendedor
    ).first()
    cajera = (
        db.query(Usuario).filter(Usuario.id_usuario == orden.id_cajera).first()
        if orden.id_cajera else None
    )
    sucursal = (
        db.query(Sucursal)
        .filter(Sucursal.id_sucursal == orden.id_sucursal)
        .first()
        if orden.id_sucursal else None
    )

    detalles_res = []
    for d in detalles:
        sku_val = None
        if d.id_activo:
            act = db.query(Activo_Inventariado).filter(
                Activo_Inventariado.id_activo == d.id_activo
            ).first()
            if act:
                sku_val = act.sku_qr_fisico
        detalles_res.append({
            "id_detalle": d.id_detalle,
            "id_activo": d.id_activo,
            "sku": sku_val,
            "descripcion_manual": d.descripcion_manual,
            "notas_preparacion": d.notas_preparacion,
            "cantidad": d.cantidad,
            "precio_unitario": d.precio_unitario,
            "precio_final": d.precio_final,
            "preparacion_lista": d.preparacion_lista,
            "estado_preparacion": d.estado_preparacion or "Pendiente",
        })

    pagos_res = [
        {
            "id_pago": p.id_pago,
            "metodo_pago": p.metodo_pago,
            "monto": p.monto,
            "estado_pago": p.estado_pago or "Procesado",
            "fecha_pago": p.fecha_pago.isoformat() if p.fecha_pago else None,
        }
        for p in pagos
    ]

    nom_vend = (
        f"{vendedor.nombres} {vendedor.apellidos or ''}".strip()
        if vendedor else "Vendedor General"
    )
    if cajera:
        nom_caja = f"{cajera.nombres} {cajera.apellidos or ''}".strip()
    elif orden.estado_orden and orden.estado_orden.lower() == "anulada":
        nom_caja = "Sin cobro"
    elif pagos or (orden.estado_orden and orden.estado_orden.lower() in ["completada", "pagada", "entregada"]):
        cajera_suc = db.query(Usuario).filter(Usuario.id_rol == 3, Usuario.id_sucursal == orden.id_sucursal, Usuario.estado == "Activo").first()
        if not cajera_suc:
            cajera_suc = db.query(Usuario).filter(Usuario.id_rol == 3, Usuario.estado == "Activo").first()
        nom_caja = f"{cajera_suc.nombres} {cajera_suc.apellidos or ''}".strip() if cajera_suc else "Caja"
    else:
        nom_caja = "Pendiente de cobro"
    nom_suc = (
        sucursal.nombre_sucursal
        if sucursal else f"Sucursal {orden.id_sucursal}"
    )

    return {
        "id_orden": orden.id_orden,
        "folio": orden.folio,
        "estado_orden": orden.estado_orden,
        "total_venta": orden.total_venta,
        "monto_pendiente": orden.monto_pendiente,
        "qr_transaccional_salida": orden.qr_transaccional_salida,
        "fecha_creacion": (
            orden.fecha_creacion.isoformat()
            if orden.fecha_creacion else None
        ),
        "vendedor_nombre": nom_vend,
        "cajera_nombre": nom_caja,
        "sucursal_nombre": nom_suc,
        "cliente": {
            "rut": cliente.rut_cliente if cliente else None,
            "nombres": cliente.nombres if cliente else None,
            "apellidos": cliente.apellidos if cliente else None,
            "telefono": cliente.telefono if cliente else None,
        } if cliente else None,
        "despacho": {
            "direccion_envio": despacho.direccion_envio,
            "receptor_nombres": despacho.receptor_nombres,
            "receptor_rut": despacho.receptor_rut,
            "receptor_telefono": despacho.receptor_telefono,
            "estado_despacho": despacho.estado_despacho,
            "empresa_transporte": despacho.empresa_transporte,
            "costo_envio": despacho.costo_envio,
        } if despacho else None,
        "detalles": detalles_res,
        "pagos": pagos_res,
        "pagos_aplicados": pagos_res,
    }


# ==========================================
# ENDPOINT CHECKOUT WIZARD & RESERVAS BACKORDER (SPEC-HU-05)
# ==========================================

@router.post(
    "/checkout-wizard",
    response_model=CheckoutWizardResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Procesar Checkout por Pasos (Wizard) y Reservas Backorder (SPEC-HU-05)",
    description="Procesa de forma atómica (ACID) la creación de la orden de venta, "
                "reserva de repuestos físicos de inventario, registro de reservas por encargo (Backorder) "
                "y datos de despacho a domicilio."
)
def checkout_wizard(
    request: CheckoutWizardRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    # 1. Control de Acceso RBAC: Solo roles de Ventas, Jefatura o Administración
    rol_nombre = (current_user.nombre_rol or "").lower()
    es_vendedor_o_admin = current_user.id_rol in [2, 4, 5, 6, 7] or (
        "vendedor" in rol_nombre or "admin" in rol_nombre or "jefe" in rol_nombre or "gerente" in rol_nombre
    )
    if not es_vendedor_o_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Solo el personal de Ventas o Administración puede procesar el checkout."
        )

    # 1.1 Validación de Horario Operativo y Periodo de Gracia por Rol
    validar_horario_operativo_ordenes(current_user, request.items_inventariados, db)

    # 2. Validar o Crear Cliente (Micro-CRM / Consumidor Final)
    cliente = None
    if request.id_cliente:
        cliente = db.query(Cliente).filter(Cliente.id_cliente == request.id_cliente).first()

    if not cliente and request.cliente:
        rut_limpio = request.cliente.rut_cliente.strip()
        rut_norm = rut_limpio.replace(".", "").replace("-", "").upper()
        es_consumidor_final = rut_norm in ["66666666", "6666666"] or "CONSUMIDOR" in request.cliente.nombres.upper()

        if es_consumidor_final:
            cliente = db.query(Cliente).filter(
                Cliente.rut_cliente.in_(["6.666.666-6", "66666666-6", "6666666-6"])
            ).first()
            if not cliente:
                cliente = Cliente(
                    id_cliente=uuid.uuid4(),
                    rut_cliente="6.666.666-6",
                    nombres="Consumidor",
                    apellidos="Final",
                    consentimiento_legal=True,
                    estado="Activo",
                )
                db.add(cliente)
                db.flush()
        else:
            cliente = db.query(Cliente).filter(
                (Cliente.rut_cliente == rut_limpio) | (Cliente.rut_cliente == rut_limpio.replace(".", ""))
            ).first()
            if not cliente:
                id_comuna_cli = None
                if request.cliente.comuna:
                    com_cli = db.query(Comuna).filter(Comuna.nombre_comuna.ilike(request.cliente.comuna.strip())).first()
                    if com_cli:
                        id_comuna_cli = com_cli.id_comuna
                cliente = Cliente(
                    id_cliente=uuid.uuid4(),
                    rut_cliente=rut_limpio,
                    nombres=request.cliente.nombres.strip(),
                    apellidos=request.cliente.apellidos.strip(),
                    telefono=request.cliente.telefono.strip() if request.cliente.telefono else None,
                    correo=request.cliente.correo.strip() if request.cliente.correo else None,
                    id_comuna=id_comuna_cli,
                    consentimiento_legal=request.cliente.consentimiento_legal,
                    estado="Activo",
                )
                db.add(cliente)
                db.flush()
            else:
                cliente.nombres = request.cliente.nombres.strip()
                cliente.apellidos = request.cliente.apellidos.strip()
                if request.cliente.telefono:
                    cliente.telefono = request.cliente.telefono.strip()
                if request.cliente.correo:
                    cliente.correo = request.cliente.correo.strip()

    if not cliente or cliente.estado != "Activo":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="El cliente especificado no existe o se encuentra inactivo."
        )

    # Validar que al menos haya 1 ítem (inventariado, manual o reserva backorder)
    num_inv = len(request.items_inventariados or [])
    num_man = len(request.items_manuales or [])
    num_res = len(request.reservas or [])

    if num_inv == 0 and num_man == 0 and num_res == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La orden debe contener al menos un producto inventariado, ítem manual o reserva por encargo."
        )

    # 2.1 Restricción Venta en Verde: Prohibir Consumidor Final y exigir datos de contacto
    if num_res > 0:
        rut_cliente_norm = (cliente.rut_cliente or "").replace(".", "").replace("-", "").strip().upper()
        nombre_cliente_norm = f"{cliente.nombres or ''} {cliente.apellidos or ''}".upper()
        if (
            rut_cliente_norm in ["66666666", "6666666", "666666666"]
            or "CONSUMIDOR FINAL" in nombre_cliente_norm
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Las compras bajo la modalidad de Venta en Verde requieren obligatoriamente la identificación del cliente (RUT, nombres y teléfono de contacto). No se permite asignar a Consumidor Final."
            )
        if not cliente.telefono or len(cliente.telefono.strip()) < 8:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Las compras bajo la modalidad de Venta en Verde requieren registrar un teléfono de contacto directo del cliente para coordinar la entrega o retiro."
            )

    # Validar datos de despacho si aplica
    tipo_ent = (request.tipo_entrega or "Retiro").strip()
    es_despacho = "despacho" in tipo_ent.lower()
    es_traslado = "traslado" in tipo_ent.lower()

    if es_despacho:
        if not request.datos_despacho:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Para entrega tipo 'Despacho Domicilio' se requieren los datos de despacho completos."
            )
        comuna_id = request.datos_despacho.id_comuna_destino or 1
        comuna = db.query(Comuna).filter(Comuna.id_comuna == comuna_id).first()
        if not comuna and getattr(request.datos_despacho, "comuna_destino", None):
            comuna = db.query(Comuna).filter(Comuna.nombre_comuna.ilike(request.datos_despacho.comuna_destino.strip())).first()
            if comuna:
                comuna_id = comuna.id_comuna
        if not comuna:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"La comuna destino con ID '{comuna_id}' no existe."
            )
        if not request.datos_despacho.direccion_envio.strip() or not request.datos_despacho.receptor_nombres.strip() or not request.datos_despacho.receptor_rut.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Los campos de dirección, receptor y RUT son obligatorios para el despacho."
            )

    sucursal_id = current_user.id_sucursal or 1
    if es_traslado:
        id_suc_dest = request.id_sucursal_destino or (request.datos_despacho.id_sucursal_destino if request.datos_despacho else (2 if sucursal_id == 1 else 1))
        if id_suc_dest not in [1, 2]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La sucursal de destino no es válida para traslados inter-sucursal (permitidas: 1 Viña del Mar, 2 Limache)."
            )
        if id_suc_dest == sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La sucursal de origen y destino no pueden ser iguales para un traslado."
            )

    try:
        # A. Crear Cabecera de Orden de Venta
        id_orden = uuid.uuid4()

        vendedor_comercial = current_user.id_usuario
        if getattr(request, "id_vendedor_titular", None) is not None:
            if current_user.id_rol not in [1, 2, 5, 6]:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Acceso restringido: Solo el Jefe de Ventas, Vendedor o Administrador puede emitir órdenes a nombre de otro vendedor."
                )
            v_titular = db.query(Usuario).filter(Usuario.id_usuario == request.id_vendedor_titular, Usuario.estado == "Activo").first()
            if not v_titular:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="El vendedor titular seleccionado no existe o no está activo."
                )
            vendedor_comercial = v_titular.id_usuario

        vendedor_asig = request.id_vendedor_asignado
        if request.id_vendedor_titular is not None and (vendedor_asig is None or not str(vendedor_asig).strip()):
            vendedor_asig = current_user.id_usuario
        elif vendedor_asig is None:
            # Si es Vendedora Online (id_rol == 7), None representa "Mesón General" (visible para toda la sucursal en tienda)
            if current_user.id_rol != 7:
                vendedor_asig = current_user.id_usuario

        abono_req_val = request.monto_abono or 0
        if abono_req_val == 0 and request.reservas:
            abono_req_val = sum((r.abono_requerido if getattr(r, "abono_requerido", None) is not None else r.monto_abonado) for r in request.reservas)

        # Si el abono acordado cubre o supera el total de la venta, es un cobro total estándar
        if abono_req_val >= request.total_venta:
            abono_req_val = 0

        desc_val = max(0, getattr(request, "descuento", 0) or 0)
        orden = Orden_Venta(
            id_orden=id_orden,
            id_cliente=cliente.id_cliente,
            id_vendedor=vendedor_comercial,
            id_vendedor_asignado=vendedor_asig,
            id_sucursal=sucursal_id,
            estado_orden="Reservada",
            total_venta=request.total_venta,
            descuento=desc_val,
            monto_pendiente=request.total_venta,
            abono_requerido=abono_req_val,
            fecha_creacion=datetime.now(timezone.utc),
            fecha_actualizacion=datetime.now(timezone.utc)
        )
        db.add(orden)
        db.flush()

        # B. Procesar Ítems Inventariados
        activos_reservados = 0
        for item_inv in (request.items_inventariados or []):
            if isinstance(item_inv, dict):
                act_id = item_inv.get("id_activo") or item_inv.get("id")
                precio_final_custom = item_inv.get("precio_final") or item_inv.get("precio")
                notas_prep = item_inv.get("notas_preparacion") or request.instrucciones_bodega
            elif hasattr(item_inv, "id_activo"):
                act_id = getattr(item_inv, "id_activo")
                precio_final_custom = getattr(item_inv, "precio_final", None)
                notas_prep = getattr(item_inv, "notas_preparacion", None) or request.instrucciones_bodega
            else:
                act_id = item_inv
                precio_final_custom = None
                notas_prep = request.instrucciones_bodega

            if isinstance(act_id, str):
                try:
                    act_id = uuid.UUID(act_id)
                except (ValueError, AttributeError, Exception):
                    pass

            activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == act_id).first()
            if not activo:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"El activo con ID '{act_id}' no fue encontrado en inventario."
                )

            # Validar rango de tasación permitido
            min_permitido = activo.precio_minimo if activo.precio_minimo is not None else (activo.precio_referencia or 0)
            max_permitido = activo.precio_maximo if activo.precio_maximo is not None else (activo.precio_referencia or 0)

            if precio_final_custom is not None:
                p_final = int(precio_final_custom)
            else:
                p_final = activo.precio_referencia or 0

            if min_permitido > 0 or max_permitido > 0:
                if p_final < min_permitido or p_final > max_permitido:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"El precio acordado (${p_final:,}) para el repuesto SKU '{activo.sku_qr_fisico}' se encuentra fuera del rango de tasación permitido (${min_permitido:,} - ${max_permitido:,})."
                    )

            # Permitir si está Disponible (1), Paletizado (7) o Reservado por el mismo vendedor en su carrito (2)
            es_su_reserva = (
                activo.id_estado == 2
                and activo.reservado_por is not None
                and activo.reservado_por == current_user.id_usuario
            )
            if activo.id_estado not in [1, 7] and not es_su_reserva:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"El repuesto SKU '{activo.sku_qr_fisico}' no está disponible para venta (Estado actual ID {activo.id_estado})."
                )

            # Transición a Reservado formal de orden (id_estado = 2, sin TTL de carrito)
            activo.id_estado = 2
            activo.reserva_expira_en = None  # Elimina el TTL para que no caduque a los 15 min si el cliente demora en ir a Caja
            activo.reservado_por = None      # Ya no pertenece a un carrito volátil, ahora pertenece a la orden oficial
            activo.version_lock = (activo.version_lock or 1) + 1
            activo.fecha_actualizacion = datetime.now(timezone.utc)
            activos_reservados += 1

            cat = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == activo.id_categoria).first()
            cat_nombre = cat.nombre_categoria if cat else "Repuesto"
            veh = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first() if activo.id_vehiculo else None
            motor = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == activo.id_activo).first()
            caja = db.query(Detalle_Caja_Cambio).filter(Detalle_Caja_Cambio.id_activo == activo.id_activo).first()

            tec_parts = []
            if motor:
                if motor.cilindrada:
                    tec_parts.append(motor.cilindrada)
                if motor.combustible:
                    tec_parts.append(motor.combustible)
            if caja and caja.transmision_tipo:
                tec_parts.append(caja.transmision_tipo)

            veh_parts = []
            if veh:
                if veh.marca:
                    veh_parts.append(veh.marca)
                if veh.modelo:
                    veh_parts.append(veh.modelo)
                if veh.anio:
                    veh_parts.append(str(veh.anio))

            veh_str = f" - {' '.join(veh_parts)}" if veh_parts else ""
            tec_str = f" ({' • '.join(tec_parts)})" if tec_parts else ""
            desc = f"{cat_nombre}{veh_str}{tec_str}".strip() or f"{cat_nombre} ({activo.sku_qr_fisico})"

            detalle = Detalle_Orden(
                id_detalle=uuid.uuid4(),
                id_orden=orden.id_orden,
                id_activo=activo.id_activo,
                descripcion_manual=desc,
                notas_preparacion=notas_prep,
                cantidad=1,
                precio_unitario=activo.precio_referencia or p_final,
                precio_final=p_final,
                estado_preparacion="Pendiente"
            )
            db.add(detalle)

        # C. Procesar Ítems Manuales (Misceláneos de mesón / venta libre)
        for m in (request.items_manuales or []):
            desc_m = m.get("descripcion", "Ítem Manual")
            cant_m = int(m.get("cantidad", 1))
            p_unit = int(m.get("precio_unitario", 0))
            p_fin = int(m.get("precio_final", p_unit * cant_m))

            detalle_m = Detalle_Orden(
                id_detalle=uuid.uuid4(),
                id_orden=orden.id_orden,
                id_activo=None,
                descripcion_manual=desc_m,
                notas_preparacion=None,
                cantidad=cant_m,
                precio_unitario=p_unit,
                precio_final=p_fin,
                estado_preparacion="Listo"
            )
            db.add(detalle_m)

        # D. Procesar Reservas por Encargo (Backorder / Compras en Verde)
        reservas_creadas = 0
        for r in (request.reservas or []):
            categoria = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == r.id_categoria_requerida).first()
            cat_label = categoria.nombre_categoria if categoria else f"Categoría {r.id_categoria_requerida}"

            abono_res = r.abono_requerido if getattr(r, "abono_requerido", None) is not None else r.monto_abonado
            if (abono_res is None or abono_res == 0) and abono_req_val > 0:
                abono_res = abono_req_val
            reserva_bo = Reservas_Backorder(
                id_reserva=uuid.uuid4(),
                id_cliente=cliente.id_cliente,
                id_vendedor=current_user.id_usuario,
                id_orden=orden.id_orden,
                id_sucursal_registro=sucursal_id,
                id_categoria_requerida=r.id_categoria_requerida,
                marca_requerida=r.marca_requerida.strip(),
                modelo_requerido=r.modelo_requerido.strip(),
                anio_requerido=r.anio_requerido,
                cilindrada_requerida=r.cilindrada_requerida,
                combustible_requerido=r.combustible_requerido,
                transmision_requerida=r.transmision_requerida,
                notas_preparacion=r.notas_preparacion,
                precio_acordado=r.precio_acordado,
                monto_abonado=0,
                abono_requerido=abono_res,
                estado_reserva="Pendiente",
                fecha_creacion=datetime.now(timezone.utc)
            )
            db.add(reserva_bo)
            reservas_creadas += 1

            # Línea de detalle comercial en la orden
            desc_res = f"[RESERVA EN VERDE] {cat_label} - {r.marca_requerida} {r.modelo_requerido}"
            if r.anio_requerido:
                desc_res += f" ({r.anio_requerido})"

            detalle_res = Detalle_Orden(
                id_detalle=uuid.uuid4(),
                id_orden=orden.id_orden,
                id_activo=None,
                descripcion_manual=desc_res,
                notas_preparacion=r.notas_preparacion or f"Reserva por encargo. Abono acordado: ${abono_res:,}".replace(",", "."),
                cantidad=1,
                precio_unitario=r.precio_acordado,
                precio_final=r.precio_acordado,
                estado_preparacion="No Aplica"
            )
            db.add(detalle_res)

        # E. Procesar Despacho a Domicilio o Traslado a otra Sucursal
        despacho_generado = False
        if es_despacho and request.datos_despacho:
            d_data = request.datos_despacho
            despacho = Despacho(
                id_despacho=uuid.uuid4(),
                id_orden=orden.id_orden,
                id_comuna_destino=d_data.id_comuna_destino or 1,
                direccion_envio=d_data.direccion_envio.strip(),
                receptor_nombres=d_data.receptor_nombres.strip(),
                receptor_rut=d_data.receptor_rut.strip(),
                receptor_telefono=d_data.receptor_telefono.strip(),
                empresa_transporte=d_data.empresa_transporte or "Chilexpress",
                costo_envio=0,
                estado_despacho="Por Enviar",
                estado="Activo",
                fecha_creacion=datetime.now(timezone.utc)
            )
            db.add(despacho)
            despacho_generado = True
        elif es_traslado:
            id_suc_dest = request.id_sucursal_destino or (request.datos_despacho.id_sucursal_destino if request.datos_despacho else (2 if sucursal_id == 1 else 1))
            if id_suc_dest not in [1, 2]:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="La sucursal de destino no es válida para traslados inter-sucursal (permitidas: 1 Viña del Mar, 2 Limache)."
                )
            if id_suc_dest == sucursal_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="La sucursal de origen y destino no pueden ser iguales para un traslado."
                )

            nombre_dest = "Viña del Mar" if id_suc_dest == 1 else "Limache"
            rec_rut = (request.datos_despacho.receptor_rut if request.datos_despacho and request.datos_despacho.receptor_rut else cliente.rut_cliente) or "S/R"
            rec_nom = (request.datos_despacho.receptor_nombres if request.datos_despacho and request.datos_despacho.receptor_nombres else f"{cliente.nombres} {cliente.apellidos}".strip()) or "Cliente"
            rec_tel = (request.datos_despacho.receptor_telefono if request.datos_despacho and request.datos_despacho.receptor_telefono else (cliente.telefono or "+56900000000")) or "+56900000000"

            despacho_traslado = Despacho(
                id_despacho=uuid.uuid4(),
                id_orden=orden.id_orden,
                id_comuna_destino=1 if id_suc_dest == 1 else 2,
                direccion_envio=f"Traslado a Sucursal {nombre_dest}",
                receptor_nombres=rec_nom,
                receptor_rut=rec_rut,
                receptor_telefono=rec_tel,
                empresa_transporte="Interno",
                costo_envio=0,
                estado_despacho="Por Enviar",
                estado="Activo",
                fecha_creacion=datetime.now(timezone.utc)
            )
            db.add(despacho_traslado)
            despacho_generado = True

            # Registrar Tracking_Logistico para cada activo inventariado involucrado en el traslado
            for item_inv in (request.items_inventariados or []):
                if isinstance(item_inv, dict):
                    act_id = item_inv.get("id_activo") or item_inv.get("id")
                elif hasattr(item_inv, "id_activo"):
                    act_id = getattr(item_inv, "id_activo")
                else:
                    act_id = item_inv

                if not act_id:
                    continue

                if isinstance(act_id, str):
                    try:
                        act_id = uuid.UUID(act_id)
                    except (ValueError, AttributeError, Exception):
                        pass
                act_item = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == act_id).first()
                if act_item and act_item.id_sucursal_actual != id_suc_dest:
                    tracking = Tracking_Logistico(
                        id_activo=act_item.id_activo,
                        id_sucursal_origen=act_item.id_sucursal_actual,
                        id_sucursal_destino=id_suc_dest,
                        id_usuario_gestor=current_user.id_usuario,
                        id_orden=orden.id_orden,
                        estado_traslado="Pendiente",
                    )
                    db.add(tracking)

        db.commit()
        db.refresh(orden)

        return CheckoutWizardResponse(
            id_orden=orden.id_orden,
            numero_orden=orden.numero_orden,
            folio=orden.folio,
            estado=orden.estado_orden,
            estado_orden=orden.estado_orden,
            total_venta=orden.total_venta,
            descuento=orden.descuento,
            monto_pendiente=orden.monto_pendiente,
            abono_requerido=orden.abono_requerido,
            reservas_generadas=reservas_creadas,
            activos_reservados=activos_reservados,
            despacho_generado=despacho_generado,
            msg="Orden generada exitosamente.",
            mensaje="Orden generada exitosamente."
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al procesar Checkout Wizard: {str(e)}"
        )
