import uuid
from datetime import datetime, timezone, timedelta, time
from zoneinfo import ZoneInfo
import pytest
from models import (
    Region,
    Comuna,
    Sucursal,
    Rol,
    Usuario,
    Cliente,
    Categoria_Activo,
    Estado_Activo,
    Vehiculo_Origen,
    Activo_Inventariado,
    Orden_Venta,
    Detalle_Orden,
    Transaccion_Pago,
    Auditoria_Barrera,
)
from core.security import create_access_token, hash_password
from conftest import TestingSessionLocal

tz_chile = ZoneInfo("America/Santiago")


@pytest.fixture(scope="module")
def db_session(setup_database):
    """
    Inicializa datos de prueba de sucursales, clientes, activos, órdenes con pagos y auditoría
    para validar el historial y cuadre de caja (SPEC-HU-4.5).
    """
    db = TestingSessionLocal()
    try:
        # Seed Geografía y Sucursales
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        c2 = Comuna(id_comuna=2, nombre_comuna="Limache", id_region=1)
        db.add_all([c, c2])

        suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 123", id_comuna=1)
        suc2 = Sucursal(id_sucursal=2, nombre_sucursal="Sucursal Limache", direccion="Calle Comercial 456", id_comuna=2)
        db.add_all([suc1, suc2])

        # Seed Roles
        rol_bodeguero = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        db.add_all([rol_bodeguero, rol_vendedor, rol_caja, rol_admin])

        # Usuarios
        user_caja = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=3,
            id_sucursal=1,
            rut_usuario="12.345.678-9",
            nombres="Lorena",
            apellidos="Valenzuela",
            email="lorena.caja@cresal.cl",
            password_hash=hash_password("caja1234"),
            pin_acceso="3333",
            estado="Activo",
        )
        user_admin = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=5,
            id_sucursal=1,
            rut_usuario="11.222.333-4",
            nombres="Carlos",
            apellidos="Administrador",
            email="admin@cresal.cl",
            password_hash=hash_password("admin1234"),
            pin_acceso="5555",
            estado="Activo",
        )
        user_bodeguero = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=1,
            rut_usuario="15.666.777-8",
            nombres="Pedro",
            apellidos="Bodeguero",
            email="pedro.bodega@cresal.cl",
            password_hash=hash_password("bodega1234"),
            pin_acceso="1111",
            estado="Activo",
        )
        user_vendedor_vina = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=1,
            rut_usuario="17.888.999-0",
            nombres="Andrés",
            apellidos="Morales",
            email="andres.ventas@cresal.cl",
            password_hash=hash_password("ventas1234"),
            pin_acceso="2222",
            estado="Activo",
        )
        user_vendedor_vina2 = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=1,
            rut_usuario="16.555.444-3",
            nombres="Juaquin",
            apellidos="Leiva",
            email="juaquin.ventas@cresal.cl",
            password_hash=hash_password("ventas555"),
            pin_acceso="6666",
            estado="Activo",
        )
        user_vendedor_limache = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=2,
            rut_usuario="19.111.222-3",
            nombres="Roberto",
            apellidos="Vendedor Limache",
            email="roberto.limache@cresal.cl",
            password_hash=hash_password("ventaslimache"),
            pin_acceso="4444",
            estado="Activo",
        )
        db.add_all([user_caja, user_admin, user_bodeguero, user_vendedor_vina, user_vendedor_vina2, user_vendedor_limache])

        # Clientes
        cliente1 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="77.301.992-1",
            nombres="Taller Mecánico",
            apellidos="San Cristóbal SpA",
            correo="taller.sancristobal@gmail.com",
            telefono="+56911223344",
            id_comuna=1,
            consentimiento_legal=True,
            estado="Activo",
        )
        cliente2 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="15.420.301-8",
            nombres="Pedro",
            apellidos="Aguirres Molina",
            correo="pedro.aguirres@gmail.com",
            telefono="+56955667788",
            id_comuna=1,
            consentimiento_legal=True,
            estado="Activo",
        )
        cliente3_limache = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="16.789.123-4",
            nombres="Patricio",
            apellidos="Gómez",
            correo="patricio.gomez@gmail.com",
            telefono="+56999887766",
            id_comuna=2,
            consentimiento_legal=True,
            estado="Activo",
        )
        db.add_all([cliente1, cliente2, cliente3_limache])

        # Categorías y Estados de Activo
        cat_caja = Categoria_Activo(id_categoria=1, nombre_categoria="Caja de Cambios")
        cat_motor = Categoria_Activo(id_categoria=2, nombre_categoria="Motor")
        db.add_all([cat_caja, cat_motor])

        est_disponible = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_vendido = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        db.add_all([est_disponible, est_vendido])

        # Vehículos y Activos
        vehiculo1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-001",
            marca="Toyota",
            modelo="Hilux 2.8",
            anio=2020,
            traccion="4x4",
            estado="Activo",
        )
        vehiculo2 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-002",
            marca="Suzuki",
            modelo="Swift 1.2",
            anio=2021,
            traccion="4x2",
            estado="Activo",
        )
        db.add_all([vehiculo1, vehiculo2])

        activo1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="CAJ-TOY-HIL-28-091",
            id_categoria=1,
            id_estado=3,
            id_sucursal_actual=1,
            id_vehiculo=vehiculo1.id_vehiculo,
            precio_referencia=500000,
        )
        activo2 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-SUZ-SW-12-044",
            id_categoria=2,
            id_estado=3,
            id_sucursal_actual=1,
            id_vehiculo=vehiculo2.id_vehiculo,
            precio_referencia=650000,
        )
        db.add_all([activo1, activo2])

        # Marcas temporales: hoy al mediodía en hora local de Chile para evitar desfases de medianoche
        ahora_chile = datetime.combine(datetime.now(tz_chile).date(), time(12, 0), tzinfo=tz_chile)
        hoy_utc = ahora_chile.astimezone(timezone.utc).replace(tzinfo=None)

        # ── Órdenes de Venta Sucursal 1 (Viña) ──────────────────────────────────
        # Orden 1: ORD-9778 (Pagada split: Débito $420.000 + Transferencia $180.000 = $600.000)
        orden1 = Orden_Venta(
            id_orden=uuid.UUID("8f3b201a-63b7-4dc4-8392-8094a942b001"),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_cajera=user_caja.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida="ORD-9778",
            total_venta=600000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc - timedelta(minutes=10),
        )
        db.add(orden1)

        det1_1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=activo1.id_activo,
            descripcion_manual="Caja de Cambios Automática Toyota Hilux 2.8",
            cantidad=1,
            precio_unitario=500000,
            precio_final=500000,
        )
        det1_2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=None,
            descripcion_manual="Filtro y Sensor de Caja de Cambios",
            cantidad=1,
            precio_unitario=100000,
            precio_final=100000,
        )
        db.add_all([det1_1, det1_2])

        pago1_1 = Transaccion_Pago(
            id_pago=uuid.UUID("1c7a911e-2879-43c3-9821-2e557b451001"),
            id_orden=orden1.id_orden,
            monto=420000,
            metodo_pago="Débito",
            estado_pago="Procesado",
            fecha_pago=hoy_utc - timedelta(minutes=10),
        )
        pago1_2 = Transaccion_Pago(
            id_pago=uuid.UUID("2d8b022f-3980-54d4-a932-3f668c562002"),
            id_orden=orden1.id_orden,
            monto=180000,
            metodo_pago="Transferencia",
            estado_pago="Procesado",
            fecha_pago=hoy_utc - timedelta(minutes=10),
        )
        db.add_all([pago1_1, pago1_2])

        auditoria1 = Auditoria_Barrera(
            id_auditoria=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_bodeguero=user_bodeguero.id_usuario,
            match_exitoso=True,
            fecha_escaneo=hoy_utc - timedelta(minutes=5),
        )
        db.add(auditoria1)

        # Orden 2: ORD-9773 (Despachada único: Efectivo $650.000)
        orden2 = Orden_Venta(
            id_orden=uuid.UUID("9a4c312b-74c8-5ed5-94a3-9105b053c002"),
            id_cliente=cliente2.id_cliente,
            id_vendedor=user_vendedor_vina2.id_usuario,
            id_cajera=user_caja.id_usuario,
            id_sucursal=1,
            estado_orden="Despachada",
            qr_transaccional_salida="ORD-9773",
            total_venta=650000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc - timedelta(minutes=20),
        )
        db.add(orden2)

        det2_1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden2.id_orden,
            id_activo=activo2.id_activo,
            descripcion_manual="Motor Suzuki Swift 1.2 K12M Semiequipado",
            cantidad=1,
            precio_unitario=650000,
            precio_final=650000,
        )
        db.add(det2_1)

        pago2_1 = Transaccion_Pago(
            id_pago=uuid.UUID("3e9c133a-4091-65e5-ba43-4a779d673003"),
            id_orden=orden2.id_orden,
            monto=650000,
            metodo_pago="Efectivo",
            estado_pago="Procesado",
            fecha_pago=hoy_utc - timedelta(minutes=20),
        )
        db.add(pago2_1)

        # Orden 3: ORD-9770 (Anulada $300.000) -> Debe listarse pero NO sumarse al arqueo
        orden3_anulada = Orden_Venta(
            id_orden=uuid.UUID("a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_cajera=user_caja.id_usuario,
            id_sucursal=1,
            estado_orden="Anulada",
            qr_transaccional_salida="ORD-9770",
            total_venta=300000,
            monto_pendiente=300000,
            fecha_creacion=hoy_utc - timedelta(minutes=30),
        )
        db.add(orden3_anulada)

        # Orden 4: ORD-9760 (Pagada fuera de HOY: 15 días atrás)
        orden4_antigua = Orden_Venta(
            id_orden=uuid.UUID("b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e"),
            id_cliente=cliente2.id_cliente,
            id_vendedor=user_vendedor_vina2.id_usuario,
            id_cajera=user_caja.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida="ORD-9760",
            total_venta=500000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc - timedelta(days=15),
        )
        db.add(orden4_antigua)

        pago4_1 = Transaccion_Pago(
            id_pago=uuid.UUID("4f0d244b-5102-76f6-cb54-5b880e784004"),
            id_orden=orden4_antigua.id_orden,
            monto=500000,
            metodo_pago="Crédito",
            estado_pago="Procesado",
            fecha_pago=hoy_utc - timedelta(days=15),
        )
        db.add(pago4_1)

        # Orden 5: Sucursal 2 (Limache) -> NO debe aparecer en consultas de Sucursal 1
        orden5_limache = Orden_Venta(
            id_orden=uuid.UUID("c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f"),
            id_cliente=cliente3_limache.id_cliente,
            id_vendedor=user_vendedor_limache.id_usuario,
            id_sucursal=2,
            estado_orden="Pagada",
            qr_transaccional_salida="ORD-8888",
            total_venta=200000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc,
        )
        db.add(orden5_limache)

        db.commit()

        yield {
            "user_caja_id": user_caja.id_usuario,
            "user_admin_id": user_admin.id_usuario,
            "user_bodeguero_id": user_bodeguero.id_usuario,
            "user_vendedor_id": user_vendedor_vina.id_usuario,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def tokens(db_session):
    return {
        "caja": create_access_token({"sub": str(db_session["user_caja_id"])}),
        "admin": create_access_token({"sub": str(db_session["user_admin_id"])}),
        "bodeguero": create_access_token({"sub": str(db_session["user_bodeguero_id"])}),
        "vendedor": create_access_token({"sub": str(db_session["user_vendedor_id"])}),
    }


def test_filtrar_historial_periodo_hoy_sucursal_1(client, tokens):
    """
    Test 1: Valida que GET /api/v1/caja/historial?sucursal_id=1&periodo=HOY
    retorne las 3 órdenes emitidas hoy en Viña y excluya la sucursal 2 (Limache) y órdenes antiguas.
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}
    response = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY", headers=headers)

    assert response.status_code == 200
    data = response.json()

    assert data["total_registros"] == 3
    assert data["pagina_actual"] == 1
    assert data["total_paginas"] == 1

    folios = [item["folio"] for item in data["items"]]
    assert "ORD-9778" in folios
    assert "ORD-9773" in folios
    assert "ORD-9770" in folios
    assert "ORD-8888" not in folios
    assert "ORD-9760" not in folios


def test_consistencia_matematica_resumen_cuadre_y_exclusion_anuladas(client, tokens):
    """
    Test 2: Valida la consistencia matemática del resumen_cuadre:
    - Total Efectivo: $650.000 (ORD-9773)
    - Total POS (Débito + Crédito): $420.000 (ORD-9778)
    - Total Transferencia: $180.000 (ORD-9778)
    - Total Recaudado: $1.250.000
    - Total Órdenes Pagadas: 2 (excluye ORD-9770 Anulada)
    - Exclusión estricta de orden Anulada del arqueo.
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}
    response = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY", headers=headers)

    assert response.status_code == 200
    cuadre = response.json()["resumen_cuadre"]

    assert cuadre["total_ordenes_pagadas"] == 2
    assert cuadre["total_efectivo"] == 650000
    assert cuadre["total_debito"] == 420000
    assert cuadre["total_credito"] == 0
    assert cuadre["total_pos"] == 420000
    assert cuadre["total_transferencia"] == 180000
    assert cuadre["total_cheque"] == 0
    assert cuadre["total_recaudado"] == 1250000
    assert cuadre["total_pos"] == cuadre["total_debito"] + cuadre["total_credito"]
    assert cuadre["total_recaudado"] == (
        cuadre["total_efectivo"] + cuadre["total_pos"] + cuadre["total_transferencia"] + cuadre["total_cheque"]
    )


def test_busqueda_multicriterio_rut_folio_cliente_vendedor(client, tokens):
    """
    Test 3: Valida búsqueda reactiva multicriterio:
    - Búsqueda por Folio ('ORD-9778')
    - Búsqueda por RUT sin puntos/guión ('773019921')
    - Búsqueda por apellido de cliente ('Aguirres')
    - Búsqueda por vendedor ('Andres')
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    # Búsqueda por Folio
    r_folio = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&busqueda=ORD-9778", headers=headers)
    assert r_folio.status_code == 200
    assert r_folio.json()["total_registros"] == 1
    assert r_folio.json()["items"][0]["folio"] == "ORD-9778"
    assert r_folio.json()["items"][0]["modalidad_pago"] == "split"

    # Búsqueda por RUT sin formato
    r_rut = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&busqueda=773019921", headers=headers)
    assert r_rut.status_code == 200
    assert r_rut.json()["total_registros"] == 2
    assert all(it["cliente_rut"] == "77.301.992-1" for it in r_rut.json()["items"])

    # Búsqueda por Cliente
    r_cli = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&busqueda=Aguirres", headers=headers)
    assert r_cli.status_code == 200
    assert r_cli.json()["total_registros"] == 1
    assert r_cli.json()["items"][0]["folio"] == "ORD-9773"

    # Búsqueda por Vendedor
    r_vend = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&busqueda=Andres", headers=headers)
    assert r_vend.status_code == 200
    assert r_vend.json()["total_registros"] >= 1


def test_filtro_por_metodo_de_pago(client, tokens):
    """
    Test 4: Valida filtrado por método de pago específico:
    - 'Efectivo': Retorna solo ORD-9773
    - 'Transferencia': Retorna solo ORD-9778
    - 'Cheque': Retorna 0 registros
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    r_efectivo = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&metodo_pago=Efectivo", headers=headers)
    assert r_efectivo.status_code == 200
    assert r_efectivo.json()["total_registros"] == 1
    assert r_efectivo.json()["items"][0]["folio"] == "ORD-9773"

    r_transf = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&metodo_pago=Transferencia", headers=headers)
    assert r_transf.status_code == 200
    assert r_transf.json()["total_registros"] == 1
    assert r_transf.json()["items"][0]["folio"] == "ORD-9778"

    r_cheque = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&metodo_pago=Cheque", headers=headers)
    assert r_cheque.status_code == 200
    assert r_cheque.json()["total_registros"] == 0


def test_paginacion_y_total_paginas(client, tokens):
    """
    Test 5: Valida paginación consistente con límite y cálculo exacto de total_paginas.
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    r_pag1 = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&limite=1&pagina=1", headers=headers)
    assert r_pag1.status_code == 200
    d_pag1 = r_pag1.json()
    assert d_pag1["total_registros"] == 3
    assert d_pag1["total_paginas"] == 3
    assert d_pag1["pagina_actual"] == 1
    assert len(d_pag1["items"]) == 1

    r_pag2 = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&limite=1&pagina=2", headers=headers)
    assert r_pag2.status_code == 200
    d_pag2 = r_pag2.json()
    assert d_pag2["pagina_actual"] == 2
    assert len(d_pag2["items"]) == 1
    assert d_pag2["items"][0]["folio"] != d_pag1["items"][0]["folio"]


def test_control_de_acceso_rbac_y_seguridad(client, tokens):
    """
    Test 6: Valida Zero Trust RBAC:
    - 401 Unauthorized sin token
    - 403 Forbidden para Bodeguero (id_rol=1) y Vendedor (id_rol=2)
    - 200 OK para Administrador (id_rol=5) y Cajera (id_rol=3)
    """
    # Sin token
    r_no_auth = client.get("/api/v1/caja/historial?sucursal_id=1")
    assert r_no_auth.status_code == 401

    # Bodeguero
    h_bod = {"Authorization": f"Bearer {tokens['bodeguero']}"}
    r_bod = client.get("/api/v1/caja/historial?sucursal_id=1", headers=h_bod)
    assert r_bod.status_code == 403

    # Vendedor
    h_vend = {"Authorization": f"Bearer {tokens['vendedor']}"}
    r_vend = client.get("/api/v1/caja/historial?sucursal_id=1", headers=h_vend)
    assert r_vend.status_code == 403

    # Administrador
    h_admin = {"Authorization": f"Bearer {tokens['admin']}"}
    r_admin = client.get("/api/v1/caja/historial?sucursal_id=1", headers=h_admin)
    assert r_admin.status_code == 200


def test_filtro_rango_fechas_y_validacion_error(client, tokens):
    """
    Test 7: Valida filtro RANGO y respuesta 422 si fecha_desde > fecha_hasta o si faltan fechas.
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    # Rango invertido -> 422
    r_invalid = client.get(
        "/api/v1/caja/historial?sucursal_id=1&periodo=RANGO&fecha_desde=2026-08-30&fecha_hasta=2026-08-01",
        headers=headers,
    )
    assert r_invalid.status_code == 422

    # Rango sin fechas -> 422
    r_missing = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=RANGO", headers=headers)
    assert r_missing.status_code == 422


def test_historial_excluye_ordenes_reservadas(client, tokens):
    """
    Test 8: Valida que órdenes en estado 'Reservada' (pendientes de cobro)
    NUNCA aparezcan en el historial de auditoría de caja.
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    # Consultar historial general
    response = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=TODOS", headers=headers)
    assert response.status_code == 200
    items = response.json()["items"]

    # Ningún ítem en el historial debe tener estado Reservada
    for item in items:
        assert item["estado_orden"] != "Reservada"


def test_filtro_metodo_pago_con_tildes_debito_y_credito(client, tokens):
    """
    Test 9: Valida que el filtro de método de pago normalice tildes (Débito == Debito).
    """
    headers = {"Authorization": f"Bearer {tokens['caja']}"}

    # 'Débito' con tilde debe encontrar ORD-9778 (que tiene pago Débito)
    r_deb = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&metodo_pago=Débito", headers=headers)
    assert r_deb.status_code == 200
    assert r_deb.json()["total_registros"] == 1
    assert r_deb.json()["items"][0]["folio"] == "ORD-9778"

    # 'Debito' sin tilde también debe encontrarla
    r_deb2 = client.get("/api/v1/caja/historial?sucursal_id=1&periodo=HOY&metodo_pago=Debito", headers=headers)
    assert r_deb2.status_code == 200
    assert r_deb2.json()["total_registros"] == 1

