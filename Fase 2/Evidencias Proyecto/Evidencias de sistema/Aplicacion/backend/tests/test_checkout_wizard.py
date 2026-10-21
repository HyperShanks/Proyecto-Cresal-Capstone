# backend/tests/test_checkout_wizard.py
# Suite de pruebas automatizadas para SPEC-HU-05:
# Flujo de Checkout por Pasos (Wizard) e Integración de Reservas por Encargo (Reservas_Backorder).

import uuid
import pytest
from datetime import datetime, timezone

from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Orden_Venta, Detalle_Orden,
    Cliente, Reservas_Backorder, Despacho
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def wizard_db(setup_database):
    db = TestingSessionLocal()
    try:
        # Seed Base
        r = Region(id_region=30, nombre_region="Valparaíso - Wizard")
        db.add(r)
        c = Comuna(id_comuna=30, nombre_comuna="Viña del Mar - Wizard", id_region=30)
        db.add(c)

        suc1 = Sucursal(id_sucursal=30, nombre_sucursal="Sucursal Wizard", direccion="Av. Libertad 555", id_comuna=30)
        db.add(suc1)

        rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        rol_jefe = Rol(id_rol=6, nombre_rol="JefeVenta")
        rol_online = Rol(id_rol=7, nombre_rol="VendedorOnline")
        for rol in [rol_bodega, rol_vendedor, rol_caja, rol_admin, rol_jefe, rol_online]:
            db.merge(rol)

        u_vend_id = uuid.uuid4()
        u_bod_id = uuid.uuid4()
        u_caja_id = uuid.uuid4()

        # Usuarios
        user_vendedor = Usuario(
            id_usuario=u_vend_id,
            id_rol=2,
            id_sucursal=30,
            rut_usuario="18.111.222-3",
            nombres="Carlos",
            apellidos="Ventas Wizard",
            email="vendedor.wizard@cresal.cl",
            password_hash="hash",
            pin_acceso="2020",
            estado="Activo"
        )
        user_bodeguero = Usuario(
            id_usuario=u_bod_id,
            id_rol=1,
            id_sucursal=30,
            rut_usuario="18.333.444-5",
            nombres="Juan",
            apellidos="Bodega Wizard",
            email="bodega.wizard@cresal.cl",
            password_hash="hash",
            pin_acceso="1010",
            estado="Activo"
        )
        user_caja = Usuario(
            id_usuario=u_caja_id,
            id_rol=3,
            id_sucursal=30,
            rut_usuario="18.555.666-7",
            nombres="Lorena",
            apellidos="Caja Wizard",
            email="caja.wizard@cresal.cl",
            password_hash="hash",
            pin_acceso="3030",
            estado="Activo"
        )
        db.add_all([user_vendedor, user_bodeguero, user_caja])

        # Categorías y Estados
        cat_motor = Categoria_Activo(id_categoria=31, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=32, nombre_categoria="Caja de Cambios")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_ven = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
        for est in [est_disp, est_res, est_ven, est_pal]:
            db.merge(est)

        # Vehículo Origen
        veh = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-WIZ-01",
            patente="WIZ123",
            vin="VINWIZ12345678901",
            marca="Toyota",
            modelo="Corolla",
            anio=2020,
            traccion="4x2",
            estado="Activo"
        )
        db.add(veh)

        # Activo Físico Disponible
        act_disp_id = uuid.uuid4()
        act_disp = Activo_Inventariado(
            id_activo=act_disp_id,
            sku_qr_fisico="MOT-TOY-COR-001",
            id_categoria=31,
            id_estado=1,  # Disponible
            id_sucursal_actual=30,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-02",
            ubicacion_pallet="PAL-05",
            precio_referencia=650000,
            version_lock=1,
            estado="Activo"
        )

        # Activo Físico Ya Vendido (para test de rollback)
        act_ven_id = uuid.uuid4()
        act_ven = Activo_Inventariado(
            id_activo=act_ven_id,
            sku_qr_fisico="MOT-TOY-COR-VENDIDO",
            id_categoria=31,
            id_estado=3,  # Vendido
            id_sucursal_actual=30,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-02",
            ubicacion_pallet="PAL-06",
            precio_referencia=650000,
            version_lock=1,
            estado="Activo"
        )
        db.add_all([act_disp, act_ven])

        # Cliente CRM
        cli_id = uuid.uuid4()
        cli = Cliente(
            id_cliente=cli_id,
            rut_cliente="19.999.888-7",
            nombres="Andrea",
            apellidos="Montesinos",
            telefono="+56987654321",
            correo="andrea.montesinos@cresal.cl",
            id_comuna=30,
            consentimiento_legal=True,
            estado="Activo"
        )
        db.add(cli)

        db.commit()

        return {
            "vendedor_id": u_vend_id,
            "bodeguero_id": u_bod_id,
            "caja_id": u_caja_id,
            "cliente_id": cli_id,
            "activo_disp_id": act_disp_id,
            "activo_ven_id": act_ven_id,
            "comuna_id": 30,
            "categoria_motor_id": 31,
            "categoria_caja_id": 32,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_vendedor_wiz(wizard_db):
    token = create_access_token(data={"sub": str(wizard_db["vendedor_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_bodeguero_wiz(wizard_db):
    token = create_access_token(data={"sub": str(wizard_db["bodeguero_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_caja_wiz(wizard_db):
    token = create_access_token(data={"sub": str(wizard_db["caja_id"])})
    return {"Authorization": f"Bearer {token}"}


# ── TEST 1: Flujo Híbrido Completo (Inventario + Manual + Backorder + Despacho) ──
def test_checkout_wizard_flujo_completo_hibrido(client, wizard_db, auth_vendedor_wiz):
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Despacho Domicilio",
        "total_venta": 1150000,
        "monto_pendiente": 650000,  # 1.150.000 total - 500.000 abono
        "items_inventariados": [str(wizard_db["activo_disp_id"])],
        "items_manuales": [
            {
                "descripcion": "Kit de Empaquetaduras de Culata",
                "cantidad": 1,
                "precio_unitario": 50000,
                "precio_final": 50000,
                "notas_preparacion": "Sellado en empaque original"
            }
        ],
        "reservas": [
            {
                "id_categoria_requerida": wizard_db["categoria_caja_id"],
                "marca_requerida": "Toyota",
                "modelo_requerido": "Corolla",
                "anio_requerido": 2021,
                "cilindrada_requerida": "1.8L",
                "combustible_requerido": "Bencina",
                "transmision_requerida": "CVT",
                "notas_preparacion": "Revisar sincronizadores y sensor de reversa",
                "precio_acordado": 450000,
                "monto_abonado": 150000
            }
        ],
        "datos_despacho": {
            "direccion_envio": "Av. Uno Norte 1234, Depto 402",
            "receptor_nombres": "Andrea Montesinos",
            "receptor_rut": "19.999.888-7",
            "receptor_telefono": "+56987654321",
            "id_comuna_destino": wizard_db["comuna_id"],
            "empresa_transporte": "Chilexpress"
        }
    }

    response = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert response.status_code == 201, response.text

    data = response.json()
    assert "id_orden" in data
    assert data["estado"] == "Reservada"
    assert data["total_venta"] == 1150000
    assert data["monto_pendiente"] == 1150000
    assert data["abono_requerido"] == 150000
    assert data["activos_reservados"] == 1
    assert data["reservas_generadas"] == 1
    assert data["despacho_generado"] is True

    id_orden = uuid.UUID(data["id_orden"])

    # Verificación en Base de Datos
    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
        assert orden_db is not None
        assert orden_db.estado_orden == "Reservada"
        assert orden_db.monto_pendiente == 1150000
        assert orden_db.abono_requerido == 150000

        # Activo inventariado cambió a Reservado (id_estado = 2) y version_lock = 2
        act_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == wizard_db["activo_disp_id"]).first()
        assert act_db.id_estado == 2
        assert act_db.version_lock >= 2

        # Detalles de orden creados (3 líneas: inventariado + manual + reserva)
        detalles_db = db.query(Detalle_Orden).filter(Detalle_Orden.id_orden == id_orden).all()
        assert len(detalles_db) == 3

        # Registro en Reservas_Backorder
        reserva_db = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_orden == id_orden).first()
        assert reserva_db is not None
        assert reserva_db.marca_requerida == "Toyota"
        assert reserva_db.modelo_requerido == "Corolla"
        assert reserva_db.precio_acordado == 450000
        assert reserva_db.monto_abonado == 0
        assert reserva_db.abono_requerido == 150000
        assert reserva_db.estado_reserva == "Pendiente"

        # Registro en Despacho
        despacho_db = db.query(Despacho).filter(Despacho.id_orden == id_orden).first()
        assert despacho_db is not None
        assert despacho_db.direccion_envio == "Av. Uno Norte 1234, Depto 402"
        assert despacho_db.empresa_transporte == "Chilexpress"
    finally:
        db.close()


# ── TEST 2: Venta Exclusiva de Reserva por Encargo (Compra en Verde) ──────────
def test_checkout_wizard_solo_reserva_backorder_con_abono(client, wizard_db, auth_vendedor_wiz):
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Retiro",
        "total_venta": 500000,
        "monto_pendiente": 300000,  # 500.000 total - 200.000 abono
        "items_inventariados": [],
        "items_manuales": [],
        "reservas": [
            {
                "id_categoria_requerida": wizard_db["categoria_motor_id"],
                "marca_requerida": "Nissan",
                "modelo_requerido": "Qashqai",
                "anio_requerido": 2019,
                "cilindrada_requerida": "2.0L",
                "precio_acordado": 500000,
                "monto_abonado": 200000,
                "notas_preparacion": "Importación directa de desarme"
            }
        ]
    }

    response = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert response.status_code == 201

    data = response.json()
    assert data["reservas_generadas"] == 1
    assert data["activos_reservados"] == 0
    assert data["despacho_generado"] is False


# ── TEST 3: Rollback ante Activo no Disponible (Vendido) ──────────────────────
def test_checkout_wizard_falla_activo_no_disponible_rollback(client, wizard_db, auth_vendedor_wiz):
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Retiro",
        "total_venta": 650000,
        "monto_pendiente": 650000,
        "items_inventariados": [str(wizard_db["activo_ven_id"])],  # Ya está Vendido
    }

    response = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert response.status_code == 400
    assert "no está disponible para venta" in response.json()["detail"]


# ── TEST 4: Error ante Despacho Incompleto o Comuna Inexistente ───────────────
def test_checkout_wizard_falla_despacho_incompleto(client, wizard_db, auth_vendedor_wiz):
    # Caso A: Falta objeto datos_despacho
    payload_a = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Despacho Domicilio",
        "total_venta": 100000,
        "monto_pendiente": 100000,
        "items_manuales": [{"descripcion": "Filtro Aceite", "cantidad": 1, "precio_unitario": 100000}],
    }
    res_a = client.post("/api/v1/ordenes/checkout-wizard", json=payload_a, headers=auth_vendedor_wiz)
    assert res_a.status_code == 400
    assert "se requieren los datos de despacho" in res_a.json()["detail"]

    # Caso B: Comuna inexistente
    payload_b = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Despacho Domicilio",
        "total_venta": 100000,
        "monto_pendiente": 100000,
        "items_manuales": [{"descripcion": "Filtro Aceite", "cantidad": 1, "precio_unitario": 100000}],
        "datos_despacho": {
            "direccion_envio": "Calle Falsa 123",
            "receptor_nombres": "Pedro",
            "receptor_rut": "11.222.333-4",
            "receptor_telefono": "+56911112222",
            "id_comuna_destino": 999999  # Inexistente
        }
    }
    res_b = client.post("/api/v1/ordenes/checkout-wizard", json=payload_b, headers=auth_vendedor_wiz)
    assert res_b.status_code == 400
    assert "no existe" in res_b.json()["detail"]


# ── TEST 5: Error ante Cliente Inexistente ────────────────────────────────────
def test_checkout_wizard_falla_cliente_inexistente(client, wizard_db, auth_vendedor_wiz):
    payload = {
        "id_cliente": str(uuid.uuid4()),
        "tipo_entrega": "Retiro",
        "total_venta": 50000,
        "monto_pendiente": 50000,
        "items_manuales": [{"descripcion": "Bujía", "cantidad": 1, "precio_unitario": 50000}],
    }

    response = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert response.status_code == 404
    assert "cliente especificado no existe" in response.json()["detail"]


# ── TEST 6: RBAC: Bodeguero y Cajera bloqueados de emitir órdenes ─────────────
def test_checkout_wizard_bloqueo_rbac_bodeguero_y_cajera(client, wizard_db, auth_bodeguero_wiz, auth_caja_wiz):
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Retiro",
        "total_venta": 50000,
        "monto_pendiente": 50000,
        "items_manuales": [{"descripcion": "Bujía", "cantidad": 1, "precio_unitario": 50000}],
    }

    # Bodeguero -> 403
    res_bodega = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_bodeguero_wiz)
    assert res_bodega.status_code == 403

    # Caja -> 403
    res_caja = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_caja_wiz)
    assert res_caja.status_code == 403


