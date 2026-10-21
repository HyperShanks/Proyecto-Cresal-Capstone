# backend/routers/gerencia.py
"""
Router de Gerencia: Dashboard Ejecutivo y Analítica en Tiempo Real (HU-5.1).
Implemento los endpoints de consulta analítica de alto nivel para consolidar
el pulso financiero y la carga operativa de bodega.
"""

from datetime import datetime, time, timezone
from typing import Optional, List
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, and_, func, cast, String
from sqlalchemy.orm import Session

from database import get_db
from models import (
    Usuario,
    Orden_Venta,
    Transaccion_Pago,
    Detalle_Orden,
    Activo_Inventariado,
    Estado_Activo,
    Despacho,
    Cliente,
    Sucursal,
    Categoria_Activo,
    Reservas_Backorder,
)
from core.security import require_gerencia_role, require_gerencia_o_auditor_central
from schemas import (
    KpiFinancieroDTO,
    ResumenPagosDTO,
    DesglosePagoDTO,
    FlujoOperativoDTO,
    BackorderGerenciaItemDTO,
    BackorderGerenciaListResponse,
    BackorderGerenciaKpisDTO,
    SucursalGerenciaDTO,
)

# Inicializo el router con el prefijo /api/v1/gerencia y tag para Swagger
router = APIRouter(
    prefix="/api/v1/gerencia",
    tags=["Gerencia - Dashboard Ejecutivo"],
)

tz_chile = ZoneInfo("America/Santiago")


def calcular_limites_temporales_chile():
    """
    Calculo los límites de inicio y fin de hoy, junto al primer día del mes
    (MTD) en hora local chilena (America/Santiago) y los convierto a UTC.
    """
    ahora_chile = datetime.now(tz_chile)

    # Ventas de hoy: desde 00:00:00 hasta 23:59:59.999999 de hoy en Chile
    inicio_hoy_local = datetime.combine(
        ahora_chile.date(), time.min, tzinfo=tz_chile
    )
    fin_hoy_local = datetime.combine(
        ahora_chile.date(), time.max, tzinfo=tz_chile
    )
    inicio_hoy_utc = (
        inicio_hoy_local.astimezone(timezone.utc).replace(tzinfo=None)
    )
    fin_hoy_utc = (
        fin_hoy_local.astimezone(timezone.utc).replace(tzinfo=None)
    )

    # Acumulado MTD: desde el primer día del mes actual a las 00:00:00
    primer_dia_mes = ahora_chile.date().replace(day=1)
    inicio_mes_local = datetime.combine(
        primer_dia_mes, time.min, tzinfo=tz_chile
    )
    inicio_mes_utc = (
        inicio_mes_local.astimezone(timezone.utc).replace(tzinfo=None)
    )

    return inicio_hoy_utc, fin_hoy_utc, inicio_mes_utc


@router.get(
    "/sucursales",
    response_model=List[SucursalGerenciaDTO],
    summary="Listado de Sucursales Activas para Gerencia",
    description="Retorna las sucursales existentes en el sistema para alternar el filtro multi-sucursal.",
)
def obtener_sucursales_gerencia(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_gerencia_role),
):
    """
    Retorna el catálogo dinámico de sucursales activas en la BD, identificando Casa Matriz.
    """
    sucursales = (
        db.query(Sucursal)
        .filter(Sucursal.estado == "Activo")
        .order_by(Sucursal.id_sucursal)
        .all()
    )
    resultado = []
    for suc in sucursales:
        nombre = suc.nombre_sucursal or f"Sucursal {suc.id_sucursal}"
        # Identificar si es casa matriz por id_sucursal == 1 o por coincidencia en el nombre
        es_matriz = (suc.id_sucursal == 1) or ("matriz" in nombre.lower())
        resultado.append(
            SucursalGerenciaDTO(
                id_sucursal=suc.id_sucursal,
                nombre_sucursal=nombre,
                es_casa_matriz=es_matriz,
            )
        )
    return resultado


