import uuid
from datetime import datetime, time, timezone, timedelta
from zoneinfo import ZoneInfo
from database import SessionLocal, engine, Base
from models import (
    Rol, Categoria_Activo, Estado_Activo, 
    Region, Comuna, Sucursal, Usuario,
    Orden_Venta, Transaccion_Pago, Despacho, Cliente
)

from sqlalchemy import text

def seed_data():
    # 1. Esta es la línea mágica que lee models.py y crea las tablas si no existen
    print("Verificando y creando tablas en PostgreSQL...")
    Base.metadata.create_all(bind=engine)

    # Abrimos la sesión de conexión a la base de datos
    db = SessionLocal()

    try:
        # Sincronizar secuencias de IDs en PostgreSQL para evitar colisiones UniqueViolation
        try:
            db.execute(text("""
                SELECT setval(pg_get_serial_sequence('"Estado_Activo"', 'id_estado'), COALESCE((SELECT MAX(id_estado) FROM "Estado_Activo"), 1));
                SELECT setval(pg_get_serial_sequence('"Rol"', 'id_rol'), COALESCE((SELECT MAX(id_rol) FROM "Rol"), 1));
                SELECT setval(pg_get_serial_sequence('"Categoria_Activo"', 'id_categoria'), COALESCE((SELECT MAX(id_categoria) FROM "Categoria_Activo"), 1));
                SELECT setval(pg_get_serial_sequence('"Sucursal"', 'id_sucursal'), COALESCE((SELECT MAX(id_sucursal) FROM "Sucursal"), 1));
            """))
            db.commit()
        except Exception as seq_err:
            db.rollback()
            print(f"- Nota sincronizando secuencias: {seq_err}")

        # 2. Poblar Roles
        roles_base = ["Bodeguero", "Vendedor", "Caja", "Gerente", "Administrador", "Auditor"]
        for nombre in roles_base:
            if not db.query(Rol).filter_by(nombre_rol=nombre).first():
                db.add(Rol(nombre_rol=nombre))
        db.commit()
        print("- Roles creados.")

        # 3. Poblar Categorías de Inventario
        categorias_base = ["Motor", "Caja de Cambios", "Accesorio"]
        for cat in categorias_base:
            if not db.query(Categoria_Activo).filter_by(nombre_categoria=cat).first():
                db.add(Categoria_Activo(nombre_categoria=cat))
        db.commit()
        print("- Categorias creados.")

        # 4. Poblar Estados del Activo (HU-3.6: incluye 'Entregado' y 'Paletizado' para ciclo de tasación)
        estados_base = ["En Desarme", "Disponible", "Reservado", "Vendido", "En Importación", "Entregado", "Paletizado"]
        for est in estados_base:
            if not db.query(Estado_Activo).filter_by(nombre_estado=est).first():
                db.add(Estado_Activo(nombre_estado=est))
                print(f"  + Estado creado: {est}")
        db.commit()
        print("- Estados de activo verificados y creados.")

        # 5. Configurar Geografía y Sucursales Oficiales (1: Viña del Mar - Casa Matriz, 2: Limache)
        region_valpo = db.query(Region).filter_by(nombre_region="Valparaíso").first()
        if not region_valpo:
            region_valpo = Region(nombre_region="Valparaíso")
            db.add(region_valpo)
            db.commit()

        comuna_vina = db.query(Comuna).filter_by(nombre_comuna="Viña del Mar").first()
        if not comuna_vina:
            comuna_vina = Comuna(nombre_comuna="Viña del Mar", id_region=region_valpo.id_region)
            db.add(comuna_vina)
            db.commit()

        comuna_limache = db.query(Comuna).filter_by(nombre_comuna="Limache").first()
        if not comuna_limache:
            comuna_limache = Comuna(nombre_comuna="Limache", id_region=region_valpo.id_region)
            db.add(comuna_limache)
            db.commit()

        # Sucursal 1: Viña del Mar (Casa Matriz)
        sucursal_matriz = db.query(Sucursal).filter(
            (Sucursal.id_sucursal == 1) | (Sucursal.nombre_sucursal.ilike("%Viña%")) | (Sucursal.nombre_sucursal.ilike("%Matriz%"))
        ).first()
        if not sucursal_matriz:
            sucursal_matriz = Sucursal(
                id_sucursal=1,
                nombre_sucursal="Viña del Mar",
                direccion="Camino Internacional 4105",
                sector="Barrio Industrial",
                id_comuna=comuna_vina.id_comuna
            )
            db.add(sucursal_matriz)
            db.commit()
        else:
            if sucursal_matriz.nombre_sucursal != "Viña del Mar":
                sucursal_matriz.nombre_sucursal = "Viña del Mar"
                db.commit()
        print("- Sucursal 1 (Viña del Mar - Casa Matriz) configurada.")

        # Sucursal 2: Limache
        sucursal_limache = db.query(Sucursal).filter(
            (Sucursal.id_sucursal == 2) | (Sucursal.nombre_sucursal.ilike("%Limache%"))
        ).first()
        if not sucursal_limache:
            sucursal_limache = Sucursal(
                id_sucursal=2,
                nombre_sucursal="Limache",
                direccion="Avenida Palmira Romano Sur 1200",
                sector="Sector Industrial Limache",
                id_comuna=comuna_limache.id_comuna
            )
            db.add(sucursal_limache)
            db.commit()
        else:
            if sucursal_limache.nombre_sucursal != "Limache":
                sucursal_limache.nombre_sucursal = "Limache"
                db.commit()
        print("- Sucursal 2 (Limache) configurada.")

        # 6. Crear el Usuario Administrador
        rol_admin = db.query(Rol).filter_by(nombre_rol="Administrador").first()
        admin_user = db.query(Usuario).filter_by(email="admin@cresal.cl").first()
        
        if not admin_user:
            admin_user = Usuario(
                id_rol=rol_admin.id_rol,
                id_sucursal=sucursal_matriz.id_sucursal,
                rut_usuario="11111111-1",
                nombres="Admin",
                apellidos="Cresal",
                email="admin@cresal.cl",
                # Nota: Más adelante usaremos passlib para encriptar. Por ahora usamos un hash falso para el MVP.
                password_hash="hash_temporal_1234", 
                pin_acceso="9999"
            )
            db.add(admin_user)
            db.commit()
            print("- Usuario Administrador (admin@cresal.cl) creado exitosamente.")

        # 7. Poblar Órdenes y Pagos para el Dashboard Ejecutivo (HU-5.1 y HU-5.2)
        seed_gerencia_transacciones(db)

        print("\n[OK] Poblamiento de Base de Datos completado con exito!")

    except Exception as e:
        db.rollback()
        print(f"[ERROR] Error al poblar la base de datos: {e}")
    finally:
        db.close()


