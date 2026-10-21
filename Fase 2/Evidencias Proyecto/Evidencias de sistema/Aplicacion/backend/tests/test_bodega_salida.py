# backend/test_bodega_salida.py
# Suite de pruebas automatizadas para HU-3.6 (Fase 3): Handshake de Salida en Bodega y Dual-Scan.

import pytest
import uuid
from datetime import datetime

from conftest import TestingSessionLocal
from models import (
    Usuario,
    Rol,
    Sucursal,
    Region,
    Comuna,
    Cliente,
    Vehiculo_Origen,
    Categoria_Activo,
    Estado_Activo,
    Activo_Inventariado,
    Orden_Venta,
    Detalle_Orden,
    Auditoria_Barrera,
    Detalle_Motor,
    Detalle_Caja_Cambio,
)
from core.security import create_access_token


@pytest.fixture(scope="module")
def db_session(setup_database):
    db = TestingSessionLocal()
    try:
        # 1. Geografía
        reg = Region(id_region=1, nombre_region="Valparaíso")
        com = Comuna(id_comuna=1, nombre_comuna="Quilpué", id_region=1)
        db.add_all([reg, com])

        # 2. Sucursales
        sucursal_1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz Quilpué", id_comuna=1, direccion="Av. Los Carrera 100")
        sucursal_2 = Sucursal(id_sucursal=2, nombre_sucursal="Sucursal Viña", id_comuna=1, direccion="Av. Libertad 500")
        db.add_all([sucursal_1, sucursal_2])

        # 3. Roles
        rol_vendedor = Rol(id_rol=1, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=2, nombre_rol="Caja")
        rol_bodega = Rol(id_rol=3, nombre_rol="Bodeguero")
        db.add_all([rol_vendedor, rol_caja, rol_bodega])

        # 4. Usuarios
        u_bodeguero_id = uuid.uuid4()
        bodeguero = Usuario(
            id_usuario=u_bodeguero_id,
            id_rol=3,
            id_sucursal=1,
            rut_usuario="33.333.333-3",
            nombres="Martín",
            apellidos="Bodeguero",
            email="martin.bodega@cresal.cl",
            password_hash="hash",
            pin_acceso="3333",
            estado="Activo"
        )

        u_bodeguero_suc2_id = uuid.uuid4()
        bodeguero_suc2 = Usuario(
            id_usuario=u_bodeguero_suc2_id,
            id_rol=3,
            id_sucursal=2,
            rut_usuario="44.444.444-4",
            nombres="Pedro",
            apellidos="Sucursal2",
            email="pedro.suc2@cresal.cl",
            password_hash="hash",
            pin_acceso="4444",
            estado="Activo"
        )
        db.add_all([bodeguero, bodeguero_suc2])

        # 5. Categorías y Estados
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambio")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_entregado = Estado_Activo(id_estado=6, nombre_estado="Entregado")
        db.add_all([est_disp, est_res, est_vend, est_entregado])

        # 6. Vehículo y Activos
        veh1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-BOD1",
            patente="BOD123",
            marca="Toyota",
            modelo="Yaris",
            anio=2019,
            traccion="4x2",
            estado="Activo"
        )
        db.add(veh1)

        # Activo 1: Repuesto que será entregado
        act1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=act1_id,
            sku_qr_fisico="MOT-TOY-YAR-888",
            id_categoria=1,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=500000,
            ubicacion_pasillo="P-03",
            ubicacion_pallet="PL-07",
            ubicacion_galpon="G-01",
            qr_impreso=True,
            estado="Activo"
        )

        # Activo 2: Repuesto en el MISMO pallet que NO debe verse afectado
        act2_id = uuid.uuid4()
        act2 = Activo_Inventariado(
            id_activo=act2_id,
            sku_qr_fisico="CAJ-TOY-YAR-999",
            id_categoria=2,
            id_estado=1,  # Disponible
            id_sucursal_actual=1,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=350000,
            ubicacion_pasillo="P-03",
            ubicacion_pallet="PL-07",
            ubicacion_galpon="G-01",
            estado="Activo"
        )

        # Activo 3 y 4: Para orden con múltiples piezas
        act3_id = uuid.uuid4()
        act3 = Activo_Inventariado(
            id_activo=act3_id,
            sku_qr_fisico="MOT-HYU-ACC-333",
            id_categoria=1,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=400000,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PL-02",
            qr_impreso=True,
            estado="Activo"
        )

        act4_id = uuid.uuid4()
        act4 = Activo_Inventariado(
            id_activo=act4_id,
            sku_qr_fisico="CAJ-HYU-ACC-444",
            id_categoria=2,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=250000,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PL-03",
            qr_impreso=True,
            estado="Activo"
        )

        db.add_all([act1, act2, act3, act4])

        # 7. Cliente
        cliente_1 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="12.345.678-9",
            nombres="Roberto",
            apellidos="Gómez",
            telefono="+56911223344",
            correo="roberto@correo.cl",
            id_comuna=1,
            consentimiento_legal=True,
            estado="Activo"
        )
        db.add(cliente_1)

        # 8. Órdenes de prueba
        # Orden 1: Pagada con 1 repuesto físico (lista para salida exitosa)
        orden_1_id = uuid.uuid4()
        token_orden_1 = f"TX-QR-{str(orden_1_id)[:8].upper()}-AAAA1111BBBB"
        orden_1 = Orden_Venta(
            id_orden=orden_1_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_bodeguero_id,
            id_cajera=u_bodeguero_id,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=token_orden_1,
            total_venta=500000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        det_1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_1_id,
            id_activo=act1_id,
            notas_preparacion="Entregar con alternador incluido",
            cantidad=1,
            precio_unitario=500000,
            precio_final=500000,
        )
        db.add_all([orden_1, det_1])

        # Orden 2: Con 1 repuesto inventariado + 1 ítem venta libre (Servicio de Desmontaje)
        orden_2_id = uuid.uuid4()
        token_orden_2 = f"TX-QR-{str(orden_2_id)[:8].upper()}-CCCC2222DDDD"
        orden_2 = Orden_Venta(
            id_orden=orden_2_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_bodeguero_id,
            id_cajera=u_bodeguero_id,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=token_orden_2,
            total_venta=450000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        det_2_a = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_2_id,
            id_activo=act3_id,
            notas_preparacion="Chequear correas",
            cantidad=1,
            precio_unitario=400000,
            precio_final=400000,
        )
        det_2_b = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_2_id,
            id_activo=None,  # Venta libre / misceláneo
            descripcion_manual="Servicio de Limpieza y Embalaje",
            cantidad=1,
            precio_unitario=50000,
            precio_final=50000,
        )
        db.add_all([orden_2, det_2_a, det_2_b])

        # Orden 3: Con múltiples repuestos físicos (act3 y act4)
        orden_3_id = uuid.uuid4()
        token_orden_3 = f"TX-QR-{str(orden_3_id)[:8].upper()}-EEEE3333FFFF"
        orden_3 = Orden_Venta(
            id_orden=orden_3_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_bodeguero_id,
            id_cajera=u_bodeguero_id,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=token_orden_3,
            total_venta=650000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        det_3_a = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_3_id,
            id_activo=act3_id,
            cantidad=1,
            precio_unitario=400000,
            precio_final=400000,
        )
        det_3_b = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_3_id,
            id_activo=act4_id,
            cantidad=1,
            precio_unitario=250000,
            precio_final=250000,
        )
        db.add_all([orden_3, det_3_a, det_3_b])

        # Orden 4: Reservada (No Pagada)
        orden_4_id = uuid.uuid4()
        token_orden_4 = f"TX-QR-{str(orden_4_id)[:8].upper()}-GGGG4444HHHH"
        orden_4 = Orden_Venta(
            id_orden=orden_4_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_bodeguero_id,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida=token_orden_4,
            total_venta=300000,
            monto_pendiente=300000,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_4)

        # Orden 5: Anulada
        orden_5_id = uuid.uuid4()
        token_orden_5 = f"TX-QR-{str(orden_5_id)[:8].upper()}-IIII5555JJJJ"
        orden_5 = Orden_Venta(
            id_orden=orden_5_id,
            id_cliente=cliente_1.id_cliente,
            id_vendedor=u_bodeguero_id,
            id_sucursal=1,
            estado_orden="Anulada",
            qr_transaccional_salida=token_orden_5,
            total_venta=200000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_5)

        db.commit()

        return {
            "u_bodeguero_id": u_bodeguero_id,
            "u_bodeguero_suc2_id": u_bodeguero_suc2_id,
            "orden_1_id": orden_1_id,
            "token_orden_1": token_orden_1,
            "act1_id": act1_id,
            "act2_id": act2_id,
            "orden_2_id": orden_2_id,
            "token_orden_2": token_orden_2,
            "orden_3_id": orden_3_id,
            "token_orden_3": token_orden_3,
            "orden_4_id": orden_4_id,
            "token_orden_4": token_orden_4,
            "orden_5_id": orden_5_id,
            "token_orden_5": token_orden_5,
            "act3_id": act3_id,
            "act4_id": act4_id,
            "cliente_1_id": cliente_1.id_cliente,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_headers_bodeguero(db_session):
    token = create_access_token(data={"sub": str(db_session["u_bodeguero_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_bodeguero_suc2(db_session):
    token = create_access_token(data={"sub": str(db_session["u_bodeguero_suc2_id"])})
    return {"Authorization": f"Bearer {token}"}


# ==============================================================================
# 1. TESTS DE INSPECCIÓN PREVIA: POST /verificar-qr-salida
# ==============================================================================

def test_verificar_qr_salida_exitoso(client, db_session, auth_headers_bodeguero):
    """
    Bodeguero escanea el QR en la pantalla del vendedor para ver los detalles de la orden
    antes de buscar la pieza en bodega.
    """
    token = db_session["token_orden_1"]

    response = client.post(
        "/api/v1/bodega/verificar-qr-salida",
        json={"qr_transaccional_salida": token},
        headers=auth_headers_bodeguero
    )

    assert response.status_code == 200, f"Error: {response.text}"
    data = response.json()

    print(f"\n[TEST QA] Datos de inspección previa recibidos: {data}")
    assert data["id_orden"] == str(db_session["orden_1_id"])
    assert data["estado_orden"] == "Pagada"
    assert data["monto_pendiente"] == 0
    assert data["cliente_nombre"] == "Roberto Gómez"
    assert data["cliente_rut"] == "12.345.678-9"
    assert data["total_items_fisicos"] == 1
    assert len(data["items_requeridos"]) == 1

    item = data["items_requeridos"][0]
    assert item["sku_qr_fisico"] == "MOT-TOY-YAR-888"
    assert item["es_inventariado"] is True
    assert "P-03" in item["ubicacion"] and "PL-07" in item["ubicacion"]
    assert item["notas_preparacion"] == "Entregar con alternador incluido"


def test_verificar_qr_salida_inexistente(client, auth_headers_bodeguero):
    """QR inexistente debe responder con HTTP 404."""
    response = client.post(
        "/api/v1/bodega/verificar-qr-salida",
        json={"qr_transaccional_salida": "TX-QR-INVENTADO-1234567890AB"},
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 404
    assert "no encontrado" in response.json()["detail"].lower()


# ==============================================================================
# 2. TESTS DE SALIDA DUAL-SCAN Y TRANSACCIÓN ACID: POST /escanear-salida
# ==============================================================================

def test_escanear_salida_dual_scan_exitoso_y_liberacion_rack(client, db_session, auth_headers_bodeguero):
    """
    Validación completa del Handshake:
    - Token digital del vendedor coincide con orden pagada.
    - SKU físico escaneado coincide con el repuesto de la orden.
    - Orden pasa a 'Completada'.
    - Activo pasa a 'Entregado' (ID 6).
    - Ubicación en rack (P-03, PL-07, G-01) del activo entregado pasa a None.
    - El Activo 2 que compartía el mismo pallet permanece con su ubicación intacta.
    """
    token = db_session["token_orden_1"]
    sku_fisico = "MOT-TOY-YAR-888"

    payload = {
        "qr_transaccional_salida": token,
        "skus_escaneados": [sku_fisico],
        "observaciones_entrega": "Pieza revisada e inspeccionada en barrera."
    }

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json=payload,
        headers=auth_headers_bodeguero
    )

    assert response.status_code == 200, f"Error: {response.text}"
    data = response.json()

    print(f"\n[TEST QA] Respuesta de entrega completada (Cero-Clics): {data}")
    assert data["id_orden"] == str(db_session["orden_1_id"])
    assert data["estado_orden"] == "Completada"
    assert data["id_bodeguero"] == str(db_session["u_bodeguero_id"])
    assert data["bodeguero_nombre"] == "Martín Bodeguero"
    assert data["total_entregados"] == 1
    assert sku_fisico in data["activos_entregados"]

    # Verificación en Base de Datos
    db = TestingSessionLocal()
    try:
        # A. Orden en estado Completada
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == db_session["orden_1_id"]).first()
        assert orden_db.estado_orden == "Completada"

        # B. Activo 1 en estado 6 (Entregado) y con rack liberado
        act1_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == db_session["act1_id"]).first()
        assert act1_db.id_estado == 6, f"Se esperaba estado 6 (Entregado), pero tiene {act1_db.id_estado}"
        assert act1_db.ubicacion_pasillo is None
        assert act1_db.ubicacion_pallet is None
        assert act1_db.ubicacion_galpon is None
        assert "Entregado en barrera" in (act1_db.observacion_estado or "")

        # C. Activo 2 (mismo pallet PL-07) NO fue afectado y mantiene su ubicación
        act2_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == db_session["act2_id"]).first()
        assert act2_db.id_estado == 1  # Disponible
        assert act2_db.ubicacion_pasillo == "P-03"
        assert act2_db.ubicacion_pallet == "PL-07"
        assert act2_db.ubicacion_galpon == "G-01"

        # D. Registro de Auditoria_Barrera persistido correctamente
        auditoria_db = db.query(Auditoria_Barrera).filter(Auditoria_Barrera.id_orden == db_session["orden_1_id"]).first()
        assert auditoria_db is not None
        assert auditoria_db.id_bodeguero == db_session["u_bodeguero_id"]
        assert auditoria_db.match_exitoso is True
        assert auditoria_db.id_orden == db_session["orden_1_id"]
    finally:
        db.close()


def test_escanear_salida_con_item_venta_libre_cero_clics(client, db_session, auth_headers_bodeguero):
    """
    Regla Cero-Clics: Si la orden tiene repuestos físicos Y servicios/venta libre (id_activo == None),
    el escaneo solo exige el SKU del repuesto físico y no bloquea por el ítem no inventariado.
    """
    token = db_session["token_orden_2"]
    sku_fisico = "MOT-HYU-ACC-333"

    payload = {
        "qr_transaccional_salida": token,
        "skus_escaneados": [sku_fisico]
    }

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json=payload,
        headers=auth_headers_bodeguero
    )

    assert response.status_code == 200, f"Error: {response.text}"
    data = response.json()
    assert data["estado_orden"] == "Completada"
    assert data["total_entregados"] == 1
    assert sku_fisico in data["activos_entregados"]
    assert data["folio"].startswith("ORD-")

    # Verificar que el ítem misceláneo/venta libre fue marcado 'Listo' automáticamente sin botón
    db_chk = TestingSessionLocal()
    try:
        det_vl = (
            db_chk.query(Detalle_Orden)
            .join(Orden_Venta, Detalle_Orden.id_orden == Orden_Venta.id_orden)
            .filter(
                Orden_Venta.qr_transaccional_salida == token,
                Detalle_Orden.id_activo.is_(None),
            )
            .first()
        )
        assert det_vl is not None
        assert det_vl.estado_preparacion == "Listo"
        assert det_vl.fecha_preparacion is not None
    finally:
        db_chk.close()


# ==============================================================================
# 3. TESTS POKA-YOKE: RECHAZOS Y PROTECCIONES ANTI-ERROR
# ==============================================================================

def test_rechazo_salida_orden_no_pagada(client, db_session, auth_headers_bodeguero):
    """Rechazo: Orden en estado 'Reservada' (no pagada)."""
    token = db_session["token_orden_4"]

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={"qr_transaccional_salida": token, "skus_escaneados": []},
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 400
    assert "no ha sido pagada" in response.json()["detail"].lower()


def test_rechazo_salida_orden_anulada(client, db_session, auth_headers_bodeguero):
    """Rechazo: Orden en estado 'Anulada'."""
    token = db_session["token_orden_5"]

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={"qr_transaccional_salida": token, "skus_escaneados": []},
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 400
    assert "anulada" in response.json()["detail"].lower()


def test_rechazo_salida_orden_ya_completada(client, db_session, auth_headers_bodeguero):
    """Rechazo: Intento de re-entregar una orden que ya está 'Completada'."""
    token = db_session["token_orden_1"]  # Ya completada en el test anterior

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={"qr_transaccional_salida": token, "skus_escaneados": ["MOT-TOY-YAR-888"]},
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 400
    assert "ya fue entregada" in response.json()["detail"].lower()


def test_rechazo_dual_scan_sku_incorrecto(client, db_session, auth_headers_bodeguero):
    """Rechazo Poka-Yoke: Bodeguero escanea un SKU físico ajeno a la orden."""
    token = db_session["token_orden_3"]
    sku_ajeno = "SKU-AJENO-TOTALMENTE-DISTINTO"

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={
            "qr_transaccional_salida": token,
            "skus_escaneados": [sku_ajeno]
        },
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 400
    assert "no pertenecen a esta orden" in response.json()["detail"].lower() or "no pertenece a esta orden" in response.json()["detail"].lower()


def test_rechazo_dual_scan_faltan_skus(client, db_session, auth_headers_bodeguero):
    """Rechazo Poka-Yoke: Orden con 2 repuestos físicos, pero solo se escanea 1."""
    token = db_session["token_orden_3"]
    sku_parcial = "MOT-HYU-ACC-333"  # Falta "CAJ-HYU-ACC-444"

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={
            "qr_transaccional_salida": token,
            "skus_escaneados": [sku_parcial]
        },
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 400
    assert "falta escanear el qr físico" in response.json()["detail"].lower()


def test_escanear_salida_multiples_piezas_exitoso(client, db_session, auth_headers_bodeguero):
    """Salida exitosa con los 2 repuestos físicos requeridos escaneados."""
    token = db_session["token_orden_3"]
    skus_completos = ["MOT-HYU-ACC-333", "CAJ-HYU-ACC-444"]

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={
            "qr_transaccional_salida": token,
            "skus_escaneados": skus_completos
        },
        headers=auth_headers_bodeguero
    )
    assert response.status_code == 200
    data = response.json()
    assert data["estado_orden"] == "Completada"
    assert data["total_entregados"] == 2
    assert set(data["activos_entregados"]) == set(skus_completos)