# ── TEST 7: Traslado con ítems en formato dict y Tracking_Logistico ───────────
def test_checkout_wizard_traslado_con_dict_items(client, wizard_db, auth_vendedor_wiz):
    """Verifica que items_inventariados con dicts {'id_activo': ..., 'precio_final': ...} no fallen con psycopg2 dict error."""
    db = TestingSessionLocal()
    try:
        act_id = uuid.uuid4()
        act = Activo_Inventariado(
            id_activo=act_id,
            sku_qr_fisico=f"MOT-TRAS-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=31,
            id_estado=1,
            id_sucursal_actual=1,
            precio_referencia=500000,
            precio_minimo=400000,
            precio_maximo=600000,
            estado="Activo",
        )
        db.add(act)
        db.commit()
    finally:
        db.close()

    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Traslado",
        "id_sucursal_destino": 2,
        "total_venta": 500000,
        "monto_pendiente": 500000,
        "items_inventariados": [
            {
                "id_activo": str(act_id),
                "precio_final": 500000,
            }
        ],
        "datos_despacho": {
            "direccion_envio": "Traslado a Sucursal Limache",
            "receptor_nombres": "Cliente Destino",
            "receptor_rut": "18.765.432-1",
            "receptor_telefono": "+56912345678",
            "id_sucursal_destino": 2,
        }
    }

    res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["despacho_generado"] is True


