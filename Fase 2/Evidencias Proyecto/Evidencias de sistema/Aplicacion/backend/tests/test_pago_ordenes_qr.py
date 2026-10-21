# test_pago_ordenes_qr.py
# Suite de pruebas automatizadas para HU-3.6 (Fase 1): Core de Pagos, Generación de QR Transaccional e Integración con Bodega.

import uuid
import pytest
from datetime import datetime

from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor, Orden_Venta,
    Detalle_Orden, Despacho, Cliente, Transaccion_Pago
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    """Inicializa datos base para pruebas de confirmación de pago y generación QR."""
    db = TestingSessionLocal()
    try:
        # 1. Geografía y Sucursal
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        db.add(c)

        suc1 = Sucursal(
            id_sucursal=1,
            nombre_sucursal="Casa Matriz - Viña",
            direccion="Camino Internacional 4105",
            id_comuna=1
        )
        db.add(suc1)

        # 2. Roles oficiales del sistema
        rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        db.add_all([rol_bodega, rol_vendedor, rol_caja])

        # 3. Usuarios (Vendedor, Cajera y Bodeguero)
        u_vendedor_id = uuid.uuid4()
        u_cajera_id = uuid.uuid4()
        u_bodeguero_id = uuid.uuid4()

        vendedor = Usuario(
            id_usuario=u_vendedor_id,
            id_rol=2,
            id_sucursal=1,
            rut_usuario="11.111.111-1",
            nombres="Vendedor",
            apellidos="Test",
            email="vendedor@cresal.cl",
            password_hash="hash",
            pin_acceso="1111",
            estado="Activo"
        )
        cajera = Usuario(
            id_usuario=u_cajera_id,
            id_rol=3,
            id_sucursal=1,
            rut_usuario="22.222.222-2",
            nombres="Cajera",
            apellidos="Matriz",
            email="cajera@cresal.cl",
            password_hash="hash",
            pin_acceso="2222",
            estado="Activo"
        )
        bodeguero = Usuario(
            id_usuario=u_bodeguero_id,
            id_rol=1,
            id_sucursal=1,
            rut_usuario="33.333.333-3",
            nombres="Bodeguero",
            apellidos="Turno",
            email="bodeguero@cresal.cl",
            password_hash="hash",
            pin_acceso="3333",
            estado="Activo"
        )
        db.add_all([vendedor, cajera, bodeguero])

        # 4. Categorías y Estados (incluyendo 'Entregado' para HU-3.6)
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambio")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_entregado = Estado_Activo(id_estado=6, nombre_estado="Entregado")
        db.add_all([est_disp, est_res, est_vend, est_entregado])

        # 5. Vehículo y Activo Inventariado
        veh1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-QR1",
            patente="QR1234",
            marca="Hyundai",
            modelo="Accent",
            anio=2020,
            traccion="4x2",
            estado="Activo"
        )
        db.add(veh1)

        act1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=act1_id,
            sku_qr_fisico="MOT-HYU-ACC-001",
            id_categoria=1,
            id_estado=2,  # Reservado
            id_sucursal_actual=1,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=450000,
            ubicacion_pasillo="P-04",
            ubicacion_pallet="PL-10",
            estado="Activo"
        )
        db.add(act1)

        # 6. Cliente
        cliente_1 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="19.876.543-2",
            nombres="Pedro",
            apellidos="Pascal",
            telefono="+56999887766",
            correo="pedro@correo.cl",
            id_comuna=1,
            consentimiento_legal=True,
            estado="Activo"
        )
        db.add(cliente_1)

        # 7. Orden Reservada 1 (Para pagar exitosamente)
        orden_1_id = uuid.uuid4()
        orden_1 = Orden_Venta(
            id_orden=orden_1_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_vendedor_id,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=450000,
            monto_pendiente=450000,
            qr_transaccional_salida=None,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_1)

        detalle_1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_1_id,
            id_activo=act1_id,
            notas_preparacion="Chequear nivel de compresión y embalar con plástico burbuja",
            cantidad=1,
            precio_unitario=450000,
            precio_final=450000,
        )
        db.add(detalle_1)

        # 8. Orden Anulada 2 (Para probar rechazo de pago)
        orden_2_id = uuid.uuid4()
        orden_2 = Orden_Venta(
            id_orden=orden_2_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_vendedor_id,
            id_sucursal=1,
            estado_orden="Anulada",
            total_venta=200000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_2)

        db.commit()

        return {
            "u_vendedor_id": u_vendedor_id,
            "u_cajera_id": u_cajera_id,
            "u_bodeguero_id": u_bodeguero_id,
            "orden_1_id": orden_1_id,
            "orden_2_id": orden_2_id,
            "act1_id": act1_id,
            "cliente_1_id": cliente_1.id_cliente,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_headers_cajera(db_session):
    token = create_access_token(data={"sub": str(db_session["u_cajera_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_bodeguero(db_session):
    token = create_access_token(data={"sub": str(db_session["u_bodeguero_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_vendedor(db_session):
    token = create_access_token(data={"sub": str(db_session["u_vendedor_id"])})
    return {"Authorization": f"Bearer {token}"}


# ==============================================================================
# TESTS DE CORE DE PAGOS Y GENERACIÓN DE QR TRANSACCIONAL (HU-3.6)
# ==============================================================================

def test_vendedor_no_puede_simular_pago_en_caja(client, db_session, auth_headers_vendedor):
    """
    Eliminación de Simulación: Verifica que un Vendedor NO puede realizar pagos directamente.
    Debe responder con HTTP 403 Forbidden exigiendo rol de Operario de Caja o Administrador.
    """
    orden_id = db_session["orden_1_id"]

    response = client.post(
        f"/api/v1/ordenes/{orden_id}/pagar",
        json={"metodo_pago": "Efectivo"},
        headers=auth_headers_vendedor
    )

    assert response.status_code == 403
    data = response.json()
    assert "Acceso restringido" in data["detail"]

def test_pago_orden_exitoso_y_generacion_qr(client, db_session, auth_headers_cajera):
    """
    Verifica que la cajera puede procesar el pago de una orden 'Reservada':
    - estado_orden pasa a 'Pagada'.
    - monto_pendiente pasa a 0.
    - id_cajera se registra correctamente.
    - Se crea el registro correspondiente en Transaccion_Pago.
    - Se genera un código QR transaccional único con prefijo TX-QR-.
    """
    orden_id = db_session["orden_1_id"]

    payload = {
        "metodo_pago": "Tarjeta de Débito",
        "monto": 450000,
        "observaciones": "Transbank Voucher #987654"
    }

    response = client.post(
        f"/api/v1/ordenes/{orden_id}/pagar",
        json=payload,
        headers=auth_headers_cajera
    )

    assert response.status_code == 200, f"Error: {response.text}"
    data = response.json()

    print(f"\n[TEST QA] Respuesta de pago recibido: {data}")

    # Validaciones del DTO de respuesta
    assert data["id_orden"] == str(orden_id)
    assert data["estado_orden"] == "Pagada"
    assert data["total_venta"] == 450000
    assert data["monto_pagado"] == 450000
    assert data["monto_pendiente"] == 0
    assert data["metodo_pago"] == "Tarjeta de Débito"
    assert data["id_cajera"] == str(db_session["u_cajera_id"])
    assert data["qr_transaccional_salida"] is not None
    assert data["qr_transaccional_salida"].startswith("TX-QR-")

    # Verificación en Base de Datos
    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == orden_id).first()
        assert orden_db is not None
        assert orden_db.estado_orden == "Pagada"
        assert orden_db.monto_pendiente == 0
        assert orden_db.id_cajera == db_session["u_cajera_id"]
        assert orden_db.qr_transaccional_salida == data["qr_transaccional_salida"]

        # Verificar Transaccion_Pago
        pago_db = db.query(Transaccion_Pago).filter(Transaccion_Pago.id_orden == orden_id).first()
        assert pago_db is not None
        assert pago_db.monto == 450000
        assert pago_db.metodo_pago == "Tarjeta de Débito"
        assert pago_db.estado_pago == "Procesado"

        # Verificar que el activo inventariado asociado a la orden cambió de 'Reservado' (2) a 'Vendido' (3)
        act1_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == db_session["act1_id"]).first()
        assert act1_db is not None
        assert act1_db.id_estado == 3, f"Se esperaba estado 3 (Vendido), pero tiene {act1_db.id_estado}"
    finally:
        db.close()


def test_rechazo_pago_orden_ya_pagada(client, db_session, auth_headers_cajera):
    """
    Intento de volver a pagar una orden que ya está en estado 'Pagada'.
    Debe responder con HTTP 400 Bad Request y mensaje explícito.
    """
    orden_id = db_session["orden_1_id"]

    response = client.post(
        f"/api/v1/ordenes/{orden_id}/pagar",
        json={"metodo_pago": "Efectivo"},
        headers=auth_headers_cajera
    )

    assert response.status_code == 400
    data = response.json()
    assert "ya se encuentra en estado 'Pagada'" in data["detail"] or "pago confirmado" in data["detail"]


def test_rechazo_pago_orden_anulada(client, db_session, auth_headers_cajera):
    """
    Intento de pagar una orden en estado 'Anulada'.
    Debe responder con HTTP 400 Bad Request.
    """
    orden_anulada_id = db_session["orden_2_id"]

    response = client.post(
        f"/api/v1/ordenes/{orden_anulada_id}/pagar",
        json={"metodo_pago": "Efectivo"},
        headers=auth_headers_cajera
    )

    assert response.status_code == 400
    data = response.json()
    assert "Anulada" in data["detail"]


def test_rechazo_pago_orden_inexistente(client, auth_headers_cajera):
    """
    Intento de pagar una orden inexistente con UUID aleatorio.
    Debe responder con HTTP 404 Not Found.
    """
    random_id = uuid.uuid4()
    response = client.post(
        f"/api/v1/ordenes/{random_id}/pagar",
        json={"metodo_pago": "Efectivo"},
        headers=auth_headers_cajera
    )

    assert response.status_code == 404
    data = response.json()
    assert "no encontrada" in data["detail"].lower()


def test_impacto_en_alertas_bodega_tras_pago(client, db_session, auth_headers_cajera, auth_headers_bodeguero):
    """
    Verifica que antes del pago la tarea de bodega está bloqueada ('PREPARACION' / 'EN ESPERA'),
    y tras confirmar el pago se desbloquea inmediatamente a 'LIBERADA' con 'ESCANEAR EN BARRERA'.
    """
    # 1. Crear una nueva orden reservada en la BD
    db = TestingSessionLocal()
    nueva_orden_id = uuid.uuid4()
    nuevo_activo_id = uuid.uuid4()
    try:
        veh = db.query(Vehiculo_Origen).first()
        nuevo_act = Activo_Inventariado(
            id_activo=nuevo_activo_id,
            sku_qr_fisico="MOT-TEST-BOD-002",
            id_categoria=1,
            id_estado=2,  # Reservado
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            precio_referencia=300000,
            ubicacion_pasillo="P-02",
            ubicacion_pallet="PL-05",
            estado="Activo"
        )
        db.add(nuevo_act)

        orden_bodega = Orden_Venta(
            id_orden=nueva_orden_id,
            id_cliente=db_session["cliente_1_id"],
            id_vendedor=db_session["u_vendedor_id"],
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=300000,
            monto_pendiente=300000,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_bodega)

        det = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=nueva_orden_id,
            id_activo=nuevo_activo_id,
            notas_preparacion="Limpiar sensor de oxígeno",
            cantidad=1,
            precio_unitario=300000,
            precio_final=300000,
        )
        db.add(det)
        db.commit()
    finally:
        db.close()

    # 2. Consultar alertas en bodega ANTES del pago
    resp_antes = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodeguero)
    assert resp_antes.status_code == 200
    alertas_antes = resp_antes.json()

    # Encontrar la alerta de esta orden
    alerta_orden_antes = next(
        (a for a in alertas_antes if str(a.get("id_orden")) == str(nueva_orden_id)),
        None
    )
    assert alerta_orden_antes is not None
    assert alerta_orden_antes["tipo_alerta"] == "PREPARACION"
    assert alerta_orden_antes["estado_bloqueo"] == "ESPERANDO PAGO EN CAJA"
    assert alerta_orden_antes["accion_requerida"] == "EN ESPERA"
    assert (alerta_orden_antes.get("orden_ref") or "").startswith("ORD-")

    # 3. Cajera procesa el pago
    resp_pago = client.post(
        f"/api/v1/ordenes/{nueva_orden_id}/pagar",
        json={"metodo_pago": "Efectivo", "monto": 300000},
        headers=auth_headers_cajera
    )
    assert resp_pago.status_code == 200
    qr_emitido = resp_pago.json()["qr_transaccional_salida"]
    assert qr_emitido.startswith("TX-QR-")

    # 4. Consultar alertas en bodega DESPUÉS del pago (simulación de Pull-to-Refresh del Bodeguero)
    resp_despues = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodeguero)
    assert resp_despues.status_code == 200
    alertas_despues = resp_despues.json()

    alerta_orden_despues = next(
        (a for a in alertas_despues if str(a.get("id_orden")) == str(nueva_orden_id)),
        None
    )
    assert alerta_orden_despues is not None
    assert alerta_orden_despues["tipo_alerta"] == "LIBERADA"
    assert alerta_orden_despues["estado_bloqueo"] is None
    assert alerta_orden_despues["accion_requerida"] == "ESCANEAR EN BARRERA"
    assert (alerta_orden_despues.get("orden_ref") or "").startswith("ORD-")
    print(f"\n[TEST QA] Tarea en bodega desbloqueada exitosamente: {alerta_orden_despues}")

    # Verificar en BD que el activo quedó en estado 3 ('Vendido')
    db = TestingSessionLocal()
    try:
        act_bodega_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == nuevo_activo_id).first()
        assert act_bodega_db is not None
        assert act_bodega_db.id_estado == 3, f"Se esperaba estado 3 (Vendido), pero tiene {act_bodega_db.id_estado}"
    finally:
        db.close()


def test_pago_orden_miscelaneos_sin_qr(client, db_session, auth_headers_cajera):
    """
    Tarea 1: Verifica que al liquidar una orden en /pagar cuyos ítems no tienen id_activo
    (solo servicios o piezas misceláneas sin serial físico) y sin despacho, la orden pasa
    automáticamente a 'Completada' (cero clics para el vendedor), con qr_transaccional_salida en None
    y la preparación marcada como 'Listo'.
    """
    db = TestingSessionLocal()
    try:
        ord_misc_id = uuid.uuid4()
        ord_misc = Orden_Venta(
            id_orden=ord_misc_id,
            id_cliente=db_session["cliente_1_id"],
            id_vendedor=db_session["u_vendedor_id"],
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida=None,
            total_venta=30000,
            monto_pendiente=30000,
            fecha_creacion=datetime.now(),
        )
        db.add(ord_misc)

        det_misc_id = uuid.uuid4()
        det_misc = Detalle_Orden(
            id_detalle=det_misc_id,
            id_orden=ord_misc_id,
            id_activo=None,
            descripcion_manual="Mano de Obra y Montaje",
            cantidad=1,
            precio_unitario=30000,
            precio_final=30000,
        )
        db.add(det_misc)
        db.commit()
    finally:
        db.close()

    payload = {
        "metodo_pago": "Efectivo",
        "monto": 30000,
        "observaciones": "Liquidación de servicios"
    }

    response = client.post(
        f"/api/v1/ordenes/{ord_misc_id}/pagar",
        json=payload,
        headers=auth_headers_cajera
    )
    assert response.status_code == 200
    data = response.json()
    assert data["estado_orden"] == "Completada"
    assert data["monto_pendiente"] == 0
    assert data["qr_transaccional_salida"] is None

    # Verificar en BD
    db = TestingSessionLocal()
    try:
        ord_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == ord_misc_id).first()
        assert ord_db.estado_orden == "Completada"
        assert ord_db.qr_transaccional_salida is None

        det_db = db.query(Detalle_Orden).filter(Detalle_Orden.id_detalle == det_misc_id).first()
        assert det_db.estado_preparacion == "Listo"
    finally:
        db.close()
