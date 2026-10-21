# backend/tests/test_bodega_reingresos.py
# Suite de pruebas automatizadas para SPEC-HU-TAREA-4:
# Flujo de Logística Inversa y Tareas de Reingreso/Paletizado tras Anulación de Órdenes.

import uuid
import pytest
from datetime import datetime, timezone

from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor, Orden_Venta,
    Detalle_Orden, Cliente, Transaccion_Pago
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def reingreso_db(setup_database):
    db = TestingSessionLocal()
    try:
        # Seed Base
        r = Region(id_region=10, nombre_region="Valparaíso - Reingresos")
        db.add(r)
        c = Comuna(id_comuna=10, nombre_comuna="Viña del Mar - Reingresos", id_region=10)
        db.add(c)

        suc1 = Sucursal(id_sucursal=10, nombre_sucursal="Sucursal Reingreso", direccion="Av. Prueba 123", id_comuna=10)
        db.add(suc1)

        rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        db.add_all([rol_bodega, rol_vendedor, rol_caja, rol_admin])

        u_bodega_id = uuid.uuid4()
        u_vendedor_id = uuid.uuid4()

        # Usuarios
        user_bodeguero = Usuario(
            id_usuario=u_bodega_id,
            id_rol=1,
            id_sucursal=10,
            rut_usuario="10.111.111-1",
            nombres="Bodeguero",
            apellidos="Test",
            email="bodega_reingreso@cresal.cl",
            password_hash="hash",
            pin_acceso="1111",
            estado="Activo"
        )
        user_vendedor = Usuario(
            id_usuario=u_vendedor_id,
            id_rol=2,
            id_sucursal=10,
            rut_usuario="10.222.222-2",
            nombres="Vendedor",
            apellidos="Test",
            email="vendedor_reingreso@cresal.cl",
            password_hash="hash",
            pin_acceso="2222",
            estado="Activo"
        )
        db.add_all([user_bodeguero, user_vendedor])

        # Categorías y Estados
        cat_motor = Categoria_Activo(id_categoria=10, nombre_categoria="Motor Reingreso")
        cat_caja = Categoria_Activo(id_categoria=20, nombre_categoria="Caja Reingreso")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_ven = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_pend = Estado_Activo(id_estado=5, nombre_estado="Pendiente de Paletizado")
        est_ent = Estado_Activo(id_estado=6, nombre_estado="Entregado")
        est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
        for est in [est_disp, est_res, est_ven, est_pend, est_ent, est_pal]:
            db.merge(est)

        # Vehículo Origen
        v_id = uuid.uuid4()
        veh = Vehiculo_Origen(
            id_vehiculo=v_id,
            numero_ingreso="ING-REI-01",
            patente="REI123",
            vin="VINREI12345678901",
            marca="Nissan",
            modelo="Sentra",
            anio=2021,
            traccion="4x2",
            estado="Activo"
        )
        db.add(veh)

        # Activo Inventariado 1
        act1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=act1_id,
            sku_qr_fisico="MOT-NIS-SEN-001",
            id_categoria=10,
            id_estado=3,  # Vendido
            id_sucursal_actual=10,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PAL-01",
            precio_referencia=750000,
            version_lock=1,
            estado="Activo"
        )
        # Activo Inventariado 2
        act2_id = uuid.uuid4()
        act2 = Activo_Inventariado(
            id_activo=act2_id,
            sku_qr_fisico="CAJ-NIS-SEN-002",
            id_categoria=20,
            id_estado=2,  # Reservado
            id_sucursal_actual=10,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PAL-02",
            precio_referencia=450000,
            version_lock=1,
            estado="Activo"
        )
        db.add_all([act1, act2])

        # Cliente
        cli_id = uuid.uuid4()
        cli = Cliente(
            id_cliente=cli_id,
            rut_cliente="15.888.999-0",
            nombres="Pedro",
            apellidos="Reingresos",
            telefono="+56912345678",
            correo="pedro.reingresos@cresal.cl",
            id_comuna=10,
            consentimiento_legal=True,
            estado="Activo"
        )
        db.add(cli)

        # Orden de Venta Pagada (Orden A)
        ord_a_id = uuid.uuid4()
        ord_a = Orden_Venta(
            id_orden=ord_a_id,
            id_cliente=cli.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=10,
            estado_orden="Pagada",
            total_venta=750000,
            monto_pendiente=0,
            qr_transaccional_salida="TX-QR-ORD-A-001",
            fecha_creacion=datetime.now(timezone.utc)
        )
        db.add(ord_a)

        det_a = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord_a.id_orden,
            id_activo=act1.id_activo,
            descripcion_manual="Motor Nissan Sentra 2021",
            cantidad=1,
            precio_final=750000,
            estado_preparacion="Listo"
        )
        db.add(det_a)

        pago_a = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord_a.id_orden,
            monto=750000,
            metodo_pago="Transferencia",
            estado_pago="Procesado",
            fecha_pago=datetime.now(timezone.utc)
        )
        db.add(pago_a)

        # Orden de Venta Reservada (Orden B)
        ord_b_id = uuid.uuid4()
        ord_b = Orden_Venta(
            id_orden=ord_b_id,
            id_cliente=cli.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=10,
            estado_orden="Reservada",
            total_venta=450000,
            monto_pendiente=450000,
            qr_transaccional_salida="TX-QR-ORD-B-002",
            fecha_creacion=datetime.now(timezone.utc)
        )
        db.add(ord_b)

        det_b = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord_b.id_orden,
            id_activo=act2.id_activo,
            descripcion_manual="Caja de Cambios Sentra 2021",
            cantidad=1,
            precio_final=450000,
            estado_preparacion="Pendiente"
        )
        db.add(det_b)

        db.commit()

        return {
            "bodeguero_id": u_bodega_id,
            "vendedor_id": u_vendedor_id,
            "orden_a_id": ord_a_id,
            "orden_b_id": ord_b_id,
            "activo_1_id": act1_id,
            "activo_2_id": act2_id,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_bodeguero(reingreso_db):
    token = create_access_token(data={"sub": str(reingreso_db["bodeguero_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_vendedor(reingreso_db):
    token = create_access_token(data={"sub": str(reingreso_db["vendedor_id"])})
    return {"Authorization": f"Bearer {token}"}


# ── TEST 1: Anulación ACID de Orden Pagada con Reversa de Pagos ───────────────
def test_anular_orden_pagada_reversa_pagos_y_genera_tarea_reingreso(client, reingreso_db, auth_vendedor):
    id_orden = str(reingreso_db["orden_a_id"])
    payload = {"motivo_anulacion": "Cliente solicitó devolución antes del retiro"}

    response = client.post(f"/api/v1/ordenes/{id_orden}/anular", json=payload, headers=auth_vendedor)
    assert response.status_code == 200

    data = response.json()
    assert data["id_orden"] == id_orden
    assert data["estado_orden"] == "Anulada"
    assert "Orden anulada, pagos reversados y tareas de reingreso generadas" in data["mensaje"]
    assert data["pagos_reversados"] >= 1
    assert data["motivo_anulacion"] == "Cliente solicitó devolución antes del retiro"

    # Verificar en Base de Datos
    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == uuid.UUID(id_orden)).first()
        assert orden_db.estado_orden == "Anulada"
        assert orden_db.monto_pendiente == 0

        pago_db = db.query(Transaccion_Pago).filter(Transaccion_Pago.id_orden == uuid.UUID(id_orden)).first()
        assert pago_db.estado_pago == "Anulado"

        activo_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == reingreso_db["activo_1_id"]).first()
        assert activo_db.id_estado == 1  # Disponible en catálogo inmediatamente
    finally:
        db.close()


# ── TEST 2: Bodeguero Consulta Lista de Reingresos Pendientes ─────────────────
def test_bodega_consulta_reingresos_pendientes(client, reingreso_db, auth_bodeguero):
    response = client.get("/api/v1/bodega/reingresos-pendientes?sucursal_id=10", headers=auth_bodeguero)
    assert response.status_code == 200

    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1

    sku_encontrado = any(item["sku_qr_fisico"] == "MOT-NIS-SEN-001" for item in data)
    assert sku_encontrado is True

    item_mot = next(item for item in data if item["sku_qr_fisico"] == "MOT-NIS-SEN-001")
    assert item_mot["id_orden"] == str(reingreso_db["orden_a_id"])
    assert "Nissan Sentra" in item_mot["descripcion_pieza"] or "Motor" in item_mot["descripcion_pieza"]


# ── TEST 3: Confirmación de Reingreso por PDA y Control de Concurrencia ───────
def test_confirmar_reingreso_exitoso_y_version_lock(client, reingreso_db, auth_bodeguero):
    db_check = TestingSessionLocal()
    version_inicial = 0
    try:
        act = db_check.query(Activo_Inventariado).filter(Activo_Inventariado.sku_qr_fisico == "MOT-NIS-SEN-001").first()
        version_inicial = act.version_lock
    finally:
        db_check.close()

    payload = {
        "sku_qr_fisico": "MOT-NIS-SEN-001",
        "id_orden_anulada": str(reingreso_db["orden_a_id"]),
        "ubicacion_pasillo": "P-03",
        "ubicacion_pallet": "PAL-99",
        "ubicacion_galpon": "1",
    }

    response = client.post("/api/v1/bodega/confirmar-reingreso", json=payload, headers=auth_bodeguero)
    assert response.status_code == 200

    data = response.json()
    assert "exitosamente" in data["msg"]
    assert data["sku_qr_fisico"] == "MOT-NIS-SEN-001"
    assert data["nuevo_estado"] == "Disponible"
    assert data["ubicacion_pasillo"] == "P-03"
    assert data["ubicacion_pallet"] == "PAL-99"
    assert data["ubicacion_galpon"] == "1"

    # SPEC-HU-TAREA-19: El activo permanece en estado Disponible (1) fijado por ventas,
    # se actualiza su ubicación física en rack y NO se incrementa version_lock en bodega
    db = TestingSessionLocal()
    try:
        act_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.sku_qr_fisico == "MOT-NIS-SEN-001").first()
        assert act_db.id_estado == 1
        assert act_db.ubicacion_pasillo == "P-03"
        assert act_db.ubicacion_pallet == "PAL-99"
        assert act_db.ubicacion_galpon == "1"
        assert act_db.version_lock == version_inicial
    finally:
        db.close()

    # Verificar que ya no aparece en reingresos pendientes
    response_pend = client.get("/api/v1/bodega/reingresos-pendientes?sucursal_id=10", headers=auth_bodeguero)
    assert response_pend.status_code == 200
    data_pend = response_pend.json()
    assert not any(item["sku_qr_fisico"] == "MOT-NIS-SEN-001" for item in data_pend)


# ── TEST 4: Rechazo al Confirmar Reingreso de SKU no perteneciente a la orden ─
def test_rechazo_reingreso_sku_incorrecto(client, reingreso_db, auth_bodeguero):
    payload = {
        "sku_qr_fisico": "CAJ-NIS-SEN-002",  # Pertenece a Orden B, no a Orden A
        "id_orden_anulada": str(reingreso_db["orden_a_id"]),
        "ubicacion_pasillo": "P-01",
        "ubicacion_pallet": "PAL-01"
    }

    response = client.post("/api/v1/bodega/confirmar-reingreso", json=payload, headers=auth_bodeguero)
    assert response.status_code == 400
    assert "no pertenece a la orden anulada" in response.json()["detail"]


# ── TEST 5: Rechazo al Anular Orden ya Anulada ────────────────────────────────
def test_rechazo_anular_orden_ya_anulada(client, reingreso_db, auth_vendedor):
    id_orden = str(reingreso_db["orden_a_id"])
    payload = {"motivo_anulacion": "Reintento de anulación"}

    response = client.post(f"/api/v1/ordenes/{id_orden}/anular", json=payload, headers=auth_vendedor)
    assert response.status_code == 400
    assert "ya se encuentra anulada" in response.json()["detail"]


# ── TEST 6: RBAC: Bodeguero no puede anular orden y Vendedor no puede confirmar reingreso ──
def test_control_acceso_rbac_anulacion_y_reingreso(client, reingreso_db, auth_bodeguero, auth_vendedor):
    id_orden = str(reingreso_db["orden_b_id"])

    # 1. Bodeguero intenta anular -> 403
    res_bodega = client.post(f"/api/v1/ordenes/{id_orden}/anular", json={}, headers=auth_bodeguero)
    assert res_bodega.status_code == 403

    # 2. Vendedor anula Orden B -> 200
    res_anulacion = client.post(f"/api/v1/ordenes/{id_orden}/anular", json={"motivo_anulacion": "Cambio por otro repuesto"}, headers=auth_vendedor)
    assert res_anulacion.status_code == 200

    # 3. Vendedor intenta confirmar reingreso -> 403
    payload_reingreso = {
        "sku_qr_fisico": "CAJ-NIS-SEN-002",
        "id_orden_anulada": id_orden,
        "ubicacion_pasillo": "P-04",
        "ubicacion_pallet": "PAL-10"
    }
    res_vend_reingreso = client.post("/api/v1/bodega/confirmar-reingreso", json=payload_reingreso, headers=auth_vendedor)
    assert res_vend_reingreso.status_code == 403

    # 4. Bodeguero confirma reingreso de Orden B -> 200
    res_bod_reingreso = client.post("/api/v1/bodega/confirmar-reingreso", json=payload_reingreso, headers=auth_bodeguero)
    assert res_bod_reingreso.status_code == 200