# ── TEST 8: Rechazo de Traslado a la misma sucursal ──────────────────────────
def test_checkout_wizard_traslado_misma_sucursal_rechazo(client, wizard_db, auth_vendedor_wiz):
    """Rechaza traslado si la sucursal de destino coincide con la sucursal de la orden."""
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Traslado",
        "id_sucursal_destino": 30,  # Misma sucursal que el vendedor (id_sucursal=30)
        "total_venta": 500000,
        "monto_pendiente": 500000,
        "items_inventariados": [
            {
                "id_activo": str(uuid.uuid4()),
                "precio_final": 500000,
            }
        ],
    }

    res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert res.status_code == 400
    assert "no pueden ser iguales" in res.json()["detail"] or "no es válida" in res.json()["detail"]


# ── TEST 9: Descuento por Vale a Favor y Coherencia en Caja ───────────────────
def test_checkout_wizard_con_descuento_por_vale_a_favor(client, wizard_db, auth_vendedor_wiz, auth_caja_wiz):
    """Verifica que un descuento por vale a favor se guarde en la orden y sea visible en Caja."""
    payload = {
        "id_cliente": str(wizard_db["cliente_id"]),
        "tipo_entrega": "Retiro",
        "total_venta": 70000,
        "descuento": 30000,
        "monto_pendiente": 70000,
        "items_manuales": [{"descripcion": "Repuesto Especial", "cantidad": 1, "precio_unitario": 100000, "precio_final": 100000}],
    }

    res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert res.status_code == 201
    data = res.json()
    assert data["total_venta"] == 70000
    assert data["descuento"] == 30000
    id_orden = data["id_orden"]

    # Verificar visibilidad en lista de cobros pendientes de Caja
    res_caja = client.get("/api/v1/caja/pendientes?sucursal_id=30", headers=auth_caja_wiz)
    assert res_caja.status_code == 200
    pendientes = res_caja.json()["items"]
    orden_en_caja = next((p for p in pendientes if p["id_referencia"] == id_orden), None)
    assert orden_en_caja is not None
    assert orden_en_caja["total_operacion"] == 100000  # Total bruto antes del descuento
    assert orden_en_caja["descuento"] == 30000
    assert orden_en_caja["monto_a_cobrar"] == 70000  # Saldo neto a cobrar en caja


