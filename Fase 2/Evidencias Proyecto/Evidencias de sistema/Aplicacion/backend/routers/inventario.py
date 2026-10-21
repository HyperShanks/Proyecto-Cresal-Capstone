import asyncio
import uuid
from datetime import datetime, timezone
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, status, UploadFile, File, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import func, or_, case, update
from typing import Dict, List, Optional
from core.storage import supabase
from services.telegram_service import TelegramService

from database import get_db
from models import (
    Activo_Inventariado,
    Vehiculo_Origen,
    Detalle_Motor,
    Multimedia_Activo,
    Detalle_Caja_Cambio,
    Categoria_Activo,
    Estado_Activo,
    Sucursal,
    Usuario,
    Bitacora_Movimiento_Inventario,
)
from core.security import (
    get_current_user,
    verificar_rol_jefe_ventas,
    verificar_rol_tasacion,
    require_inventario_maestro_read,
    require_bodeguero_or_admin,
)
from schemas import (
    CatalogoItemResponse,
    PaginatedCatalogoResponse,
    ActivoPendientePrecioResponse,
    AsignarPrecioRequest,
    AsignarPrecioResponse,
    EditarActivoRequest,
    EditarActivoResponse,
    DespaletizarActivoRequest,
)
from routers.carrito import limpiar_reservas_expiradas

router = APIRouter(prefix="/api/v1/inventario", tags=["Buscador Inventario"])


@router.get("/opciones-filtros", response_model=Dict[str, List[str]])
def obtener_opciones_filtros(
    categoria: Optional[str] = None,
    galpon: Optional[str] = None,
    pasillo: Optional[str] = None,
    pallet: Optional[str] = None,
    marca: Optional[str] = None,
    modelo: Optional[str] = None,
    cilindrada: Optional[str] = None,
    combustible: Optional[str] = None,
    transmision: Optional[str] = None,
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    # 1. Base idéntica a la del buscador (incluyendo joins y exclusión de estados)
    query = (
        db.query(Activo_Inventariado, Vehiculo_Origen, Detalle_Motor, Detalle_Caja_Cambio)
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
    )

    # ⚠️ REGLA DE NEGOCIO: Filtrar repuestos físicamente en bodega (Disponibles, Reservados, Vendidos y Paletizados)
    query = query.filter(
        or_(
            Activo_Inventariado.id_estado.in_([1, 2, 3]),
            func.lower(Estado_Activo.nombre_estado) == "paletizado",
        ),
        Activo_Inventariado.estado == "Activo",
    )

    # 2. Aplicamos los filtros actuales que el usuario ya seleccionó
    if categoria:
        cat_upper = categoria.upper()
        if cat_upper == "MOTORES":
            query = query.filter(Activo_Inventariado.id_categoria == 1)
        elif cat_upper == "CAJAS DE CAMBIO":
            query = query.filter(Activo_Inventariado.id_categoria == 2)
        elif cat_upper == "ACCESORIOS":
            query = query.filter(Activo_Inventariado.id_categoria == 3)

    if marca:
        query = query.filter(func.upper(Vehiculo_Origen.marca) == marca.upper())
    if modelo:
        query = query.filter(func.upper(Vehiculo_Origen.modelo) == modelo.upper())
    if cilindrada:
        query = query.filter(func.upper(Detalle_Motor.cilindrada) == cilindrada.upper())
    if combustible:
        query = query.filter(func.upper(Detalle_Motor.combustible) == combustible.upper())
    if transmision:
        query = query.filter(
            (func.upper(Detalle_Motor.transmision_tipo) == transmision.upper())
            | (func.upper(Detalle_Caja_Cambio.transmision_tipo) == transmision.upper())
        )

    # 3. Ubicaciones en cascada jerárquica (Galpón -> Pasillos en ese Galpón -> Pallets en ese Pasillo)
    galpones = query.with_entities(func.upper(Activo_Inventariado.ubicacion_galpon)).distinct().all()

    if galpon and galpon.strip().lower() not in ["todos", "todas"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_galpon) == galpon.strip().upper())

    pasillos = query.with_entities(func.upper(Activo_Inventariado.ubicacion_pasillo)).distinct().all()

    if pasillo and pasillo.strip().lower() not in ["todos", "todas"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pasillo) == pasillo.strip().upper())

    pallets = query.with_entities(func.upper(Activo_Inventariado.ubicacion_pallet)).distinct().all()

    if pallet and pallet.strip().lower() not in ["todos", "todas"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pallet) == pallet.strip().upper())

    # 4. Extraemos las opciones ÚNICAS generales
    marcas = query.with_entities(func.upper(Vehiculo_Origen.marca)).distinct().all()
    modelos = query.with_entities(func.upper(Vehiculo_Origen.modelo)).distinct().all()
    cilindradas = query.with_entities(func.upper(Detalle_Motor.cilindrada)).distinct().all()
    combustibles = query.with_entities(func.upper(Detalle_Motor.combustible)).distinct().all()

    trans_motor = query.with_entities(func.upper(Detalle_Motor.transmision_tipo)).distinct().all()
    trans_caja = query.with_entities(func.upper(Detalle_Caja_Cambio.transmision_tipo)).distinct().all()
    transmisiones = list(set(trans_motor + trans_caja))

    def limpiar_lista(query_result):
        return sorted(
            list(
                set([item[0] for item in query_result if item[0] is not None and str(item[0]).strip() != ""])
            )
        )

    return {
        "marcas": limpiar_lista(marcas),
        "modelos": limpiar_lista(modelos),
        "cilindradas": limpiar_lista(cilindradas),
        "combustibles": limpiar_lista(combustibles),
        "transmisiones": limpiar_lista(transmisiones),
        "galpones": limpiar_lista(galpones),
        "pasillos": limpiar_lista(pasillos),
        "pallets": limpiar_lista(pallets),
    }


