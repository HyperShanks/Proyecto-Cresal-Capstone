import uuid
from datetime import datetime, timezone
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
    Reservas_Backorder,
)
from core.security import create_access_token, hash_password
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    """
    Inicializa datos de prueba de sucursales, clientes, activos, órdenes y reservas para
    validar la bandeja unificada de cobros pendientes y búsqueda reactiva de caja (SPEC-HU-4.2).
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
            nombres="María Jesús",
            apellidos="López Vega",
            email="maria.caja@cresal.cl",
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
            nombres="Juaquin",
            apellidos="Leiva",
            email="juaquin.ventas@cresal.cl",
            password_hash=hash_password("ventas1234"),
            pin_acceso="2222",
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
        db.add_all([user_caja, user_admin, user_bodeguero, user_vendedor_vina, user_vendedor_limache])

        # Clientes
        cliente1 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="14.892.401-2",
            nombres="Cristobal Alejandro",
            apellidos="Espinoza Perez",
            correo="cristobal.espinoza@gmail.com",
            telefono="+56911223344",
            id_comuna=1,
            consentimiento_legal=True,
            estado="Activo",
        )
        cliente2 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="18.432.109-K",
            nombres="Camila Andrea",
            apellidos="Soto Lagos",
            correo="camila.soto@gmail.com",
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
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambios")
        db.add_all([cat_motor, cat_caja])

        est_disponible = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_reservado = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        db.add_all([est_disponible, est_reservado])

        # Vehículo y Activo
        vehiculo1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-001",
            marca="MG",
            modelo="ZS 1.5 VTi-Tech",
            anio=2021,
            traccion="4x2",
            estado="Activo",
        )
        db.add(vehiculo1)

        activo1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-MG-ZS-15-089",
            id_categoria=1,
            id_estado=2,
            id_sucursal_actual=1,
            id_vehiculo=vehiculo1.id_vehiculo,
            precio_referencia=550000,
        )
        db.add(activo1)

        # ── Órdenes de Venta ─────────────────────────────────────────────────
        # Orden 1: Viña (Pendiente de pago, saldo 500.000) -> DEBE APARECER
        orden1 = Orden_Venta(
            id_orden=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa6"),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida="ORD-9780",
            total_venta=650000,
            monto_pendiente=500000,
            fecha_creacion=datetime(2026, 8, 21, 11, 38, 0, tzinfo=timezone.utc),
        )
        db.add(orden1)

        det1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=activo1.id_activo,
            descripcion_manual="Motor MG ZS 1.5 VTi-Tech Completo",
            cantidad=1,
            precio_unitario=550000,
            precio_final=550000,
        )
        det2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=None,
            descripcion_manual="Soporte Motor en Desarme",
            cantidad=1,
            precio_unitario=100000,
            precio_final=100000,
        )
        db.add_all([det1, det2])

        # Orden 2: Viña Pagada (monto_pendiente = 0) -> NO DEBE APARECER
        orden2_pagada = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida="ORD-PAID-01",
            total_venta=200000,
            monto_pendiente=0,
        )
        db.add(orden2_pagada)

        # Orden 3: Limache (id_sucursal = 2) -> NO DEBE APARECER EN VIÑA
        orden3_limache = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente3_limache.id_cliente,
            id_vendedor=user_vendedor_limache.id_usuario,
            id_sucursal=2,
            estado_orden="Reservada",
            qr_transaccional_salida="ORD-LIM-01",
            total_venta=300000,
            monto_pendiente=300000,
        )
        db.add(orden3_limache)

        # ── Reservas Backorder ───────────────────────────────────────────────
        # Reserva 1: Viña (Pendiente de cobro 300.000) -> DEBE APARECER
        reserva1 = Reservas_Backorder(
            id_reserva=uuid.UUID("7c9e6679-7425-40de-944b-e07fc1f90ae7"),
            id_cliente=cliente2.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Hyundai",
            modelo_requerido="Tucson 2.0 CRDi Turbo Diesel",
            anio_requerido=2022,
            cilindrada_requerida="2.0L Turbo Diesel (D4HA)",
            combustible_requerido="Diésel",
            notas_preparacion="En Tránsito Marítimo (Arribo est.: 10 días)",
            precio_acordado=1200000,
            monto_abonado=900000,
            estado_reserva="Pendiente",
            fecha_creacion=datetime(2026, 8, 21, 12, 20, 0, tzinfo=timezone.utc),
        )
        db.add(reserva1)

        # Reserva 2: Viña Pagada/Completada -> NO DEBE APARECER
        reserva2_completada = Reservas_Backorder(
            id_reserva=uuid.uuid4(),
            id_cliente=cliente2.id_cliente,
            id_vendedor=user_vendedor_vina.id_usuario,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Toyota",
            modelo_requerido="Hilux",
            precio_acordado=500000,
            monto_abonado=500000,
            estado_reserva="Completada",
        )
        db.add(reserva2_completada)

        # Reserva 3: Limache -> NO DEBE APARECER EN VIÑA
        reserva3_limache = Reservas_Backorder(
            id_reserva=uuid.uuid4(),
            id_cliente=cliente3_limache.id_cliente,
            id_vendedor=user_vendedor_limache.id_usuario,
            id_sucursal_registro=2,
            id_categoria_requerida=2,
            marca_requerida="Nissan",
            modelo_requerido="Qashqai",
            precio_acordado=400000,
            monto_abonado=0,
            estado_reserva="Pendiente",
        )
        db.add(reserva3_limache)

        db.commit()

        yield {
            "caja_vina": user_caja,
            "admin": user_admin,
            "bodeguero": user_bodeguero,
            "vendedor_vina": user_vendedor_vina,
            "vendedor_limache": user_vendedor_limache,
        }
    finally:
        db.close()


def test_listar_pendientes_sucursal_1_consolida_ventas_y_backorders(client, db_session):
    """
    Verifica que GET /api/v1/caja/pendientes?sucursal_id=1 retorne tanto órdenes de venta
    como reservas backorder pendientes de cobro para la sucursal 1.
    """
    token = create_access_token(
        data={"sub": str(db_session["caja_vina"].id_usuario), "id_rol": 3, "id_sucursal": 1}
    )
    response = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1",
        headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2
    assert data["sucursal_id"] == 1

    folios = [item["folio_documento"] for item in data["items"]]
    assert "ORD-9780" in folios
    assert any(f.startswith("RES-") for f in folios)

    # Verificar datos de la orden de venta
    item_venta = next(it for it in data["items"] if it["tipo_operacion"] == "VENTA")
    assert item_venta["cliente_nombre"] == "Cristobal Alejandro Espinoza Perez"
    assert item_venta["cliente_rut"] == "14.892.401-2"
    assert item_venta["vendedor_nombre"] == "Juaquin Leiva"
    assert item_venta["total_operacion"] == 650000
    assert item_venta["abono_previo"] == 150000
    assert item_venta["monto_a_cobrar"] == 500000
    assert len(item_venta["articulos"]) == 2
    assert item_venta["articulos"][0]["tipo"] == "INVENTARIADO"
    assert item_venta["articulos"][0]["sku"] == "MOT-MG-ZS-15-089"

    # Verificar datos de la reserva backorder
    item_bo = next(it for it in data["items"] if it["tipo_operacion"] == "BACKORDER")
    assert item_bo["cliente_nombre"] == "Camila Andrea Soto Lagos"
    assert item_bo["cliente_rut"] == "18.432.109-K"
    assert item_bo["total_operacion"] == 1200000
    assert item_bo["abono_previo"] == 900000
    assert item_bo["monto_a_cobrar"] == 300000
    assert item_bo["especificaciones_backorder"] is not None
    assert item_bo["especificaciones_backorder"]["marca"] == "Hyundai"
    assert item_bo["especificaciones_backorder"]["modelo"] == "Tucson 2.0 CRDi Turbo Diesel"


def test_aislamiento_multi_tenant_por_sucursal(client, db_session):
    """
    Verifica que la consulta para sucursal 1 no incluya registros de sucursal 2,
    y que la consulta para sucursal 2 retorne únicamente los de sucursal 2.
    """
    token = create_access_token(
        data={"sub": str(db_session["caja_vina"].id_usuario), "id_rol": 3, "id_sucursal": 1}
    )

    # Consulta sucursal 1
    resp1 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert resp1.status_code == 200
    folios_suc1 = [it["folio_documento"] for it in resp1.json()["items"]]
    assert "ORD-LIM-01" not in folios_suc1

    # Consulta sucursal 2
    resp2 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=2",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert resp2.status_code == 200
    data2 = resp2.json()
    assert data2["total"] == 2
    folios_suc2 = [it["folio_documento"] for it in data2["items"]]
    assert "ORD-LIM-01" in folios_suc2
    assert "ORD-9780" not in folios_suc2


def test_filtro_por_tipo_operacion(client, db_session):
    """
    Verifica que el parámetro tipo_operacion ('VENTA', 'BACKORDER', 'TODOS')
    filtre adecuadamente la lista.
    """
    token = create_access_token(
        data={"sub": str(db_session["caja_vina"].id_usuario), "id_rol": 3, "id_sucursal": 1}
    )

    # Solo VENTAS
    resp_venta = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&tipo_operacion=VENTA",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert resp_venta.status_code == 200
    items_v = resp_venta.json()["items"]
    assert len(items_v) == 1
    assert items_v[0]["tipo_operacion"] == "VENTA"
    assert items_v[0]["folio_documento"] == "ORD-9780"

    # Solo BACKORDER
    resp_bo = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&tipo_operacion=BACKORDER",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert resp_bo.status_code == 200
    items_b = resp_bo.json()["items"]
    assert len(items_b) == 1
    assert items_b[0]["tipo_operacion"] == "BACKORDER"


def test_busqueda_multicriterio_rut_folio_nombre_vendedor(client, db_session):
    """
    Verifica que el parámetro 'busqueda' busque insensible a mayúsculas/minúsculas y puntuación de RUT.
    """
    token = create_access_token(
        data={"sub": str(db_session["caja_vina"].id_usuario), "id_rol": 3, "id_sucursal": 1}
    )

    # 1. Búsqueda por RUT con puntos
    r1 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=14.892.401-2",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r1.status_code == 200
    assert r1.json()["total"] == 1
    assert r1.json()["items"][0]["cliente_rut"] == "14.892.401-2"

    # 2. Búsqueda por RUT sin puntos ni guion
    r2 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=148924012",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r2.status_code == 200
    assert r2.json()["total"] == 1

    # 3. Búsqueda por Folio
    r3 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=9780",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r3.status_code == 200
    assert r3.json()["total"] == 1
    assert r3.json()["items"][0]["folio_documento"] == "ORD-9780"

    # 4. Búsqueda por Nombre de Cliente
    r4 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=Soto",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r4.status_code == 200
    assert r4.json()["total"] == 1
    assert r4.json()["items"][0]["cliente_nombre"] == "Camila Andrea Soto Lagos"

    # 5. Búsqueda por Vendedor
    r5 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=Juaquin",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r5.status_code == 200
    assert r5.json()["total"] == 2

    # 6. Búsqueda sin coincidencias
    r6 = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1&busqueda=NONEXISTENT_XYZ",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert r6.status_code == 200
    assert r6.json()["total"] == 0
    assert r6.json()["items"] == []


def test_acceso_denegado_para_bodeguero_y_vendedor_403(client, db_session):
    """
    Verifica que usuarios con rol Bodeguero (1) o Vendedor (2) reciban 403 Forbidden.
    """
    token_bodega = create_access_token(
        data={"sub": str(db_session["bodeguero"].id_usuario), "id_rol": 1, "id_sucursal": 1}
    )
    resp_b = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1",
        headers={"Authorization": f"Bearer {token_bodega}"}
    )
    assert resp_b.status_code == 403
    assert "Acceso restringido" in resp_b.json()["detail"]

    token_vendedor = create_access_token(
        data={"sub": str(db_session["vendedor_vina"].id_usuario), "id_rol": 2, "id_sucursal": 1}
    )
    resp_v = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1",
        headers={"Authorization": f"Bearer {token_vendedor}"}
    )
    assert resp_v.status_code == 403


def test_acceso_permitido_para_admin(client, db_session):
    """
    Verifica que el Administrador (id_rol == 5) tenga acceso autorizado a la bandeja de pendientes.
    """
    token_admin = create_access_token(
        data={"sub": str(db_session["admin"].id_usuario), "id_rol": 5, "id_sucursal": 1}
    )
    resp_admin = client.get(
        "/api/v1/caja/pendientes?sucursal_id=1",
        headers={"Authorization": f"Bearer {token_admin}"}
    )
    assert resp_admin.status_code == 200
    assert resp_admin.json()["total"] == 2


def test_acceso_sin_token_retorna_401(client):
    """
    Verifica que una petición sin autenticación retorne 401 Unauthorized.
    """
    response = client.get("/api/v1/caja/pendientes?sucursal_id=1")
    assert response.status_code in [401, 403]


def test_no_duplicidad_orden_backorder_en_caja(client, db_session):
    """
    Verifica que cuando un cliente realiza una reserva backorder (que genera una Orden_Venta y
    una Reservas_Backorder vinculada), en Caja NO se duplique la orden en tipo=TODOS.
    Solo debe aparecer 1 registro con tipo_operacion == 'BACKORDER' (RES-XXXX), y no una orden normal (ORD-XXXX).
    """
    db = TestingSessionLocal()
    try:
        user_caja = db_session["caja_vina"]
        token_caja = create_access_token(
            data={"sub": str(user_caja.id_usuario), "id_rol": 3, "id_sucursal": 1}
        )
        headers = {"Authorization": f"Bearer {token_caja}"}

        # Crear una orden con backorder vinculado
        id_orden = uuid.uuid4()
        id_reserva = uuid.uuid4()
        cliente = db.query(Cliente).first()

        orden = Orden_Venta(
            id_orden=id_orden,
            id_cliente=cliente.id_cliente,
            id_vendedor=db_session["vendedor_vina"].id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=850000,
            monto_pendiente=850000,
            abono_requerido=250000,
        )
        db.add(orden)
        db.flush()

        reserva = Reservas_Backorder(
            id_reserva=id_reserva,
            id_cliente=cliente.id_cliente,
            id_vendedor=db_session["vendedor_vina"].id_usuario,
            id_orden=id_orden,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Subaru",
            modelo_requerido="WRX STI",
            anio_requerido=2021,
            precio_acordado=850000,
            monto_abonado=0,
            abono_requerido=250000,
            estado_reserva="Pendiente",
            fecha_creacion=datetime.now(timezone.utc),
        )
        db.add(reserva)
        db.commit()

        # Consultar la bandeja de cobros pendientes en Caja con filtro TODOS
        resp = client.get("/api/v1/caja/pendientes?sucursal_id=1&tipo=TODOS", headers=headers)
        assert resp.status_code == 200
        items = resp.json()["items"]

        # Filtrar los ítems que corresponden a este id_orden o id_reserva
        items_orden = [it for it in items if it["id_referencia"] == str(id_orden)]
        items_reserva = [it for it in items if it["id_referencia"] == str(id_reserva)]

        # 1. La Orden_Venta vinculada a la reserva NO debe aparecer como VENTA duplicada
        assert len(items_orden) == 0, "La Orden_Venta no debe duplicarse como VENTA en caja si tiene una reserva backorder asociada"

        # 2. La reserva SÍ debe aparecer como BACKORDER única
        assert len(items_reserva) == 1, "Debe aparecer exactamente una reserva backorder"
        assert items_reserva[0]["tipo_operacion"] == "BACKORDER"
        assert items_reserva[0]["total_operacion"] == 850000
        assert items_reserva[0]["monto_a_cobrar"] == 250000
        assert items_reserva[0]["abono_previo"] == 0
    finally:
        db.close()