@router.get(
    "/dashboard/kpis",
    response_model=KpiFinancieroDTO,
    summary="Métricas Financieras Superiores del Dashboard",
    description="Retorna ventas hoy, transacciones, MTD y ticket promedio.",
)
def obtener_kpis_financieros(
    id_sucursal: Optional[int] = Query(
        None,
        description="ID de sucursal. Si se omite, consolida toda la cadena.",
    ),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_gerencia_o_auditor_central),
):
    """
    Calculo los KPIs financieros en tiempo real.
    Filtro transacciones con estado_pago = 'Procesado' y excluyo anuladas.
    """
    inicio_hoy_utc, fin_hoy_utc, inicio_mes_utc = (
        calcular_limites_temporales_chile()
    )

    # 1. Consulto los pagos procesados de hoy
    query_pagos_hoy = (
        db.query(Transaccion_Pago)
        .outerjoin(Orden_Venta, Transaccion_Pago.id_orden == Orden_Venta.id_orden)
        .outerjoin(Reservas_Backorder, Transaccion_Pago.id_reserva == Reservas_Backorder.id_reserva)
        .filter(
            Transaccion_Pago.estado_pago == "Procesado",
            Transaccion_Pago.fecha_pago.between(inicio_hoy_utc, fin_hoy_utc),
            or_(Orden_Venta.estado_orden.is_(None), Orden_Venta.estado_orden != "Anulada"),
            or_(Reservas_Backorder.estado_reserva.is_(None), Reservas_Backorder.estado_reserva != "Anulada"),
        )
    )
    if id_sucursal is not None:
        query_pagos_hoy = query_pagos_hoy.filter(
            or_(
                Orden_Venta.id_sucursal == id_sucursal,
                Reservas_Backorder.id_sucursal_registro == id_sucursal,
            )
        )

    pagos_hoy = query_pagos_hoy.all()
    ventas_del_dia = sum(p.monto for p in pagos_hoy)

    # Identifico las transacciones pagadas de hoy
    ordenes_hoy_ids = {
        p.id_orden or p.id_reserva for p in pagos_hoy if (p.id_orden is not None or p.id_reserva is not None)
    }
    transacciones_hoy = len(ordenes_hoy_ids)

    # Calculo el ticket promedio de las ventas de hoy
    ticket_promedio = (
        round(float(ventas_del_dia) / float(transacciones_hoy), 2)
        if transacciones_hoy > 0
        else 0.0
    )

    # 2. Consulto el acumulado mensual MTD
    query_mtd = (
        db.query(Transaccion_Pago)
        .outerjoin(Orden_Venta, Transaccion_Pago.id_orden == Orden_Venta.id_orden)
        .outerjoin(Reservas_Backorder, Transaccion_Pago.id_reserva == Reservas_Backorder.id_reserva)
        .filter(
            Transaccion_Pago.estado_pago == "Procesado",
            Transaccion_Pago.fecha_pago.between(inicio_mes_utc, fin_hoy_utc),
            or_(Orden_Venta.estado_orden.is_(None), Orden_Venta.estado_orden != "Anulada"),
            or_(Reservas_Backorder.estado_reserva.is_(None), Reservas_Backorder.estado_reserva != "Anulada"),
        )
    )
    if id_sucursal is not None:
        query_mtd = query_mtd.filter(
            or_(
                Orden_Venta.id_sucursal == id_sucursal,
                Reservas_Backorder.id_sucursal_registro == id_sucursal,
            )
        )

    pagos_mtd = query_mtd.all()
    acumulado_mensual_mtd = sum(p.monto for p in pagos_mtd)

    return KpiFinancieroDTO(
        ventas_del_dia=ventas_del_dia,
        transacciones_hoy=transacciones_hoy,
        acumulado_mensual_mtd=acumulado_mensual_mtd,
        ticket_promedio=ticket_promedio,
        margen_bruto=64.8,
    )