@router.get("/buscar")
def buscar_inventario(
    q: Optional[str] = Query(None, description="Texto libre para buscar por marca, modelo, SKU o N° Ingreso"),
    categoria: Optional[str] = None,
    pasillo: Optional[str] = None,
    pallet: Optional[str] = None,
    marca: Optional[str] = None,
    modelo: Optional[str] = None,
    cilindrada: Optional[str] = None,
    combustible: Optional[str] = None,
    transmision: Optional[str] = None,
    estado: Optional[str] = Query(None, description="Filtro operativo: Disponibles, Reservados, Vendidos, Paletizados, Todos"),
    limit: Optional[int] = Query(None, ge=1, le=100, description="Límite de elementos por página"),
    offset: int = Query(0, ge=0, description="Desplazamiento para paginación"),
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    query = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Detalle_Motor,
            Detalle_Caja_Cambio,
            Categoria_Activo,
            Estado_Activo,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
    )

    # Filtro por Estado Operativo (SPEC-HU-TAREA-16)
    if estado and estado.strip():
        est_clean = estado.strip().upper()
        if est_clean in ["DISPONIBLES", "DISPONIBLE"]:
            query = query.filter(
                or_(
                    Activo_Inventariado.id_estado == 1,
                    func.lower(Estado_Activo.nombre_estado) == "disponible",
                )
            )
        elif est_clean in ["RESERVADOS", "RESERVADO"]:
            query = query.filter(
                or_(
                    Activo_Inventariado.id_estado == 2,
                    func.lower(Estado_Activo.nombre_estado) == "reservado",
                )
            )
        elif est_clean in ["PALETIZADOS", "PALETIZADO"]:
            query = query.filter(
                func.lower(Estado_Activo.nombre_estado) == "paletizado"
            )
        elif est_clean in ["TODOS", "TODO"]:
            query = query.filter(
                or_(
                    Activo_Inventariado.id_estado.in_([1, 2]),
                    func.lower(Estado_Activo.nombre_estado) == "paletizado",
                )
            )
        else:
            # Los estados no operativos en bodega (ej. VENDIDO/DESPACHADO) no forman parte del stock físico en pasillos
            query = query.filter(Activo_Inventariado.id_estado == -1)
    else:
        # Default operativo en bodega: incluye Disponibles, Reservados y Paletizados (excluye Vendidos que ya salieron de bodega)
        query = query.filter(
            or_(
                Activo_Inventariado.id_estado.in_([1, 2]),
                func.lower(Estado_Activo.nombre_estado) == "paletizado",
            )
        )

    query = query.filter(Activo_Inventariado.estado == "Activo")

    # Búsqueda por Texto Libre
    if q and q.strip():
        q_term = f"%{q.strip().upper()}%"
        query = query.filter(
            or_(
                func.upper(Activo_Inventariado.sku_qr_fisico).like(q_term),
                func.upper(Categoria_Activo.nombre_categoria).like(q_term),
                func.upper(Vehiculo_Origen.marca).like(q_term),
                func.upper(Vehiculo_Origen.modelo).like(q_term),
                func.upper(Vehiculo_Origen.numero_ingreso).like(q_term),
            )
        )

    # Filtro de Categoría
    if categoria:
        cat_upper = categoria.upper()
        if cat_upper == "MOTORES":
            query = query.filter(Activo_Inventariado.id_categoria == 1)
        elif cat_upper == "CAJAS DE CAMBIO":
            query = query.filter(Activo_Inventariado.id_categoria == 2)
        elif cat_upper == "ACCESORIOS":
            query = query.filter(Activo_Inventariado.id_categoria == 3)

    if pasillo:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pasillo) == pasillo.upper())
    if pallet:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pallet) == pallet.upper())
    if marca:
        query = query.filter(func.upper(Vehiculo_Origen.marca) == marca.upper())
    if modelo:
        query = query.filter(func.upper(Vehiculo_Origen.modelo) == modelo.upper())
    if cilindrada:
        query = query.filter(func.upper(Detalle_Motor.cilindrada) == cilindrada.upper())
    if combustible:
        query = query.filter(func.upper(Detalle_Motor.combustible) == combustible.upper())
    if transmision:
        query = query.filter(
            (func.upper(Detalle_Motor.transmision_tipo) == transmision.upper())
            | (func.upper(Detalle_Caja_Cambio.transmision_tipo) == transmision.upper())
        )

    query = query.order_by(Activo_Inventariado.fecha_creacion.desc())

    if limit is not None:
        query = query.offset(offset).limit(limit)

    resultados_db = query.all()

    # Obtener imágenes eficientemente en lote
    activo_ids = [activo.id_activo for activo, *_ in resultados_db]
    fotos_db = (
        db.query(Multimedia_Activo.id_activo, Multimedia_Activo.url_storage)
        .filter(Multimedia_Activo.id_activo.in_(activo_ids))
        .all()
    ) if activo_ids else []
    fotos_map: Dict[UUID, List[str]] = {}
    for act_id, url in fotos_db:
        fotos_map.setdefault(act_id, []).append(url)

    # Herencia de datos técnicos de motor para Cajas de Cambio en lote (SPEC-HU-TAREA-17)
    cajas_vehiculo_ids = [
        activo.id_vehiculo
        for activo, vehiculo, motor, caja, cat, est in resultados_db
        if cat.id_categoria == 2 and activo.id_vehiculo is not None
    ]
    motores_donantes_buscar: Dict[UUID, Detalle_Motor] = {}
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
            motores_donantes_buscar[v_id] = dm

    respuesta = []
    for activo, vehiculo, motor, caja, cat, est in resultados_db:
        lista_fotos = fotos_map.get(activo.id_activo, [])
        motor_donante = motores_donantes_buscar.get(activo.id_vehiculo) if (cat.id_categoria == 2 and activo.id_vehiculo) else None

        if cat.id_categoria == 2:
            transmision_val = caja.transmision_tipo if caja else "N/A"
            cilindrada_val = (motor_donante.cilindrada if motor_donante else None) or "N/A"
            combustible_val = (motor_donante.combustible if motor_donante else None) or "N/A"
            numero_motor_val = None
        elif motor:
            transmision_val = motor.transmision_tipo or "N/A"
            cilindrada_val = motor.cilindrada or "N/A"
            combustible_val = motor.combustible or "N/A"
            numero_motor_val = motor.numero_motor if cat.id_categoria == 1 else None
        else:
            transmision_val = "N/A"
            cilindrada_val = "N/A"
            combustible_val = "N/A"
            numero_motor_val = None

        respuesta.append(
            {
                "id_activo": str(activo.id_activo),
                "sku": activo.sku_qr_fisico,
                "qr_impreso": activo.qr_impreso if activo.qr_impreso is not None else False,
                "numero_ingreso": vehiculo.numero_ingreso if vehiculo else "N/A",
                "marca": vehiculo.marca if vehiculo else "Desconocida",
                "modelo": vehiculo.modelo if vehiculo else "Desconocido",
                "anio": vehiculo.anio if vehiculo else 0,
                "traccion": vehiculo.traccion if (vehiculo and vehiculo.traccion) else "N/A",
                "ubicacion": f"{activo.ubicacion_pasillo or 'S/P'} - {activo.ubicacion_pallet or 'S/P'}",
                "pasillo": activo.ubicacion_pasillo or "",
                "pallet": activo.ubicacion_pallet or "",
                "galpon": getattr(activo, "ubicacion_galpon", "") or "",
                "ubicacion_pasillo": activo.ubicacion_pasillo or "",
                "ubicacion_pallet": activo.ubicacion_pallet or "",
                "ubicacion_galpon": getattr(activo, "ubicacion_galpon", "") or "",
                "estado": est.nombre_estado,
                "categoria": cat.nombre_categoria,
                "cilindrada": cilindrada_val,
                "combustible": combustible_val,
                "transmision": transmision_val,
                "numero_motor": numero_motor_val,
                "observacion": getattr(activo, "observacion_estado", "Sin observaciones registradas."),
                "observacion_estado": getattr(activo, "observacion_estado", None),
                "version_lock": activo.version_lock or 1,
                "imagenes": lista_fotos,
                "precio_referencia": activo.precio_referencia,
                "precio_minimo": activo.precio_minimo,
                "precio_maximo": activo.precio_maximo,
            }
        )

    return respuesta