# ── TEST 10: Venta en Verde Rechaza Consumidor Final ─────────────────────────
def test_checkout_wizard_venta_en_verde_rechaza_consumidor_final(client, wizard_db, auth_vendedor_wiz):
    """Verifica que Venta en Verde rechaza emisión para Consumidor Final (RUT 6.666.666-6)."""
    db = TestingSessionLocal()
    try:
        cli_anon = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="6.666.666-6",
            nombres="Consumidor",
            apellidos="Final",
            telefono="+56912345678",
            id_comuna=30,
            estado="Activo"
        )
        db.add(cli_anon)
        db.commit()
        db.refresh(cli_anon)
        id_cli_anon = str(cli_anon.id_cliente)
    finally:
        db.close()

    payload = {
        "id_cliente": id_cli_anon,
        "tipo_entrega": "Retiro",
        "total_venta": 1200000,
        "monto_pendiente": 600000,
        "items_inventariados": [],
        "items_manuales": [],
        "reservas": [
            {
                "id_categoria_requerida": 31,
                "marca_requerida": "Toyota",
                "modelo_requerido": "Yaris",
                "anio_requerido": 2020,
                "precio_acordado": 1200000,
                "monto_abonado": 600000,
            }
        ],
    }

    res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert res.status_code == 400
    assert "Venta en Verde" in res.json()["detail"]
    assert "Consumidor Final" in res.json()["detail"]