@router.get(
    "/dashboard/pagos",
    response_model=ResumenPagosDTO,
    summary="Desglose y Comparativa de Medios de Pago",
    description="Retorna distribución de recaudación de hoy por canal.",
)
def obtener_resumen_pagos(
    id_sucursal: Optional[int] = Query(
        None,
        description="ID de sucursal. Si se omite, consolida toda la cadena.",
    ),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_gerencia_o_auditor_central),
):
    """
    Agrupo los métodos de pago de hoy para generar el gráfico Donut.
    Clasifico en efectivo_fisico y canales_electronicos.
    """
    inicio_hoy_utc, fin_hoy_utc, _ = calcular_limites_temporales_chile()

    query_pagos = (
        db.query(Transaccion_Pago)
        .outerjoin(Orden_Venta, Transaccion_Pago.id_orden == Orden_Venta.id_orden)
        .outerjoin(Reservas_Backorder, Transaccion_Pago.id_reserva == Reservas_Backorder.id_reserva)
        .filter(
            Transaccion_Pago.estado_pago == "Procesado",
            Transaccion_Pago.fecha_pago.between(inicio_hoy_utc, fin_hoy_utc),
            or_(Orden_Venta.estado_orden.is_(None), Orden_Venta.estado_orden != "Anulada"),
            or_(Reservas_Backorder.estado_reserva.is_(None), Reservas_Backorder.estado_reserva != "Anulada"),
        )
    )
    if id_sucursal is not None:
        query_pagos = query_pagos.filter(
            or_(
                Orden_Venta.id_sucursal == id_sucursal,
                Reservas_Backorder.id_sucursal_registro == id_sucursal,
            )
        )

    pagos = query_pagos.all()

    metodos_montos = {}
    metodos_cantidades = {}
    efectivo_fisico = 0
    canales_electronicos = 0
    total_recaudado = 0
    total_transacciones = len(pagos)

    for p in pagos:
        metodo = (p.metodo_pago or "Otro").strip()
        metodos_montos[metodo] = metodos_montos.get(metodo, 0) + p.monto
        metodos_cantidades[metodo] = metodos_cantidades.get(metodo, 0) + 1
        total_recaudado += p.monto
        if "efectivo" in metodo.lower():
            efectivo_fisico += p.monto
        else:
            canales_electronicos += p.monto

    desglose = []
    items_ordenados = sorted(
        metodos_montos.items(), key=lambda x: x[1], reverse=True
    )
    for metodo, monto in items_ordenados:
        cant = metodos_cantidades.get(metodo, 1)
        porcentaje_monto = (
            round((monto / total_recaudado) * 100, 2)
            if total_recaudado > 0
            else 0.0
        )
        porcentaje_cant = (
            round((cant / total_transacciones) * 100, 2)
            if total_transacciones > 0
            else 0.0
        )
        desglose.append(
            DesglosePagoDTO(
                metodo_pago=metodo,
                monto_total=monto,
                porcentaje=porcentaje_monto,
                cantidad=cant,
                porcentaje_cantidad=porcentaje_cant,
            )
        )

    return ResumenPagosDTO(
        efectivo_fisico=efectivo_fisico,
        canales_electronicos=canales_electronicos,
        total_transacciones=total_transacciones,
        desglose=desglose,
    )