def seed_gerencia_transacciones(db):
    """
    Puebla la base de datos Supabase con órdenes y transacciones reales para
    el Dashboard Ejecutivo (HU-5.1 y HU-5.2), incluyendo ventas de hoy
    y acumulado MTD (Mes en curso) para ambas sucursales.
    """
    print("\n--- Verificando y poblando datos para Dashboard de Gerencia ---")
    tz_chile = ZoneInfo("America/Santiago")
    ahora_chile = datetime.now(tz_chile)
    inicio_hoy_chile = datetime.combine(ahora_chile.date(), time.min, tzinfo=tz_chile)
    fin_hoy_chile = datetime.combine(ahora_chile.date(), time.max, tzinfo=tz_chile)
    inicio_hoy_utc = inicio_hoy_chile.astimezone(timezone.utc).replace(tzinfo=None)
    fin_hoy_utc = fin_hoy_chile.astimezone(timezone.utc).replace(tzinfo=None)
    inicio_mes_chile = datetime.combine(ahora_chile.date().replace(day=1), time.min, tzinfo=tz_chile)
    inicio_mes_utc = inicio_mes_chile.astimezone(timezone.utc).replace(tzinfo=None)

    # 1. Obtener usuarios necesarios
    admin_user = db.query(Usuario).filter(Usuario.email == "admin@cresal.cl").first()
    vendedor_user = db.query(Usuario).filter(Usuario.id_rol == 2).first() or admin_user
    cajera_user = db.query(Usuario).filter(Usuario.id_rol == 3).first() or admin_user

    # 2. Obtener clientes
    clientes = db.query(Cliente).all()
    if not clientes:
        print("  Creando cliente base...")
        cliente_demo = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="12.345.678-9",
            nombres="Roberto",
            apellidos="Silva Gerente",
            correo="cliente.demo@cresal.cl",
            telefono="+56912345678",
            consentimiento_legal=True,
            estado="Activo",
        )
        db.add(cliente_demo)
        db.commit()
        clientes = [cliente_demo]

    # 3. Obtener sucursales
    suc_1 = db.query(Sucursal).filter(Sucursal.id_sucursal == 1).first()
    suc_2 = db.query(Sucursal).filter(Sucursal.id_sucursal == 2).first()
    id_suc_1 = suc_1.id_sucursal if suc_1 else 1
    id_suc_2 = suc_2.id_sucursal if suc_2 else (suc_1.id_sucursal if suc_1 else 1)

    # 4. Verificar si ya existen pagos de hoy
    pagos_hoy_count = (
        db.query(Transaccion_Pago)
        .filter(
            Transaccion_Pago.estado_pago == "Procesado",
            Transaccion_Pago.fecha_pago.between(inicio_hoy_utc, fin_hoy_utc),
        )
        .count()
    )

    if pagos_hoy_count == 0:
        print("  Insertando 5 órdenes pagadas para el día de HOY ($5.000.000 total)...")
        ventas_hoy_specs = [
            {"metodo": "Transferencia Bancaria", "monto": 1350000, "sucursal": id_suc_1},
            {"metodo": "Tarjeta Crédito", "monto": 1250000, "sucursal": id_suc_1},
            {"metodo": "Webpay", "monto": 1050000, "sucursal": id_suc_1},
            {"metodo": "Efectivo en Caja", "monto": 750000, "sucursal": id_suc_2},
            {"metodo": "Tarjeta Débito", "monto": 600000, "sucursal": id_suc_2},
        ]

        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
        for i, spec in enumerate(ventas_hoy_specs):
            cliente = clientes[i % len(clientes)]
            id_orden = uuid.uuid4()
            folio_str = f"ORD-HOY-{str(id_orden)[:4].upper()}"
            orden = Orden_Venta(
                id_orden=id_orden,
                id_cliente=cliente.id_cliente,
                id_vendedor=vendedor_user.id_usuario,
                id_cajera=cajera_user.id_usuario,
                id_sucursal=spec["sucursal"],
                estado_orden="Pagada",
                total_venta=spec["monto"],
                monto_pendiente=0,
                qr_transaccional_salida=folio_str,
                fecha_creacion=now_utc - timedelta(hours=i),
                fecha_actualizacion=now_utc - timedelta(hours=i),
            )
            db.add(orden)
            db.flush()

            pago = Transaccion_Pago(
                id_pago=uuid.uuid4(),
                id_orden=orden.id_orden,
                monto=spec["monto"],
                metodo_pago=spec["metodo"],
                estado_pago="Procesado",
                fecha_pago=now_utc - timedelta(hours=i),
            )
            db.add(pago)

        db.commit()
        print("  [OK] 5 ordenes de hoy creadas exitosamente ($5.000.000 facturados).")
    else:
        print(f"  [INFO] Ya existen {pagos_hoy_count} pagos registrados para hoy.")

    # 5. Verificar y poblar acumulado MTD (resto de septiembre)
    pagos_mes_count = (
        db.query(Transaccion_Pago)
        .filter(
            Transaccion_Pago.estado_pago == "Procesado",
            Transaccion_Pago.fecha_pago.between(inicio_mes_utc, fin_hoy_utc),
        )
        .count()
    )

    if pagos_mes_count < 40:
        print("  Completando acumulado MTD del mes en curso (43 ordenes adicionales para sumar $42.500.000)...")
        montos_base = [750000, 850000, 950000, 650000, 1100000, 1200000, 550000, 1500000]
        metodos_pool = ["Transferencia", "Tarjeta Crédito", "Efectivo", "Tarjeta Débito", "Webpay"]

        suma_acum = 0
        ordenes_specs = []
        for j in range(42):
            m = montos_base[j % len(montos_base)]
            suma_acum += m
            ordenes_specs.append(m)
        ultimo_monto = max(750000, 42500000 - suma_acum)
        ordenes_specs.append(ultimo_monto)

        for k, monto in enumerate(ordenes_specs):
            dia_offset = (k % 7) + 1
            hora_offset = (k % 10) + 9
            fecha_orden_chile = ahora_chile.replace(day=min(dia_offset, ahora_chile.day), hour=hora_offset, minute=15)
            fecha_utc = fecha_orden_chile.astimezone(timezone.utc).replace(tzinfo=None)

            suc_target = id_suc_1 if k % 2 == 0 else id_suc_2
            cliente = clientes[k % len(clientes)]
            metodo = metodos_pool[k % len(metodos_pool)]

            id_orden = uuid.uuid4()
            folio_str = f"ORD-MTD-{str(id_orden)[:4].upper()}"
            orden_mtd = Orden_Venta(
                id_orden=id_orden,
                id_cliente=cliente.id_cliente,
                id_vendedor=vendedor_user.id_usuario,
                id_cajera=cajera_user.id_usuario,
                id_sucursal=suc_target,
                estado_orden="Pagada",
                total_venta=monto,
                monto_pendiente=0,
                qr_transaccional_salida=folio_str,
                fecha_creacion=fecha_utc,
                fecha_actualizacion=fecha_utc,
            )
            db.add(orden_mtd)
            db.flush()

            pago_mtd = Transaccion_Pago(
                id_pago=uuid.uuid4(),
                id_orden=orden_mtd.id_orden,
                monto=monto,
                metodo_pago=metodo,
                estado_pago="Procesado",
                fecha_pago=fecha_utc,
            )
            db.add(pago_mtd)

        db.commit()
        print("  [OK] 43 ordenes MTD creadas exitosamente ($42.500.000 acumulado MTD).")
    else:
        print(f"  [INFO] Ya existen {pagos_mes_count} pagos registrados este mes.")

    # 6. Alerta Operativa: Asegurar orden con saldo pendiente ($320.000)
    orden_pendiente_existente = db.query(Orden_Venta).filter(Orden_Venta.monto_pendiente == 320000).first()
    if not orden_pendiente_existente:
        id_ord_pend = uuid.uuid4()
        orden_pend = Orden_Venta(
            id_orden=id_ord_pend,
            id_cliente=clientes[0].id_cliente,
            id_vendedor=vendedor_user.id_usuario,
            id_sucursal=id_suc_1,
            estado_orden="Reservada",
            total_venta=1120000,
            monto_pendiente=320000,
            qr_transaccional_salida="ORD-9778",
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            fecha_actualizacion=datetime.now(timezone.utc).replace(tzinfo=None),
        )
        db.add(orden_pend)
        db.commit()
        print("  [OK] Orden ORD-9778 con saldo pendiente ($320.000) creada.")

    # 7. Flujo de despacho: Asegurar despachos en estado 'Enviado'
    couriers_existentes = db.query(Despacho).filter(Despacho.estado_despacho == "Enviado").count()
    if couriers_existentes < 2:
        faltantes = 2 - couriers_existentes
        ordenes_disponibles = (
            db.query(Orden_Venta)
            .outerjoin(Despacho, Orden_Venta.id_orden == Despacho.id_orden)
            .filter(Despacho.id_despacho.is_(None))
            .limit(faltantes)
            .all()
        )
        for c_i, ord_item in enumerate(ordenes_disponibles):
            despacho = Despacho(
                id_despacho=uuid.uuid4(),
                id_orden=ord_item.id_orden,
                id_comuna_destino=1,
                direccion_envio=f"Av. Libertad #{1000 + c_i}, Viña del Mar",
                receptor_nombres="Cliente Courier",
                receptor_rut="11.222.333-4",
                receptor_telefono="+56987654321",
                empresa_transporte="Chilexpress" if c_i == 0 else "Starken",
                estado_despacho="Enviado",
                estado="Activo",
                fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            )
            db.add(despacho)
        db.commit()
        print("  [OK] Despachos en courier 'Enviado' creados.")


if __name__ == "__main__":
    print("Iniciando script seed.py...")
    seed_data()