@router.get("/catalogo/opciones-filtros")
def obtener_opciones_filtros_catalogo(
    id_categoria: Optional[int] = Query(None, description="Filtro opcional por ID de categoría"),
    id_sucursal: Optional[int] = Query(None, description="Filtro opcional por ID de sucursal"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Retorna exclusivamente las opciones de filtro (marcas, años, cilindradas, transmisiones)
    de aquellos repuestos inventariados que se encuentren actualmente en estado 'Disponible',
    activos y con precio de referencia tasado (visibles en el catálogo de ventas).
    """
    limpiar_reservas_expiradas(db)

    # Base: sólo activos inventariados Disponibles y con precio de referencia
    base_filter = [
        Activo_Inventariado.estado == "Activo",
        Activo_Inventariado.id_estado == 1,
        Estado_Activo.nombre_estado == "Disponible",
        Activo_Inventariado.precio_referencia.isnot(None),
        Activo_Inventariado.precio_referencia > 0,
    ]

    if id_categoria is not None:
        base_filter.append(Activo_Inventariado.id_categoria == id_categoria)
    if id_sucursal is not None:
        base_filter.append(Activo_Inventariado.id_sucursal_actual == id_sucursal)

    # 1. Marcas
    marcas_raw = (
        db.query(Vehiculo_Origen.marca)
        .join(Activo_Inventariado, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(*base_filter, Vehiculo_Origen.marca.isnot(None))
        .distinct()
        .all()
    )
    marcas = sorted(
        list(set(m[0].strip().upper() for m in marcas_raw if m[0] and m[0].strip()))
    )

    # 2. Años
    anios_raw = (
        db.query(Vehiculo_Origen.anio)
        .join(Activo_Inventariado, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(*base_filter, Vehiculo_Origen.anio.isnot(None))
        .distinct()
        .all()
    )
    anios = sorted(
        list(set(int(a[0]) for a in anios_raw if a[0] is not None and a[0] > 1900)),
        reverse=True,
    )

    # 3. Cilindradas (de motores)
    cil_raw = (
        db.query(Detalle_Motor.cilindrada)
        .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(*base_filter, Detalle_Motor.cilindrada.isnot(None))
        .distinct()
        .all()
    )
    cilindradas = sorted(
        list(set(c[0].strip().upper().replace("L", "").strip() for c in cil_raw if c[0] and c[0].strip()))
    )

    # 4. Transmisiones (motores y cajas)
    trans_m_raw = (
        db.query(Detalle_Motor.transmision_tipo)
        .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(*base_filter, Detalle_Motor.transmision_tipo.isnot(None))
        .distinct()
        .all()
    )
    trans_c_raw = (
        db.query(Detalle_Caja_Cambio.transmision_tipo)
        .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(*base_filter, Detalle_Caja_Cambio.transmision_tipo.isnot(None))
        .distinct()
        .all()
    )
    trans_combined = []
    for t in (trans_m_raw + trans_c_raw):
        if t[0] and t[0].strip():
            val = t[0].strip()
            val_upper = val.upper()
            if "MEC" in val_upper or "MAN" in val_upper:
                trans_combined.append("Mecánica")
            elif "AUT" in val_upper:
                trans_combined.append("Automática")
            elif "SEMI" in val_upper:
                trans_combined.append("Semiautomática")
            else:
                trans_combined.append(val.title())
    transmisiones = sorted(list(set(trans_combined)))

    return {
        "marcas": marcas,
        "anios": anios,
        "cilindradas": cilindradas,
        "transmisiones": transmisiones,
    }


@router.get("/catalogo", response_model=PaginatedCatalogoResponse)
def obtener_catalogo(
    q: Optional[str] = Query(None, description="Texto libre para buscar por marca, modelo o SKU"),
    id_categoria: Optional[int] = Query(None, description="Filtro por ID de categoría"),
    id_sucursal: Optional[int] = Query(None, description="Filtro explícito por ID de sucursal"),
    marca: Optional[str] = Query(None, description="Filtro por marca"),
    anio: Optional[int] = Query(None, description="Filtro por año"),
    cilindrada: Optional[str] = Query(None, description="Filtro por cilindrada"),
    transmision: Optional[str] = Query(None, description="Filtro por tipo de transmisión"),
    limit: int = Query(20, ge=1, le=100, description="Límite de elementos por página"),
    offset: int = Query(0, ge=0, description="Desplazamiento para paginación"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    limpiar_reservas_expiradas(db)
    query = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
            Estado_Activo,
            Sucursal,
            Detalle_Motor,
            Detalle_Caja_Cambio,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .join(Sucursal, Activo_Inventariado.id_sucursal_actual == Sucursal.id_sucursal)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
    )

    # Filtros Base de catálogo
    query = query.filter(
        Activo_Inventariado.estado == "Activo",
        Activo_Inventariado.id_estado == 1,
        Estado_Activo.nombre_estado == "Disponible",
        Activo_Inventariado.precio_referencia.isnot(None),
        Activo_Inventariado.precio_referencia > 0,
    )

    if id_categoria is not None:
        query = query.filter(Activo_Inventariado.id_categoria == id_categoria)

    if id_sucursal is not None:
        query = query.filter(Activo_Inventariado.id_sucursal_actual == id_sucursal)

    if marca and marca.strip():
        query = query.filter(func.upper(Vehiculo_Origen.marca) == marca.strip().upper())

    if anio is not None:
        query = query.filter(Vehiculo_Origen.anio == anio)

    if cilindrada and cilindrada.strip():
        cil_clean = cilindrada.strip().upper().replace("L", "").strip()
        query = query.filter(func.upper(Detalle_Motor.cilindrada).like(f"%{cil_clean}%"))

    if transmision and transmision.strip():
        trans_clean = transmision.strip().upper()
        if "MEC" in trans_clean or "MAN" in trans_clean:
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like("%MAN%"),
                    func.upper(Detalle_Motor.transmision_tipo).like("%MEC%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%MAN%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%MEC%"),
                )
            )
        elif "AUT" in trans_clean:
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like("%AUT%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%AUT%"),
                )
            )
        else:
            trans_term = f"%{trans_clean}%"
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like(trans_term),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like(trans_term),
                )
            )

    if q and q.strip():
        q_term = f"%{q.strip().upper()}%"
        query = query.filter(
            or_(
                func.upper(Activo_Inventariado.sku_qr_fisico).like(q_term),
                func.upper(Categoria_Activo.nombre_categoria).like(q_term),
                func.upper(Vehiculo_Origen.marca).like(q_term),
                func.upper(Vehiculo_Origen.modelo).like(q_term),
            )
        )

    total_count = query.count()

    if id_sucursal is None and getattr(current_user, "id_sucursal", None) is not None:
        radar_order = case(
            (Activo_Inventariado.id_sucursal_actual == current_user.id_sucursal, 1),
            else_=0,
        ).desc()
        query = query.order_by(radar_order, Activo_Inventariado.fecha_creacion.desc())
    else:
        query = query.order_by(Activo_Inventariado.fecha_creacion.desc())

    resultados = query.offset(offset).limit(limit).all()

    activo_ids = [activo.id_activo for activo, *_ in resultados]
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
        for activo, vehiculo, cat, est, suc, motor, caja in resultados
        if cat.id_categoria == 2 and activo.id_vehiculo is not None
    ]
    motores_donantes_catalogo: Dict[UUID, Detalle_Motor] = {}
    if cajas_vehiculo_ids:
        motores_cat = (
            db.query(Activo_Inventariado.id_vehiculo, Detalle_Motor)
            .join(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .filter(
                Activo_Inventariado.id_vehiculo.in_(cajas_vehiculo_ids),
                Activo_Inventariado.id_categoria == 1,
            )
            .all()
        )
        for v_id, dm in motores_cat:
            motores_donantes_catalogo[v_id] = dm

    items: List[CatalogoItemResponse] = []
    for activo, vehiculo, cat, est, suc, motor, caja in resultados:
        cilindrada_val = None
        combustible_val = None
        transmision_val = None
        numero_motor_val = None

        motor_donante = motores_donantes_catalogo.get(activo.id_vehiculo) if (cat.id_categoria == 2 and activo.id_vehiculo) else None

        if cat.id_categoria == 1 and motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
            numero_motor_val = motor.numero_motor
        elif cat.id_categoria == 2:
            transmision_val = caja.transmision_tipo if caja else None
            if motor_donante:
                cilindrada_val = motor_donante.cilindrada
                combustible_val = motor_donante.combustible
            numero_motor_val = None
        else:
            if motor:
                cilindrada_val = motor.cilindrada
                combustible_val = motor.combustible
                transmision_val = motor.transmision_tipo
                if cat.id_categoria == 1:
                    numero_motor_val = motor.numero_motor
            elif caja:
                transmision_val = caja.transmision_tipo

        item = CatalogoItemResponse(
            id_activo=activo.id_activo,
            sku_qr_fisico=activo.sku_qr_fisico,
            precio_referencia=activo.precio_referencia,
            precio_minimo=activo.precio_minimo,
            precio_maximo=activo.precio_maximo,
            id_categoria=cat.id_categoria,
            nombre_categoria=cat.nombre_categoria,
            id_sucursal_actual=suc.id_sucursal,
            nombre_sucursal=suc.nombre_sucursal,
            id_vehiculo=vehiculo.id_vehiculo if vehiculo else None,
            marca=vehiculo.marca if vehiculo else None,
            modelo=vehiculo.modelo if vehiculo else None,
            anio=vehiculo.anio if vehiculo else None,
            traccion=vehiculo.traccion if vehiculo else None,
            cilindrada=cilindrada_val,
            combustible=combustible_val,
            transmision_tipo=transmision_val,
            ubicacion_pasillo=activo.ubicacion_pasillo,
            ubicacion_galpon=activo.ubicacion_galpon,
            ubicacion_pallet=activo.ubicacion_pallet,
            observacion_estado=activo.observacion_estado,
            numero_motor=numero_motor_val,
            id_estado=activo.id_estado,
            estado_activo=est.nombre_estado,
            version_lock=activo.version_lock or 1,
            reservado_por=activo.reservado_por,
            qr_impreso=activo.qr_impreso if activo.qr_impreso is not None else False,
            imagenes=fotos_map.get(activo.id_activo, []),
        )
        items.append(item)

    return PaginatedCatalogoResponse(
        items=items,
        total_count=total_count,
        limit=limit,
        offset=offset,
    )


# =============================================================================
# ENDPOINTS PARA JEFE DE VENTAS: ASIGNACIÓN DE PRECIOS (HU-3.8)
# =============================================================================

@router.get(
    "/pendientes-precio",
    response_model=List[ActivoPendientePrecioResponse],
    summary="Bandeja de Entrada de Activos Pendientes de Precio (HU-3.8)",
    description="Consulta todos los activos inventariados/paletizados por bodega que tienen "
                "precio_referencia nulo o igual a 0. Requiere rol de Jefe de Ventas (id_rol == 6).",
)
@router.get(
    "/bandeja-precios",
    response_model=List[ActivoPendientePrecioResponse],
    summary="Bandeja de Entrada de Activos Pendientes de Precio (SPEC-HU-TAREA-15)",
)
def obtener_pendientes_precio(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(verificar_rol_jefe_ventas),
):
    query = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
            Estado_Activo,
            Sucursal,
            Detalle_Motor,
            Detalle_Caja_Cambio,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .join(Sucursal, Activo_Inventariado.id_sucursal_actual == Sucursal.id_sucursal)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .filter(
            Activo_Inventariado.estado == "Activo",
            or_(
                Activo_Inventariado.precio_referencia == None,
                Activo_Inventariado.precio_referencia == 0,
                Activo_Inventariado.precio_minimo == None,
                Activo_Inventariado.precio_minimo == 0,
                Activo_Inventariado.precio_maximo == None,
                Activo_Inventariado.precio_maximo == 0,
            ),
            Activo_Inventariado.ubicacion_pasillo.isnot(None),
            Activo_Inventariado.ubicacion_pasillo != "",
            Activo_Inventariado.ubicacion_pallet.isnot(None),
            Activo_Inventariado.ubicacion_pallet != "",
            Estado_Activo.nombre_estado == "Paletizado",
        )
        .order_by(Activo_Inventariado.fecha_creacion.desc())
    )

    resultados = query.all()

    # Tarea 1: Extracción en lote (Batch) de fotografías sin N+1
    activo_ids = [activo.id_activo for activo, _, _, _, _, _, _ in resultados]
    multimedia_por_activo = {}
    if activo_ids:
        multimedias = (
            db.query(Multimedia_Activo.id_activo, Multimedia_Activo.url_storage)
            .filter(Multimedia_Activo.id_activo.in_(activo_ids))
            .all()
        )
        for id_act, url in multimedias:
            if url:
                multimedia_por_activo.setdefault(id_act, []).append(url)

    respuesta: List[ActivoPendientePrecioResponse] = []
    for activo, vehiculo, cat, est, suc, motor, caja in resultados:
        cilindrada_val = None
        combustible_val = None
        transmision_val = None

        if cat.id_categoria == 1 and motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
        elif cat.id_categoria == 2 and caja:
            transmision_val = caja.transmision_tipo
        else:
            if motor:
                cilindrada_val = motor.cilindrada
                combustible_val = motor.combustible
                transmision_val = motor.transmision_tipo
            elif caja:
                transmision_val = caja.transmision_tipo

        nombre_cat = cat.nombre_categoria if cat else "Repuesto"
        if vehiculo:
            titulo = f"{nombre_cat} - {vehiculo.marca} {vehiculo.modelo} {vehiculo.anio or ''}".strip()
        else:
            titulo = f"{nombre_cat} ({activo.sku_qr_fisico})"

        item = ActivoPendientePrecioResponse(
            id_activo=activo.id_activo,
            sku_qr_fisico=activo.sku_qr_fisico,
            id_categoria=cat.id_categoria,
            nombre_categoria=cat.nombre_categoria,
            id_sucursal_actual=suc.id_sucursal,
            nombre_sucursal=suc.nombre_sucursal,
            ubicacion_galpon=activo.ubicacion_galpon,
            ubicacion_pasillo=activo.ubicacion_pasillo,
            ubicacion_pallet=activo.ubicacion_pallet,
            id_vehiculo=vehiculo.id_vehiculo if vehiculo else None,
            numero_ingreso=vehiculo.numero_ingreso if vehiculo else None,
            marca=vehiculo.marca if vehiculo else None,
            modelo=vehiculo.modelo if vehiculo else None,
            anio=vehiculo.anio if vehiculo else None,
            traccion=vehiculo.traccion if vehiculo else None,
            cilindrada=cilindrada_val,
            combustible=combustible_val,
            transmision_tipo=transmision_val,
            titulo_repuesto=titulo,
            estado_activo=est.nombre_estado,
            fecha_creacion=activo.fecha_creacion.isoformat() if activo.fecha_creacion else None,
            fotografias=multimedia_por_activo.get(activo.id_activo, []),
            precio_referencia=activo.precio_referencia,
            precio_minimo=activo.precio_minimo,
            precio_maximo=activo.precio_maximo,
            observacion_estado=activo.observacion_estado,
        )
        respuesta.append(item)

    return respuesta


# Router adicional para endpoints bajo /api/v1/ventas (SPEC-HU-TAREA-15)
ventas_router = APIRouter(prefix="/api/v1/ventas", tags=["Ventas Bandeja Precios"])


@ventas_router.get(
    "/bandeja-precios",
    response_model=List[ActivoPendientePrecioResponse],
    summary="Bandeja de Precios para Jefe de Ventas (SPEC-HU-TAREA-15)",
)
def obtener_bandeja_precios_ventas(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(verificar_rol_jefe_ventas),
):
    return obtener_pendientes_precio(db=db, current_user=current_user)


@router.get(
    "/maestro",
    response_model=PaginatedCatalogoResponse,
    summary="Maestro de Inventario Global y Tasación (HU-5.3)",
    description="Visor maestro de inventario multi-sucursal para auditoría global y tasación "
                "de piezas paletizadas. Soporta filtros por sucursal, categoría, estado, "
                "combustible, transmisión, ubicación y búsqueda libre.",
)
def obtener_maestro_inventario(
    q: Optional[str] = Query(None, description="Búsqueda libre por SKU, marca, modelo, pasillo, pallet, N° ingreso"),
    id_sucursal: Optional[int] = Query(None, description="Filtro por sucursal. Si es null, consolida toda la cadena"),
    id_categoria: Optional[int] = Query(None, description="Filtro por categoría"),
    id_estado: Optional[int] = Query(None, description="Filtro por ID de estado"),
    estado: Optional[str] = Query(None, description="Filtro por nombre de estado"),
    combustible: Optional[str] = Query(None, description="Filtro por combustible"),
    transmision: Optional[str] = Query(None, description="Filtro por transmisión"),
    ubicacion: Optional[str] = Query(None, description="Filtro rápido por pasillo, pallet o galpón (legacy)"),
    galpon: Optional[str] = Query(None, description="Filtro por Galpón"),
    pasillo: Optional[str] = Query(None, description="Filtro por Pasillo"),
    pallet: Optional[str] = Query(None, description="Filtro por Pallet"),
    solo_sin_tasar: bool = Query(False, description="Filtrar únicamente ítems pendientes de tasación"),
    limit: int = Query(15, ge=1, le=100, description="Límite por página"),
    offset: int = Query(0, ge=0, description="Desplazamiento para paginación"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_inventario_maestro_read),
):
    limpiar_reservas_expiradas(db)
    query = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
            Estado_Activo,
            Sucursal,
            Detalle_Motor,
            Detalle_Caja_Cambio,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .join(Sucursal, Activo_Inventariado.id_sucursal_actual == Sucursal.id_sucursal)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .filter(Activo_Inventariado.estado == "Activo")
    )

    # ⚠️ REGLA DE NEGOCIO: Excluir activos que no están físicamente en inventario de bodega
    # ('En Desarme' / ID 5 y 'Entregado' / ID 6).
    query = query.filter(
        ~Activo_Inventariado.id_estado.in_([5, 6]),
        ~func.lower(Estado_Activo.nombre_estado).in_(["en desarme", "desarme", "entregado"]),
    )

    if id_sucursal is not None:
        query = query.filter(Activo_Inventariado.id_sucursal_actual == id_sucursal)

    if id_categoria is not None:
        query = query.filter(Activo_Inventariado.id_categoria == id_categoria)

    if id_estado is not None:
        query = query.filter(Activo_Inventariado.id_estado == id_estado)
    elif estado and estado.strip().lower() not in ["todos", "todas"]:
        query = query.filter(func.lower(Estado_Activo.nombre_estado) == estado.strip().lower())

    if combustible and combustible.strip().lower() not in ["todos", "todas"]:
        query = query.filter(func.upper(Detalle_Motor.combustible) == combustible.strip().upper())

    if transmision and transmision.strip().lower() not in ["todos", "todas"]:
        trans_clean = transmision.strip().upper()
        if "MEC" in trans_clean or "MAN" in trans_clean:
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like("%MAN%"),
                    func.upper(Detalle_Motor.transmision_tipo).like("%MEC%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%MAN%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%MEC%"),
                )
            )
        elif "AUT" in trans_clean:
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like("%AUT%"),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like("%AUT%"),
                )
            )
        else:
            trans_term = f"%{trans_clean}%"
            query = query.filter(
                or_(
                    func.upper(Detalle_Motor.transmision_tipo).like(trans_term),
                    func.upper(Detalle_Caja_Cambio.transmision_tipo).like(trans_term),
                )
            )

    if galpon and galpon.strip().lower() not in ["todas", "todos"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_galpon) == galpon.strip().upper())

    if pasillo and pasillo.strip().lower() not in ["todas", "todos"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pasillo) == pasillo.strip().upper())

    if pallet and pallet.strip().lower() not in ["todas", "todos"]:
        query = query.filter(func.upper(Activo_Inventariado.ubicacion_pallet) == pallet.strip().upper())

    if ubicacion and ubicacion.strip().lower() not in ["todas", "todos"]:
        u_clean = ubicacion.strip().lower()
        if u_clean.startswith("pasillo-"):
            letra = u_clean.replace("pasillo-", "").upper()
            query = query.filter(func.upper(Activo_Inventariado.ubicacion_pasillo) == letra)
        elif u_clean.startswith("pallet-"):
            num = u_clean.replace("pallet-", "").upper()
            query = query.filter(func.upper(Activo_Inventariado.ubicacion_pallet) == num)
        elif u_clean.startswith("galpon-"):
            num = u_clean.replace("galpon-", "").upper()
            query = query.filter(func.upper(Activo_Inventariado.ubicacion_galpon) == num)

    if solo_sin_tasar:
        query = query.filter(
            or_(
                Activo_Inventariado.id_estado == 7,
                Estado_Activo.nombre_estado == "Paletizado",
            )
        )

    if q and q.strip():
        q_term = f"%{q.strip().upper()}%"
        query = query.filter(
            or_(
                func.upper(Activo_Inventariado.sku_qr_fisico).like(q_term),
                func.upper(Categoria_Activo.nombre_categoria).like(q_term),
                func.upper(Vehiculo_Origen.marca).like(q_term),
                func.upper(Vehiculo_Origen.modelo).like(q_term),
                func.upper(Vehiculo_Origen.numero_ingreso).like(q_term),
                func.upper(Activo_Inventariado.ubicacion_pasillo).like(q_term),
                func.upper(Activo_Inventariado.ubicacion_pallet).like(q_term),
            )
        )

    total_count = query.count()

    # Cálculo exacto de pendientes de tasación (cuellos de botella) para el alcance actual
    query_cuellos = (
        db.query(Activo_Inventariado)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .filter(
            Activo_Inventariado.estado == "Activo",
            or_(
                Activo_Inventariado.id_estado == 7,
                Estado_Activo.nombre_estado == "Paletizado",
            ),
        )
    )
    if id_sucursal is not None:
        query_cuellos = query_cuellos.filter(Activo_Inventariado.id_sucursal_actual == id_sucursal)
    pendientes_tasacion_count = query_cuellos.count()

    query = query.order_by(Activo_Inventariado.fecha_creacion.desc())
    resultados = query.offset(offset).limit(limit).all()

    activo_ids = [activo.id_activo for activo, *_ in resultados]
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
        for activo, vehiculo, cat, est, suc, motor, caja in resultados
        if cat.id_categoria == 2 and activo.id_vehiculo is not None
    ]
    motores_donantes_maestro: Dict[UUID, Detalle_Motor] = {}
    if cajas_vehiculo_ids:
        motores_m = (
            db.query(Activo_Inventariado.id_vehiculo, Detalle_Motor)
            .join(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
            .filter(
                Activo_Inventariado.id_vehiculo.in_(cajas_vehiculo_ids),
                Activo_Inventariado.id_categoria == 1,
            )
            .all()
        )
        for v_id, dm in motores_m:
            motores_donantes_maestro[v_id] = dm

    items: List[CatalogoItemResponse] = []
    for activo, vehiculo, cat, est, suc, motor, caja in resultados:
        cilindrada_val = None
        combustible_val = None
        transmision_val = None
        numero_motor_val = None

        motor_donante = motores_donantes_maestro.get(activo.id_vehiculo) if (cat.id_categoria == 2 and activo.id_vehiculo) else None

        if cat.id_categoria == 1 and motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
            numero_motor_val = motor.numero_motor
        elif cat.id_categoria == 2:
            transmision_val = caja.transmision_tipo if caja else None
            if motor_donante:
                cilindrada_val = motor_donante.cilindrada
                combustible_val = motor_donante.combustible
            numero_motor_val = None
        else:
            if motor:
                cilindrada_val = motor.cilindrada
                combustible_val = motor.combustible
                transmision_val = motor.transmision_tipo
                if cat.id_categoria == 1:
                    numero_motor_val = motor.numero_motor
            elif caja:
                transmision_val = caja.transmision_tipo

        item = CatalogoItemResponse(
            id_activo=activo.id_activo,
            sku_qr_fisico=activo.sku_qr_fisico,
            precio_referencia=activo.precio_referencia,
            precio_minimo=activo.precio_minimo,
            precio_maximo=activo.precio_maximo,
            id_categoria=cat.id_categoria,
            nombre_categoria=cat.nombre_categoria,
            id_sucursal_actual=suc.id_sucursal,
            nombre_sucursal=suc.nombre_sucursal,
            id_vehiculo=vehiculo.id_vehiculo if vehiculo else None,
            marca=vehiculo.marca if vehiculo else None,
            modelo=vehiculo.modelo if vehiculo else None,
            anio=vehiculo.anio if vehiculo else None,
            traccion=vehiculo.traccion if vehiculo else None,
            cilindrada=cilindrada_val,
            combustible=combustible_val,
            transmision_tipo=transmision_val,
            ubicacion_pasillo=activo.ubicacion_pasillo,
            ubicacion_galpon=activo.ubicacion_galpon,
            ubicacion_pallet=activo.ubicacion_pallet,
            observacion_estado=activo.observacion_estado,
            numero_motor=numero_motor_val,
            id_estado=activo.id_estado,
            estado_activo=est.nombre_estado,
            version_lock=activo.version_lock or 1,
            reservado_por=activo.reservado_por,
            qr_impreso=activo.qr_impreso if activo.qr_impreso is not None else False,
            imagenes=fotos_map.get(activo.id_activo, []),
        )
        items.append(item)

    return PaginatedCatalogoResponse(
        items=items,
        total_count=total_count,
        limit=limit,
        offset=offset,
        pendientes_tasacion_count=pendientes_tasacion_count,
    )


@router.patch(
    "/{id_activo}/precio",
    response_model=AsignarPrecioResponse,
    summary="Asignar Precio de Referencia a Repuesto (HU-3.8 / HU-5.3)",
    description="Fija el precio_referencia de un repuesto y actualiza su estado automáticamente "
                "a 'Disponible' para habilitar su venta en el catálogo. Requiere rol de Gerencia, "
                "Administrador o Jefe de Ventas.",
)
def asignar_precio_repuesto(
    id_activo: UUID,
    payload: AsignarPrecioRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(verificar_rol_tasacion),
):
    try:
        activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == id_activo).first()
        if not activo:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Repuesto inventariado con ID '{id_activo}' no encontrado.",
            )

        # Regla de negocio: Solo se permite tasar o modificar precio si el activo está en estado 'Paletizado' o 'Disponible'
        # Bloquea intentos sobre repuestos 'Reservado', 'Vendido', 'En Desarme', 'Entregado', etc.
        estado_actual = db.query(Estado_Activo).filter(Estado_Activo.id_estado == activo.id_estado).first()
        nombre_estado_actual = estado_actual.nombre_estado.lower().strip() if estado_actual and estado_actual.nombre_estado else ""
        if nombre_estado_actual not in ["disponible", "paletizado"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"No es posible modificar el precio de un repuesto en estado '{estado_actual.nombre_estado if estado_actual else activo.id_estado}'. Solo se permite tasar repuestos en estado 'Disponible' o 'Paletizado'.",
            )

        activo.precio_minimo = payload.precio_minimo
        activo.precio_maximo = payload.precio_maximo
        activo.precio_referencia = payload.precio_referencia or payload.precio_maximo
        activo.fecha_actualizacion = datetime.now(timezone.utc).replace(tzinfo=None)

        estado_disponible = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Disponible").first()
        if not estado_disponible:
            estado_disponible = Estado_Activo(id_estado=1, nombre_estado="Disponible")
            db.add(estado_disponible)
            db.flush()

        activo.id_estado = estado_disponible.id_estado
        activo.version_lock = (activo.version_lock or 1) + 1

        db.commit()
        db.refresh(activo)

        return AsignarPrecioResponse(
            id_activo=activo.id_activo,
            sku_qr_fisico=activo.sku_qr_fisico,
            precio_minimo=activo.precio_minimo,
            precio_maximo=activo.precio_maximo,
            precio_referencia=activo.precio_referencia,
            estado_activo="Disponible",
            mensaje="Rango de precios asignado exitosamente. El repuesto ahora está disponible en el catálogo de ventas.",
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al asignar precio: {str(e)}",
        )


@router.get(
    "/{id_activo}",
    response_model=CatalogoItemResponse,
    summary="Detalle Completo de Activo con Imágenes",
)
def obtener_detalle_activo(
    id_activo: UUID,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    resultado = (
        db.query(
            Activo_Inventariado,
            Vehiculo_Origen,
            Categoria_Activo,
            Estado_Activo,
            Sucursal,
            Detalle_Motor,
            Detalle_Caja_Cambio,
        )
        .outerjoin(Vehiculo_Origen, Activo_Inventariado.id_vehiculo == Vehiculo_Origen.id_vehiculo)
        .join(Categoria_Activo, Activo_Inventariado.id_categoria == Categoria_Activo.id_categoria)
        .join(Estado_Activo, Activo_Inventariado.id_estado == Estado_Activo.id_estado)
        .join(Sucursal, Activo_Inventariado.id_sucursal_actual == Sucursal.id_sucursal)
        .outerjoin(Detalle_Motor, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
        .outerjoin(Detalle_Caja_Cambio, Activo_Inventariado.id_activo == Detalle_Caja_Cambio.id_activo)
        .filter(Activo_Inventariado.id_activo == id_activo)
        .first()
    )

    if not resultado:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado.",
        )

    activo, vehiculo, cat, est, suc, motor, caja = resultado

    cilindrada_val = None
    combustible_val = None
    transmision_val = None
    numero_motor_val = None

    if cat.id_categoria == 1 and motor:
        cilindrada_val = motor.cilindrada
        combustible_val = motor.combustible
        transmision_val = motor.transmision_tipo
        numero_motor_val = motor.numero_motor
    elif cat.id_categoria == 2:
        transmision_val = caja.transmision_tipo if caja else None
        # Herencia para Caja de Cambios desde Detalle_Motor del mismo id_vehiculo (SPEC-HU-TAREA-17)
        if activo.id_vehiculo:
            motor_donante = (
                db.query(Detalle_Motor)
                .join(Activo_Inventariado, Activo_Inventariado.id_activo == Detalle_Motor.id_activo)
                .filter(
                    Activo_Inventariado.id_vehiculo == activo.id_vehiculo,
                    Activo_Inventariado.id_categoria == 1,
                )
                .first()
            )
            if motor_donante:
                cilindrada_val = motor_donante.cilindrada
                combustible_val = motor_donante.combustible
        numero_motor_val = None
    else:
        if motor:
            cilindrada_val = motor.cilindrada
            combustible_val = motor.combustible
            transmision_val = motor.transmision_tipo
            if cat.id_categoria == 1:
                numero_motor_val = motor.numero_motor
        elif caja:
            transmision_val = caja.transmision_tipo

    fotos_db = (
        db.query(Multimedia_Activo.url_storage)
        .filter(Multimedia_Activo.id_activo == activo.id_activo)
        .all()
    )
    lista_fotos = [f[0] for f in fotos_db] if fotos_db else []

    return CatalogoItemResponse(
        id_activo=activo.id_activo,
        sku_qr_fisico=activo.sku_qr_fisico,
        precio_referencia=activo.precio_referencia,
        precio_minimo=activo.precio_minimo,
        precio_maximo=activo.precio_maximo,
        id_categoria=cat.id_categoria,
        nombre_categoria=cat.nombre_categoria,
        id_sucursal_actual=suc.id_sucursal,
        nombre_sucursal=suc.nombre_sucursal,
        id_vehiculo=vehiculo.id_vehiculo if vehiculo else None,
        marca=vehiculo.marca if vehiculo else None,
        modelo=vehiculo.modelo if vehiculo else None,
        anio=vehiculo.anio if vehiculo else None,
        traccion=vehiculo.traccion if vehiculo else None,
        cilindrada=cilindrada_val,
        combustible=combustible_val,
        transmision_tipo=transmision_val,
        ubicacion_pasillo=activo.ubicacion_pasillo,
        ubicacion_galpon=activo.ubicacion_galpon,
        ubicacion_pallet=activo.ubicacion_pallet,
        observacion_estado=activo.observacion_estado,
        numero_motor=numero_motor_val,
        id_estado=est.id_estado,
        estado_activo=est.nombre_estado,
        version_lock=activo.version_lock or 1,
        reservado_por=activo.reservado_por,
        qr_impreso=activo.qr_impreso if activo.qr_impreso is not None else False,
        imagenes=lista_fotos,
    )


@router.patch(
    "/{id_activo}",
    response_model=EditarActivoResponse,
    summary="Edición Directa de Activo Inventariado (HU-11)",
    description="Permite a operarios de Bodega y Administradores actualizar ubicación física "
                "y notas técnicas con control de concurrencia optimista (version_lock).",
)
def editar_activo_inventariado(
    id_activo: UUID,
    payload: EditarActivoRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_bodeguero_or_admin),
):
    # 1. Verificar existencia previa
    activo_existente = (
        db.query(Activo_Inventariado)
        .filter(Activo_Inventariado.id_activo == id_activo)
        .first()
    )
    if not activo_existente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado.",
        )

    # 2. Regla de Negocio: Solo activos en estado 'Disponible' o 'Paletizado' pueden editar su ubicación
    # id_estado: 1 = Disponible, 7 = Paletizado
    estado_obj = (
        db.query(Estado_Activo)
        .filter(Estado_Activo.id_estado == activo_existente.id_estado)
        .first()
    )
    nombre_estado = estado_obj.nombre_estado if estado_obj else ""
    nombre_estado_lower = nombre_estado.strip().lower()
    estados_permitidos_id = {1, 7}
    estados_permitidos_nombre = {"disponible", "paletizado"}

    if activo_existente.id_estado not in estados_permitidos_id and nombre_estado_lower not in estados_permitidos_nombre:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Solo es posible modificar la ubicación de repuestos en estado 'Disponible' o 'Paletizado'. El artículo actual se encuentra en estado '{nombre_estado or activo_existente.id_estado}'.",
        )

    # 3. Transacción atómica con control de concurrencia optimista (ubicación y especificaciones)
    try:
        update_values = {
            "version_lock": Activo_Inventariado.version_lock + 1,
            "fecha_actualizacion": datetime.now(timezone.utc).replace(tzinfo=None),
        }
        if payload.ubicacion_pasillo is not None:
            update_values["ubicacion_pasillo"] = payload.ubicacion_pasillo
        if payload.ubicacion_galpon is not None:
            update_values["ubicacion_galpon"] = payload.ubicacion_galpon
        if payload.ubicacion_pallet is not None:
            update_values["ubicacion_pallet"] = payload.ubicacion_pallet
        if payload.observacion_estado is not None:
            update_values["observacion_estado"] = payload.observacion_estado

        stmt = (
            update(Activo_Inventariado)
            .where(
                Activo_Inventariado.id_activo == id_activo,
                Activo_Inventariado.version_lock == payload.version_lock_esperado,
            )
            .values(**update_values)
        )
        result = db.execute(stmt)

        if result.rowcount == 0:
            # Falló por colisión de concurrencia optimista
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="La información de este repuesto fue modificada por otro usuario recientemente. "
                       "Los datos se actualizarán ahora para que revises los cambios antes de volver a editar.",
            )

        # Actualizar datos en Vehiculo_Origen si se especificaron
        traccion_actualizada = None
        marca_actualizada = None
        modelo_actualizado = None
        anio_actualizado = None

        vehiculo_obj = None
        if activo_existente.id_vehiculo:
            vehiculo_obj = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo_existente.id_vehiculo).first()
        elif any(v is not None for v in [payload.marca, payload.modelo, payload.anio, payload.traccion]):
            # Si el activo no tenía vehículo asociado pero se ingresaron datos vehiculares, creamos el Vehiculo_Origen
            num_ingreso_temp = f"ING-{uuid.uuid4().hex[:6].upper()}"
            nuevo_vehiculo = Vehiculo_Origen(
                id_vehiculo=uuid.uuid4(),
                numero_ingreso=num_ingreso_temp,
                patente=f"SPPU-{num_ingreso_temp}",
                marca=payload.marca.strip() if payload.marca else "Desconocida",
                modelo=payload.modelo.strip() if payload.modelo else "Desconocido",
                anio=payload.anio if payload.anio is not None else 2000,
                traccion=payload.traccion.strip() if payload.traccion else None,
                estado="Activo",
            )
            db.add(nuevo_vehiculo)
            db.flush()
            activo_existente.id_vehiculo = nuevo_vehiculo.id_vehiculo
            vehiculo_obj = nuevo_vehiculo

        if vehiculo_obj:
            if payload.traccion is not None:
                vehiculo_obj.traccion = payload.traccion.strip() if payload.traccion else None
            if payload.marca is not None and payload.marca.strip():
                vehiculo_obj.marca = payload.marca.strip()
            if payload.modelo is not None and payload.modelo.strip():
                vehiculo_obj.modelo = payload.modelo.strip()
            if payload.anio is not None:
                vehiculo_obj.anio = payload.anio
            vehiculo_obj.fecha_actualizacion = datetime.now(timezone.utc).replace(tzinfo=None)

            traccion_actualizada = vehiculo_obj.traccion
            marca_actualizada = vehiculo_obj.marca
            modelo_actualizado = vehiculo_obj.modelo
            anio_actualizado = vehiculo_obj.anio

        # Actualizar o insertar especificaciones técnicas (Motor, Caja o Repuestos generales)
        if activo_existente.id_categoria == 1:
            motor = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == id_activo).first()
            if not motor:
                motor = Detalle_Motor(id_activo=id_activo)
                db.add(motor)
            if payload.numero_motor is not None:
                motor.numero_motor = payload.numero_motor.strip() if payload.numero_motor else None
            if payload.cilindrada is not None:
                motor.cilindrada = payload.cilindrada.strip() if payload.cilindrada else None
            if payload.combustible is not None:
                motor.combustible = payload.combustible.strip() if payload.combustible else None
            if payload.transmision_tipo is not None:
                motor.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None

            # Sincronizar caja donante del mismo vehículo si existe y se actualizó la transmisión
            if activo_existente.id_vehiculo and payload.transmision_tipo is not None:
                caja_donante = (
                    db.query(Detalle_Caja_Cambio)
                    .join(Activo_Inventariado, Detalle_Caja_Cambio.id_activo == Activo_Inventariado.id_activo)
                    .filter(Activo_Inventariado.id_vehiculo == activo_existente.id_vehiculo)
                    .first()
                )
                if caja_donante:
                    caja_donante.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None

        elif activo_existente.id_categoria == 2:
            caja = db.query(Detalle_Caja_Cambio).filter(Detalle_Caja_Cambio.id_activo == id_activo).first()
            if not caja:
                caja = Detalle_Caja_Cambio(id_activo=id_activo)
                db.add(caja)
            if payload.transmision_tipo is not None:
                caja.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None

            # Si se especificó cilindrada, combustible o número de motor en una caja:
            # - Actualizamos o creamos Detalle_Motor propio para este activo (para persistencia directa)
            if payload.cilindrada is not None or payload.combustible is not None or payload.numero_motor is not None:
                motor_propio = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == id_activo).first()
                if not motor_propio:
                    motor_propio = Detalle_Motor(id_activo=id_activo)
                    db.add(motor_propio)
                if payload.cilindrada is not None:
                    motor_propio.cilindrada = payload.cilindrada.strip() if payload.cilindrada else None
                if payload.combustible is not None:
                    motor_propio.combustible = payload.combustible.strip() if payload.combustible else None
                if payload.numero_motor is not None:
                    motor_propio.numero_motor = payload.numero_motor.strip() if payload.numero_motor else None
                if payload.transmision_tipo is not None:
                    motor_propio.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None

            # - Si existe un motor donante asociado al mismo id_vehiculo, mantenemos sincronizada la cilindrada, combustible y transmisión
            if activo_existente.id_vehiculo:
                motor_donante = (
                    db.query(Detalle_Motor)
                    .join(Activo_Inventariado, Detalle_Motor.id_activo == Activo_Inventariado.id_activo)
                    .filter(Activo_Inventariado.id_vehiculo == activo_existente.id_vehiculo, Activo_Inventariado.id_activo != id_activo)
                    .first()
                )
                if motor_donante:
                    if payload.cilindrada is not None:
                        motor_donante.cilindrada = payload.cilindrada.strip() if payload.cilindrada else None
                    if payload.combustible is not None:
                        motor_donante.combustible = payload.combustible.strip() if payload.combustible else None
                    if payload.transmision_tipo is not None:
                        motor_donante.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None
        else:
            if any(v is not None for v in [payload.cilindrada, payload.combustible, payload.numero_motor, payload.transmision_tipo]):
                motor_propio = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == id_activo).first()
                if not motor_propio:
                    motor_propio = Detalle_Motor(id_activo=id_activo)
                    db.add(motor_propio)
                if payload.cilindrada is not None:
                    motor_propio.cilindrada = payload.cilindrada.strip() if payload.cilindrada else None
                if payload.combustible is not None:
                    motor_propio.combustible = payload.combustible.strip() if payload.combustible else None
                if payload.numero_motor is not None:
                    motor_propio.numero_motor = payload.numero_motor.strip() if payload.numero_motor else None
                if payload.transmision_tipo is not None:
                    motor_propio.transmision_tipo = payload.transmision_tipo.strip() if payload.transmision_tipo else None

        db.commit()

        # Recargar activo y detalles actualizados
        db.refresh(activo_existente)
        motor_actual = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == id_activo).first()
        caja_actual = db.query(Detalle_Caja_Cambio).filter(Detalle_Caja_Cambio.id_activo == id_activo).first()

        motor_donante_lectura = None
        if activo_existente.id_vehiculo and activo_existente.id_categoria == 2 and not motor_actual:
            motor_donante_lectura = (
                db.query(Detalle_Motor)
                .join(Activo_Inventariado, Detalle_Motor.id_activo == Activo_Inventariado.id_activo)
                .filter(Activo_Inventariado.id_vehiculo == activo_existente.id_vehiculo)
                .first()
            )

        cilindrada_res = (motor_actual.cilindrada if motor_actual else None) or (motor_donante_lectura.cilindrada if motor_donante_lectura else None)
        combustible_res = (motor_actual.combustible if motor_actual else None) or (motor_donante_lectura.combustible if motor_donante_lectura else None)
        transmision_res = (
            (caja_actual.transmision_tipo if caja_actual else None)
            or (motor_actual.transmision_tipo if motor_actual else None)
            or (motor_donante_lectura.transmision_tipo if motor_donante_lectura else None)
        )

        return EditarActivoResponse(
            id_activo=activo_existente.id_activo,
            sku_qr_fisico=activo_existente.sku_qr_fisico,
            ubicacion_pasillo=activo_existente.ubicacion_pasillo,
            ubicacion_galpon=activo_existente.ubicacion_galpon,
            ubicacion_pallet=activo_existente.ubicacion_pallet,
            observacion_estado=activo_existente.observacion_estado,
            numero_motor=motor_actual.numero_motor if motor_actual else None,
            cilindrada=cilindrada_res,
            combustible=combustible_res,
            transmision_tipo=transmision_res,
            traccion=traccion_actualizada,
            marca=marca_actualizada,
            modelo=modelo_actualizado,
            anio=anio_actualizado,
            version_lock=activo_existente.version_lock,
            mensaje="Activo actualizado exitosamente.",
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional: {str(e)}",
        )


@router.post(
    "/{id_activo}/fotos",
    summary="Subir nuevas fotos comerciales a un activo",
    description="Sube fotografías a Supabase Storage y las vincula en Multimedia_Activo.",
)
async def subir_fotos_activo(
    id_activo: UUID,
    fotos: List[UploadFile] = File(...),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_bodeguero_or_admin),
):
    activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == id_activo).first()
    if not activo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado.",
        )

    if not supabase:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="El servicio de almacenamiento Supabase no está configurado en el servidor.",
        )

    folio = str(activo.id_activo)[:8]
    if activo.id_vehiculo:
        vehiculo = db.query(Vehiculo_Origen).filter(Vehiculo_Origen.id_vehiculo == activo.id_vehiculo).first()
        if vehiculo and vehiculo.numero_ingreso:
            folio = vehiculo.numero_ingreso

    BUCKET_NAME = "multimedia-activos"
    try:
        supabase.storage.create_bucket(BUCKET_NAME, options={"public": True})
    except Exception:
        pass

    prefijo = "moto" if activo.id_categoria == 1 else "caja"
    urls_subidas = []

    for foto in fotos:
        contenido = await foto.read()
        ts = int(datetime.now(timezone.utc).timestamp())
        random_suffix = uuid.uuid4().hex[:6]
        path_nube = f"{folio}/{prefijo}_{folio}_extra_{ts}_{random_suffix}.jpg"

        def _subir_sync(path_n, data_bytes):
            supabase.storage.from_(BUCKET_NAME).upload(
                path=path_n,
                file=data_bytes,
                file_options={"cache-control": "3600", "content-type": "image/jpeg", "upsert": "true"}
            )
            return supabase.storage.from_(BUCKET_NAME).get_public_url(path_n)

        try:
            url_publica = await asyncio.to_thread(_subir_sync, path_nube, contenido)
            urls_subidas.append(url_publica)
            nueva_media = Multimedia_Activo(
                id_activo=id_activo,
                url_storage=url_publica,
                tipo_archivo="imagen",
            )
            db.add(nueva_media)
        except Exception as e:
            print(f"❌ Error al subir foto comercial extra: {e}")

    db.commit()

    imagenes_actuales = [
        m.url_storage for m in db.query(Multimedia_Activo).filter(Multimedia_Activo.id_activo == id_activo).all()
    ]

    return {
        "status": "success",
        "mensaje": f"{len(urls_subidas)} fotografía(s) subida(s) exitosamente.",
        "imagenes": imagenes_actuales,
    }


@router.delete(
    "/{id_activo}/fotos",
    summary="Eliminar una foto comercial de un activo",
    description="Elimina una fotografía de Multimedia_Activo y del bucket de Supabase Storage.",
)
def eliminar_foto_activo(
    id_activo: UUID,
    url: str = Query(..., description="URL de almacenamiento de la foto a eliminar"),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_bodeguero_or_admin),
):
    activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == id_activo).first()
    if not activo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado.",
        )

    multimedia = db.query(Multimedia_Activo).filter(
        Multimedia_Activo.id_activo == id_activo,
        Multimedia_Activo.url_storage == url.strip(),
    ).first()

    if not multimedia:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fotografía no encontrada en los registros de este activo.",
        )

    BUCKET_NAME = "multimedia-activos"
    if supabase:
        try:
            if f"{BUCKET_NAME}/" in url:
                path_archivo = url.split(f"{BUCKET_NAME}/")[-1]
                supabase.storage.from_(BUCKET_NAME).remove([path_archivo])
        except Exception as se:
            print(f"⚠️ Error al eliminar archivo de Supabase Storage: {se}")

    db.delete(multimedia)
    db.commit()

    imagenes_actuales = [
        m.url_storage for m in db.query(Multimedia_Activo).filter(Multimedia_Activo.id_activo == id_activo).all()
    ]

    return {
        "status": "success",
        "mensaje": "Fotografía eliminada exitosamente.",
        "imagenes": imagenes_actuales,
    }


@router.get("/ingreso/{numero_ingreso}", status_code=200)
def buscar_activo_por_numero_ingreso(
    numero_ingreso: str,
    db: Session = Depends(get_db),
    usuario_logeado: Usuario = Depends(get_current_user),
):
    """
    SPEC-HU-TAREA-14: Búsqueda directa de activo/vehículo por número de ingreso
    para acceso rápido al flujo de paletizado y enriquecimiento.
    """
    folio = numero_ingreso.strip()
    if not folio:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El número de ingreso no puede estar vacío.",
        )

    vehiculo = db.query(Vehiculo_Origen).filter(
        Vehiculo_Origen.numero_ingreso == folio
    ).first()

    if not vehiculo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Número de ingreso no encontrado en la base de datos.",
        )

    # Buscar activos asociados al vehículo
    activos = db.query(Activo_Inventariado).filter(
        Activo_Inventariado.id_vehiculo == vehiculo.id_vehiculo,
        Activo_Inventariado.estado == "Activo",
    ).all()

    # Un activo está pendiente de paletizado únicamente si id_estado == 5 (En Desarme) Y no tiene ubicación física válida
    activos_pendientes = [
        a for a in activos
        if a.id_estado == 5
        and (
            not a.ubicacion_pasillo
            or a.ubicacion_pasillo in ("", "S/P")
            or not a.ubicacion_pallet
            or a.ubicacion_pallet in ("", "S/P")
        )
    ]

    if not activos or not activos_pendientes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.",
        )

    # Obtener detalles de motor (Categoría 1)
    activo_motor = next((a for a in activos if a.id_categoria == 1), None)
    detalle_motor = None
    if activo_motor:
        detalle_motor = db.query(Detalle_Motor).filter(Detalle_Motor.id_activo == activo_motor.id_activo).first()

    # Obtener detalles de caja de cambios (Categoría 2)
    activo_caja = next((a for a in activos if a.id_categoria == 2), None)
    detalle_caja = None
    if activo_caja:
        detalle_caja = db.query(Detalle_Caja_Cambio).filter(Detalle_Caja_Cambio.id_activo == activo_caja.id_activo).first()

    return {
        "id_vehiculo": str(vehiculo.id_vehiculo),
        "numero_ingreso": vehiculo.numero_ingreso,
        "pendiente_paletizado": True,
        "vehiculo": {
            "id_vehiculo": str(vehiculo.id_vehiculo),
            "marca": vehiculo.marca,
            "modelo": vehiculo.modelo,
            "anio": vehiculo.anio,
            "patente": vehiculo.patente,
            "traccion": vehiculo.traccion,
            "numero_ingreso": vehiculo.numero_ingreso,
        },
        "motor": {
            "id_activo": str(activo_motor.id_activo) if activo_motor else None,
            "id_estado": activo_motor.id_estado if activo_motor else None,
            "numero_motor": detalle_motor.numero_motor if detalle_motor else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "transmision_tipo": detalle_motor.transmision_tipo if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
            "pendiente": activo_motor in activos_pendientes if activo_motor else False,
        },
        "caja_cambios": {
            "id_activo": str(activo_caja.id_activo) if activo_caja else None,
            "id_estado": activo_caja.id_estado if activo_caja else None,
            "transmision_tipo": detalle_caja.transmision_tipo if detalle_caja else "S/A",
            "cilindrada": detalle_motor.cilindrada if detalle_motor else "S/A",
            "combustible": detalle_motor.combustible if detalle_motor else "S/A",
            "traccion": vehiculo.traccion if vehiculo else "S/A",
            "pendiente": activo_caja in activos_pendientes if activo_caja else False,
        },
        "total_pendientes": len(activos_pendientes),
    }


@router.post(
    "/{id_activo}/despaletizar",
    summary="Despaletizar repuesto y devolver a estado En Desarme",
    description="Permite a bodega revertir un activo paletizado o disponible por error al estado 'En Desarme', liberando la ubicación física y reiniciando el QR.",
)
def despaletizar_activo(
    id_activo: UUID,
    payload: Optional[DespaletizarActivoRequest] = None,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(require_bodeguero_or_admin),
):
    activo = (
        db.query(Activo_Inventariado)
        .filter(Activo_Inventariado.id_activo == id_activo)
        .first()
    )
    if not activo:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activo inventariado con ID '{id_activo}' no encontrado.",
        )

    # 1. Regla de Negocio: Solo activos en estado 'Paletizado' (7) o 'Disponible' (1) pueden ser despaletizados
    estado_actual = (
        db.query(Estado_Activo)
        .filter(Estado_Activo.id_estado == activo.id_estado)
        .first()
    )
    nombre_estado_actual = (estado_actual.nombre_estado if estado_actual else "").strip().lower()
    estados_permitidos = {"disponible", "paletizado"}
    ids_permitidos = {1, 7}

    if activo.id_estado not in ids_permitidos and nombre_estado_actual not in estados_permitidos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"No es posible despaletizar un repuesto en estado '{estado_actual.nombre_estado if estado_actual else activo.id_estado}'. "
                   f"Solo se pueden revertir repuestos en estado 'Paletizado' o 'Disponible'.",
        )

    # 2. Obtener estado 'En Desarme' (id_estado = 5)
    estado_desarme = (
        db.query(Estado_Activo)
        .filter(
            or_(
                Estado_Activo.id_estado == 5,
                func.lower(Estado_Activo.nombre_estado) == "en desarme",
                func.lower(Estado_Activo.nombre_estado) == "desarme",
            )
        )
        .first()
    )
    id_estado_desarme = estado_desarme.id_estado if estado_desarme else 5

    try:
        # 3. Transacción atómica de reversión y captura de ubicación anterior
        ubicacion_anterior = f"Galpón {activo.ubicacion_galpon or 'S/G'} | Pasillo {activo.ubicacion_pasillo or 'S/P'} | Pallet {activo.ubicacion_pallet or 'S/P'}"
        motivo = payload.motivo if payload else "Reversión a desarme"
        observacion = payload.observacion if payload else "Despaletizado operativo sin justificación detallada"

        # Registrar trazabilidad en Bitacora_Movimiento_Inventario
        bitacora = Bitacora_Movimiento_Inventario(
            id_activo=activo.id_activo,
            id_usuario=current_user.id_usuario,
            tipo_evento="DESPALETIZADO",
            ubicacion_anterior=ubicacion_anterior,
            ubicacion_nueva="En Desarme / Sin Pallet",
            motivo=motivo,
            observacion=observacion,
            fecha_registro=datetime.now(timezone.utc),
        )
        db.add(bitacora)

        activo.id_estado = id_estado_desarme
        activo.ubicacion_galpon = None
        activo.ubicacion_pasillo = None
        activo.ubicacion_pallet = None
        activo.qr_impreso = False
        activo.version_lock = (activo.version_lock or 0) + 1
        activo.fecha_actualizacion = datetime.now(timezone.utc).replace(tzinfo=None)

        # Nota de auditoría en observacion_estado
        nombre_completo = f"{current_user.nombres} {current_user.apellidos}".strip()
        nota_reversion = f"[Despaletizado por {nombre_completo} el {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')}: {motivo}]"
        if activo.observacion_estado:
            activo.observacion_estado = f"{activo.observacion_estado} | {nota_reversion}"
        else:
            activo.observacion_estado = nota_reversion

        # 4. Limpiar fotos físicas del bucket de Supabase Storage y registros en Multimedia_Activo
        fotos_asociadas = (
            db.query(Multimedia_Activo)
            .filter(Multimedia_Activo.id_activo == id_activo)
            .all()
        )
        BUCKET_NAME = "multimedia-activos"
        if supabase and fotos_asociadas:
            rutas_a_borrar = []
            for f in fotos_asociadas:
                url = f.url_storage or ""
                if f"{BUCKET_NAME}/" in url:
                    path_archivo = url.split(f"{BUCKET_NAME}/")[-1].split("?")[0].strip()
                    if path_archivo:
                        rutas_a_borrar.append(path_archivo)
            if rutas_a_borrar:
                try:
                    supabase.storage.from_(BUCKET_NAME).remove(rutas_a_borrar)
                except Exception as se:
                    print(f"⚠️ Error al eliminar archivos físicos de Supabase Storage: {se}")

        db.query(Multimedia_Activo).filter(Multimedia_Activo.id_activo == id_activo).delete()

        db.commit()
        db.refresh(activo)

        # Obtener descripción enriquecida de pieza para mensaje gerencial (Categoría + Marca + Modelo + Cilindrada + Año)
        from routers.bodega import construir_descripcion_repuesto
        pieza_desc = construir_descripcion_repuesto(db, activo)

        # Disparar alerta asíncrona a Telegram para Gerencia
        background_tasks.add_task(
            TelegramService.notificar_repuesto_despaletizado,
            sku=activo.sku_qr_fisico,
            pieza_nombre=pieza_desc,
            ubicacion_anterior=ubicacion_anterior,
            bodeguero_nombre=nombre_completo,
            motivo_despaletizado=motivo,
            observacion_despaletizado=observacion,
        )

        return {
            "id_activo": str(activo.id_activo),
            "sku_qr_fisico": activo.sku_qr_fisico,
            "mensaje": "Activo despaletizado exitosamente. Ha retornado al estado 'En Desarme' y su ubicación ha sido liberada.",
            "id_estado": activo.id_estado,
            "version_lock": activo.version_lock,
            "qr_impreso": activo.qr_impreso,
            "ubicacion_galpon": activo.ubicacion_galpon,
            "ubicacion_pasillo": activo.ubicacion_pasillo,
            "ubicacion_pallet": activo.ubicacion_pallet,
            "ubicacion_anterior": ubicacion_anterior,
            "motivo": motivo,
        }

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error al revertir paletizado del activo: {str(e)}",
        )