@router.get(
    "/dashboard/operativa",
    response_model=FlujoOperativoDTO,
    summary="Pulso Operativo de Bodega y Alertas",
    description="Retorna estado del pipeline de despacho y alertas.",
)
def obtener_flujo_operativo(
    id_sucursal: Optional[int] = Query(
        None,
        description="ID de sucursal. Si se omite, consolida toda la cadena.",
    ),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_gerencia_o_auditor_central),
):
    """
    Calculo el flujo logístico de bodega: ítems en preparación física,
    piezas listas en mostrador, envíos por courier, saldos y piezas sin precio.
    """
    # 1. En preparación (Ítems en preparación de órdenes activas)
    query_prep = (
        db.query(Detalle_Orden)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .filter(
            Detalle_Orden.estado_preparacion != "Listo",
            Detalle_Orden.estado_preparacion != "Reingresado",
            Orden_Venta.estado_orden.in_(["Reservada", "Pagada"]),
        )
    )
    if id_sucursal is not None:
        query_prep = query_prep.filter(
            Orden_Venta.id_sucursal == id_sucursal
        )
    en_preparacion = query_prep.count()

    # 2. Listos mostrador (Ítems listos para retiro sin courier enviado)
    query_listos = (
        db.query(Detalle_Orden)
        .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
        .outerjoin(Despacho, Orden_Venta.id_orden == Despacho.id_orden)
        .filter(
            Detalle_Orden.estado_preparacion == "Listo",
            Orden_Venta.estado_orden.in_(["Reservada", "Pagada"]),
            or_(
                Despacho.id_despacho.is_(None),
                Despacho.estado_despacho != "Enviado",
            ),
        )
    )
    if id_sucursal is not None:
        query_listos = query_listos.filter(
            Orden_Venta.id_sucursal == id_sucursal
        )
    listos_mostrador = query_listos.count()

    # 3. Enviados Courier (Despachos en tránsito hacia su destino)
    query_courier = (
        db.query(Despacho)
        .join(Orden_Venta, Despacho.id_orden == Orden_Venta.id_orden)
        .filter(Despacho.estado_despacho == "Enviado")
    )
    if id_sucursal is not None:
        query_courier = query_courier.filter(
            Orden_Venta.id_sucursal == id_sucursal
        )
    enviados_courier = query_courier.count()

    # 4. Alertas de saldo pendiente (Órdenes activas con saldo retenido)
    query_saldos = (
        db.query(Orden_Venta)
        .filter(
            Orden_Venta.estado_orden != "Anulada",
            Orden_Venta.monto_pendiente > 0,
        )
    )
    if id_sucursal is not None:
        query_saldos = query_saldos.filter(
            Orden_Venta.id_sucursal == id_sucursal
        )
    alertas_saldo_pendiente = query_saldos.count()

    # 5. Cuellos de botella en tasación (Piezas paletizadas sin precio)
    query_cuellos = (
        db.query(Activo_Inventariado)
        .join(
            Estado_Activo,
            Activo_Inventariado.id_estado == Estado_Activo.id_estado,
        )
        .filter(
            Activo_Inventariado.estado == "Activo",
            or_(
                Activo_Inventariado.id_estado == 7,
                Estado_Activo.nombre_estado == "Paletizado",
            ),
        )
    )
    if id_sucursal is not None:
        query_cuellos = query_cuellos.filter(
            Activo_Inventariado.id_sucursal_actual == id_sucursal
        )
    cuellos_botella_paletizados = query_cuellos.count()

    return FlujoOperativoDTO(
        en_preparacion=en_preparacion,
        listos_mostrador=listos_mostrador,
        enviados_courier=enviados_courier,
        alertas_saldo_pendiente=alertas_saldo_pendiente,
        cuellos_botella_paletizados=cuellos_botella_paletizados,
    )


# ==========================================
# VISOR CENTRALIZADO DE BACKORDERS (HU-5.4)
# ==========================================

def format_relative_chile_date(dt: Optional[datetime]) -> str:
    """
    Formatea la fecha de creación en hora local de Chile a un formato amigable:
    - 'Hoy HH:MM'
    - 'Ayer HH:MM'
    - 'Hace N días'
    - 'DD/MM/YYYY HH:MM'
    """
    if not dt:
        return "Fecha desconocida"
    if dt.tzinfo is None:
        dt_utc = dt.replace(tzinfo=timezone.utc)
    else:
        dt_utc = dt.astimezone(timezone.utc)
    dt_local = dt_utc.astimezone(tz_chile)
    ahora_local = datetime.now(tz_chile)

    dias_diff = (ahora_local.date() - dt_local.date()).days
    hora_str = dt_local.strftime("%H:%M")

    if dias_diff == 0:
        return f"Hoy {hora_str}"
    elif dias_diff == 1:
        return f"Ayer {hora_str}"
    elif 2 <= dias_diff <= 7:
        return f"Hace {dias_diff} días"
    else:
        return dt_local.strftime("%d/%m/%Y %H:%M")