def test_rechazo_salida_bodeguero_otra_sucursal(client, db_session, auth_headers_bodeguero_suc2):
    """Rechazo: Bodeguero de Sucursal 2 intenta liberar una orden de Sucursal 1."""
    # Crear una orden pagada en sucursal 1
    db = TestingSessionLocal()
    nueva_orden_id = uuid.uuid4()
    token_suc1 = f"TX-QR-{str(nueva_orden_id)[:8].upper()}-SUC1SUC1SUC1"
    try:
        ord_suc1 = Orden_Venta(
            id_orden=nueva_orden_id,
            id_cliente=db_session["cliente_1_id"],
            id_vendedor=db_session["u_bodeguero_id"],
            id_sucursal=1,  # Sucursal 1
            estado_orden="Pagada",
            qr_transaccional_salida=token_suc1,
            total_venta=100000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(ord_suc1)
        db.commit()
    finally:
        db.close()

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={"qr_transaccional_salida": token_suc1, "skus_escaneados": []},
        headers=auth_headers_bodeguero_suc2  # Bodeguero asignado a sucursal 2
    )
    assert response.status_code == 403
    assert "no está autorizado" in response.json()["detail"].lower()


def test_rechazo_salida_qr_no_impreso(client, db_session, auth_headers_bodeguero):
    """
    Verifica que la salida es rechazada si alguna pieza inventariada tiene qr_impreso=False.
    """
    db = TestingSessionLocal()
    try:
        # Activo con qr_impreso=False
        act_sin_qr = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="SIN-QR-999",
            id_categoria=1,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            precio_referencia=100000,
            qr_impreso=False,
            estado="Activo",
        )
        db.add(act_sin_qr)
        db.flush()

        orden_id = uuid.uuid4()
        token = f"TX-QR-{str(orden_id)[:8].upper()}-NOQRTEST"
        orden = Orden_Venta(
            id_orden=orden_id,
            id_cliente=db_session["cliente_1_id"],
            id_vendedor=db_session["u_bodeguero_id"],
            id_cajera=db_session["u_bodeguero_id"],
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=token,
            total_venta=100000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden)
        db.flush()

        det = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_id,
            id_activo=act_sin_qr.id_activo,
            cantidad=1,
            precio_unitario=100000,
            precio_final=100000,
            estado_preparacion="Listo",
        )
        db.add(det)
        db.commit()
    finally:
        db.close()

    response = client.post(
        "/api/v1/bodega/escanear-salida",
        json={"qr_transaccional_salida": token, "skus_escaneados": ["SIN-QR-999"]},
        headers=auth_headers_bodeguero,
    )
    assert response.status_code == 400
    assert "qr" in response.json()["detail"].lower() and "imprima la etiqueta" in response.json()["detail"].lower()