# ── TEST 11: Venta en Verde Exige Teléfono de Contacto ────────────────────────
def test_checkout_wizard_venta_en_verde_exige_telefono(client, wizard_db, auth_vendedor_wiz):
    """Verifica que Venta en Verde exige registrar un teléfono válido del cliente."""
    db = TestingSessionLocal()
    try:
        cli_sin_tel = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="17.777.888-9",
            nombres="Carlos",
            apellidos="Gómez",
            telefono="",  # Vacío
            id_comuna=30,
            estado="Activo"
        )
        db.add(cli_sin_tel)
        db.commit()
        db.refresh(cli_sin_tel)
        id_cli_sin_tel = str(cli_sin_tel.id_cliente)
    finally:
        db.close()

    payload = {
        "id_cliente": id_cli_sin_tel,
        "tipo_entrega": "Retiro",
        "total_venta": 850000,
        "monto_pendiente": 425000,
        "items_inventariados": [],
        "items_manuales": [],
        "reservas": [
            {
                "id_categoria_requerida": 32,
                "marca_requerida": "Nissan",
                "modelo_requerido": "Versa",
                "anio_requerido": 2021,
                "precio_acordado": 850000,
                "monto_abonado": 425000,
            }
        ],
    }

    res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=auth_vendedor_wiz)
    assert res.status_code == 400
    assert "teléfono de contacto" in res.json()["detail"]