@router.get(
    "/backorders",
    response_model=BackorderGerenciaListResponse,
    summary="Listado Maestro de Backorders para Gerencia (HU-5.4)",
)
def obtener_backorders_gerencia(
    id_sucursal: Optional[int] = Query(None, description="Filtrar por ID de sucursal"),
    estado: Optional[str] = Query(None, description="Filtrar por estado de reserva (Pendiente, Confirmada, Completada, Anulada)"),
    q: Optional[str] = Query(None, description="Búsqueda predictiva (Folio, Cliente, Vendedor, Marca, Modelo)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: Usuario = Depends(require_gerencia_o_auditor_central),
    db: Session = Depends(get_db),
):
    query = (
        db.query(
            Reservas_Backorder,
            Cliente,
            Usuario,
            Sucursal,
            Categoria_Activo,
            Activo_Inventariado,
            Orden_Venta,
        )
        .join(Cliente, Reservas_Backorder.id_cliente == Cliente.id_cliente)
        .join(Usuario, Reservas_Backorder.id_vendedor == Usuario.id_usuario)
        .join(Sucursal, Reservas_Backorder.id_sucursal_registro == Sucursal.id_sucursal)
        .outerjoin(Categoria_Activo, Reservas_Backorder.id_categoria_requerida == Categoria_Activo.id_categoria)
        .outerjoin(Activo_Inventariado, Reservas_Backorder.id_activo_asignado == Activo_Inventariado.id_activo)
        .outerjoin(Orden_Venta, Reservas_Backorder.id_orden == Orden_Venta.id_orden)
    )

    if id_sucursal is not None:
        query = query.filter(Reservas_Backorder.id_sucursal_registro == id_sucursal)

    if estado and estado.strip() and estado.lower() != "todos":
        query = query.filter(Reservas_Backorder.estado_reserva == estado.strip())

    if q and q.strip():
        term = f"%{q.strip().lower()}%"
        query = query.filter(
            or_(
                func.lower(Reservas_Backorder.marca_requerida).ilike(term),
                func.lower(Reservas_Backorder.modelo_requerido).ilike(term),
                func.lower(Cliente.nombres).ilike(term),
                func.lower(Cliente.apellidos).ilike(term),
                func.lower(Cliente.rut_cliente).ilike(term),
                func.lower(Usuario.nombres).ilike(term),
                func.lower(Usuario.apellidos).ilike(term),
                cast(Reservas_Backorder.id_reserva, String).ilike(term),
            )
        )

    total_count = query.count()

    total_senas = (
        query.with_entities(func.coalesce(func.sum(Reservas_Backorder.monto_abonado), 0)).scalar()
        if total_count > 0 else 0
    )

    query = query.order_by(Reservas_Backorder.fecha_creacion.desc())
    rows = query.offset(offset).limit(limit).all()

    items = []
    for res, cli, ven, suc, cat, act, ord_vinc in rows:
        folio_str = f"RES-{str(res.id_reserva).replace('-', '')[:4].upper()}"
        fecha_amigable = format_relative_chile_date(res.fecha_creacion)
        fecha_iso = res.fecha_creacion.isoformat() if res.fecha_creacion else ""
        cliente_nombre_completo = f"{cli.nombres or ''} {cli.apellidos or ''}".strip() or "Cliente no registrado"
        vendedor_nombre_completo = f"{ven.nombres or ''} {ven.apellidos or ''}".strip() or "Vendedor no registrado"
        cat_nombre = cat.nombre_categoria if cat else "Repuesto"
        sku_fisico = act.sku_qr_fisico if act else None

        desc_val = getattr(ord_vinc, "descuento", 0) or 0 if ord_vinc else 0
        if ord_vinc and (ord_vinc.estado_orden == "Pagada" or ord_vinc.monto_pendiente == 0):
            saldo_calc = 0
        elif ord_vinc and ord_vinc.monto_pendiente is not None:
            saldo_calc = ord_vinc.monto_pendiente
        else:
            saldo_calc = max(0, res.precio_acordado - desc_val - (res.monto_abonado or 0))

        item_dto = BackorderGerenciaItemDTO(
            id_reserva=str(res.id_reserva),
            folio=folio_str,
            fecha_creacion=fecha_amigable,
            fecha_creacion_iso=fecha_iso,
            id_cliente=str(res.id_cliente),
            cliente_nombre=cliente_nombre_completo,
            cliente_telefono=getattr(cli, "telefono", None) or getattr(cli, "correo", None),
            cliente_rut=cli.rut_cliente,
            id_vendedor=str(res.id_vendedor),
            vendedor_nombre=vendedor_nombre_completo,
            id_sucursal=res.id_sucursal_registro,
            sucursal_nombre=suc.nombre_sucursal if suc else f"Sucursal {res.id_sucursal_registro}",
            id_categoria_requerida=res.id_categoria_requerida,
            categoria_nombre=cat_nombre,
            marca_requerida=res.marca_requerida,
            modelo_requerido=res.modelo_requerido,
            anio_requerido=res.anio_requerido,
            cilindrada_requerida=res.cilindrada_requerida,
            combustible_requerido=res.combustible_requerido,
            transmision_requerida=res.transmision_requerida,
            notas_preparacion=res.notas_preparacion,
            precio_acordado=res.precio_acordado,
            descuento=desc_val,
            monto_abonado=res.monto_abonado or 0,
            saldo_pendiente=saldo_calc,
            estado_reserva=res.estado_reserva,
            id_activo_asignado=str(res.id_activo_asignado) if res.id_activo_asignado else None,
            activo_asignado_sku=sku_fisico,
            id_orden=str(res.id_orden) if res.id_orden else None,
        )
        items.append(item_dto)

    return BackorderGerenciaListResponse(
        items=items,
        total_count=total_count,
        total_recaudado_senas=total_senas,
    )


@router.get(
    "/backorders/kpis",
    response_model=BackorderGerenciaKpisDTO,
    summary="Cabecera Analítica de KPIs de Backorders (HU-5.4)",
)
def obtener_kpis_backorders_gerencia(
    id_sucursal: Optional[int] = Query(None, description="Filtrar por sucursal"),
    current_user: Usuario = Depends(require_gerencia_o_auditor_central),
    db: Session = Depends(get_db),
):
    query = db.query(Reservas_Backorder)
    if id_sucursal is not None:
        query = query.filter(Reservas_Backorder.id_sucursal_registro == id_sucursal)

    # 1. Total Backorders Activos (Pendiente o Confirmada)
    total_activos = query.filter(
        Reservas_Backorder.estado_reserva.in_(["Pendiente", "Confirmada"])
    ).count()

    # 2. Capital Retenido en Abonos (Suma de señas de reservas activas)
    capital_retenido = (
        query.filter(Reservas_Backorder.estado_reserva.in_(["Pendiente", "Confirmada"]))
        .with_entities(func.coalesce(func.sum(Reservas_Backorder.monto_abonado), 0))
        .scalar()
    ) or 0

    # 3. Listos para Liquidar (Activos con match físico asignado)
    listos_para_liquidar = query.filter(
        Reservas_Backorder.estado_reserva.in_(["Pendiente", "Confirmada"]),
        Reservas_Backorder.id_activo_asignado.isnot(None),
    ).count()

    # Totales globales
    total_registrados = query.count()
    total_recaudado_senas = (
        query.with_entities(func.coalesce(func.sum(Reservas_Backorder.monto_abonado), 0))
        .scalar()
    ) or 0

    return BackorderGerenciaKpisDTO(
        total_activos=total_activos,
        capital_retenido=capital_retenido,
        listos_para_liquidar=listos_para_liquidar,
        total_registrados=total_registrados,
        total_recaudado_senas=total_recaudado_senas,
    )