def test_construir_descripcion_repuesto_formato_enriquecido(db_session):
    """
    Verifica que la función construir_descripcion_repuesto genere exactamente
    la estructura: Categoría (Motor o Caja) + Marca + Modelo + Cilindrada + Año.
    Ejemplo: 'Motor Geely Azkarra 1.5 2020'.
    """
    from routers.bodega import construir_descripcion_repuesto

    db = TestingSessionLocal()
    try:
        # 1. Crear vehículo
        veh = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-TEST-GEELY",
            patente="GEEL01",
            marca="Geely",
            modelo="Azkarra",
            anio=2020,
            estado="Activo",
        )
        db.add(veh)
        db.flush()

        # 2. Crear activo Motor
        act_motor = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-GEE-AZK-001",
            id_categoria=1,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            qr_impreso=True,
            estado="Activo",
        )
        db.add(act_motor)
        db.flush()

        # 3. Crear detalle motor con cilindrada 1.5
        det_motor = Detalle_Motor(
            id_activo=act_motor.id_activo,
            cilindrada="1.5",
            combustible="Bencina",
        )
        db.add(det_motor)
        db.flush()

        # 4. Crear activo Caja
        act_caja = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="CAJ-GEE-AZK-001",
            id_categoria=2,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            qr_impreso=True,
            estado="Activo",
        )
        db.add(act_caja)
        db.commit()

        # Validar descripción de Motor
        desc_motor = construir_descripcion_repuesto(db, act_motor)
        assert desc_motor == "Motor Geely Azkarra 1.5 2020", f"Esperado 'Motor Geely Azkarra 1.5 2020', obtenido: '{desc_motor}'"

        # Validar descripción de Caja (hereda cilindrada del motor hermano del mismo vehículo)
        desc_caja = construir_descripcion_repuesto(db, act_caja)
        assert desc_caja == "Caja Geely Azkarra 1.5 2020", f"Esperado 'Caja Geely Azkarra 1.5 2020', obtenido: '{desc_caja}'"

    finally:
        db.close()

