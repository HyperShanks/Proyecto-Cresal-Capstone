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
    Transaccion_Pago,
)
from core.security import create_access_token, hash_password
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    """
    Inicializa datos de prueba de sucursales, usuarios (Cajera, Admin, Vendedor, Bodeguero),
    clientes, activos, órdenes y reservas para validar el endpoint de registro de cobros (SPEC-HU-03).
    """
    db = TestingSessionLocal()
    try:
        # 1. Geografía y Sucursales
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c1 = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        c2 = Comuna(id_comuna=2, nombre_comuna="Limache", id_region=1)
        db.add_all([c1, c2])

        suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 123", id_comuna=1)
        suc2 = Sucursal(id_sucursal=2, nombre_sucursal="Sucursal Limache", direccion="Calle Comercial 456", id_comuna=2)
        db.add_all([suc1, suc2])

        # 2. Roles
        rol_bodeguero = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        db.add_all([rol_bodeguero, rol_vendedor, rol_caja, rol_admin])

        # 3. Usuarios
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
        user_vendedor = Usuario(
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
        db.add_all([user_caja, user_admin, user_vendedor, user_bodeguero])

        # 4. Cliente
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
            telefono="+56988776655",
            id_comuna=2,
            consentimiento_legal=True,
            estado="Activo",
        )
        db.add_all([cliente1, cliente2])

        # 5. Categoría y Estado Activos
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambio")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        db.add_all([est_disp, est_res, est_vend])

        # 6. Vehículo y Activo
        veh = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-9901",
            patente="MGZS15",
            marca="MG",
            modelo="ZS 1.5",
            anio=2021,
            traccion="4x2",
            estado="Activo",
        )
        db.add(veh)

        activo1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-MG-ZS-15-089",
            id_categoria=1,
            id_estado=2,
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            precio_referencia=550000,
            estado="Activo",
        )
        db.add(activo1)

        # 7. Órdenes de Venta
        # Orden 1: Total 650.000, pendiente 500.000
        orden1 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida=None,
            total_venta=650000,
            monto_pendiente=500000,
            fecha_creacion=datetime(2026, 8, 21, 15, 38),
        )
        # Orden 2: Total 200.000, pendiente 200.000 (para split payment)
        orden2 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida="ORD-SPLIT01",
            total_venta=200000,
            monto_pendiente=200000,
            fecha_creacion=datetime(2026, 8, 21, 16, 0),
        )
        # Orden 3: Total 800.000, pendiente 800.000 (para abono parcial)
        orden3 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida=None,
            total_venta=800000,
            monto_pendiente=800000,
            fecha_creacion=datetime(2026, 8, 21, 16, 30),
        )
        db.add_all([orden1, orden2, orden3])

        # 8. Detalle Orden 1
        det1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=activo1.id_activo,
            descripcion_manual="Motor MG ZS 1.5 Completo",
            cantidad=1,
            precio_unitario=550000,
            precio_final=550000,
            estado_preparacion="Pendiente",
        )
        det2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden1.id_orden,
            id_activo=None,
            descripcion_manual="Kit de Pernos y Sellos",
            cantidad=1,
            precio_unitario=100000,
            precio_final=100000,
            estado_preparacion="Pendiente",
        )
        det_ord2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden2.id_orden,
            id_activo=activo1.id_activo,
            descripcion_manual="Caja de Cambio MG ZS 1.5",
            cantidad=1,
            precio_unitario=200000,
            precio_final=200000,
            estado_preparacion="Pendiente",
        )
        db.add_all([det1, det2, det_ord2])

        # 9. Reserva Backorder
        res1 = Reservas_Backorder(
            id_reserva=uuid.uuid4(),
            id_cliente=cliente2.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Hyundai",
            modelo_requerido="Tucson 2.0 CRDi Turbo Diesel",
            anio_requerido=2022,
            cilindrada_requerida="2.0",
            combustible_requerido="Diesel",
            transmision_requerida="Automática",
            notas_preparacion="En Tránsito Marítimo",
            precio_acordado=1200000,
            monto_abonado=900000,
            estado_reserva="Pendiente",
            fecha_creacion=datetime(2026, 8, 21, 16, 20),
        )
        db.add(res1)

        db.commit()

        yield {
            "caja_user": user_caja,
            "admin_user": user_admin,
            "vendedor_user": user_vendedor,
            "bodeguero_user": user_bodeguero,
            "orden1": orden1,
            "orden2": orden2,
            "orden3": orden3,
            "reserva1": res1,
        }
    finally:
        db.close()


def get_auth_header(user):
    token = create_access_token(data={"sub": str(user.id_usuario)})
    return {"Authorization": f"Bearer {token}"}


# =============================================================================
# PRUEBAS UNITARIAS Y DE INTEGRACIÓN (SPEC-HU-03)
# =============================================================================

def test_registrar_cobro_orden_liquidacion_total_exitoso(client, db_session):
    """
    Registra cobro total (liquidación) de una orden de venta con método Efectivo.
    Verifica:
    - Retorno 200 OK con success=True
    - monto_pendiente pasa a 0
    - estado_orden pasa a 'Pagada'
    - Se genera qr_transaccional_salida
    - Se registra Transaccion_Pago en BD
    """
    user_caja = db_session["caja_user"]
    orden1 = db_session["orden1"]
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden1.id_orden),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 500000,
        "pagos": [
            {"metodo": "Efectivo", "monto": 500000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["monto_cobrado"] == 500000
    assert data["nuevo_saldo_pendiente"] == 0
    assert data["estado_actualizado"] == "Pagada"
    assert len(data["transacciones_ids"]) == 1
    assert data["qr_generado"] is not None
    assert data["qr_generado"].startswith("TX-QR-")

    # Verificar en base de datos
    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == orden1.id_orden).first()
        assert orden_db.monto_pendiente == 0
        assert orden_db.estado_orden == "Pagada"
        assert orden_db.id_cajera == user_caja.id_usuario
        assert orden_db.qr_transaccional_salida == data["qr_generado"]

        pago_db = db.query(Transaccion_Pago).filter(
            Transaccion_Pago.id_pago == uuid.UUID(data["transacciones_ids"][0])
        ).first()
        assert pago_db is not None
        assert pago_db.id_orden == orden1.id_orden
        assert pago_db.id_reserva is None
        assert pago_db.monto == 500000
        assert pago_db.metodo_pago == "Efectivo"
        assert pago_db.estado_pago == "Procesado"
    finally:
        db.close()


def test_registrar_cobro_orden_split_payment_exitoso(client, db_session):
    """
    Registra cobro dividido (split payment) de una orden: Débito ($120.000) + Efectivo ($80.000) = $200.000.
    Verifica creación de múltiples registros en Transaccion_Pago y generación de QR al liquidar.
    """
    user_caja = db_session["caja_user"]
    orden2 = db_session["orden2"]
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden2.id_orden),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 200000,
        "pagos": [
            {"metodo": "Debito", "monto": 120000},
            {"metodo": "Efectivo", "monto": 80000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["monto_cobrado"] == 200000
    assert data["nuevo_saldo_pendiente"] == 0
    assert data["estado_actualizado"] == "Pagada"
    assert len(data["transacciones_ids"]) == 2
    assert data["qr_generado"] is not None
    assert data["qr_generado"].startswith("TX-QR-")

    # Verificar en BD
    db = TestingSessionLocal()
    try:
        pagos_db = db.query(Transaccion_Pago).filter(Transaccion_Pago.id_orden == orden2.id_orden).all()
        assert len(pagos_db) == 2
        metodos = [p.metodo_pago for p in pagos_db]
        montos = [p.monto for p in pagos_db]
        assert "Debito" in metodos
        assert "Efectivo" in metodos
        assert sum(montos) == 200000
    finally:
        db.close()


def test_registrar_cobro_orden_abono_parcial_exitoso(client, db_session):
    """
    Registra un abono parcial sobre una orden de $800.000 pendiente, pagando $300.000 con Transferencia.
    Verifica:
    - estado_orden pasa a 'Reservada' (SPEC-HU-04)
    - nuevo_saldo_pendiente queda en $500.000
    - qr_generado es None
    - id_cajera se actualiza
    """
    user_caja = db_session["caja_user"]
    orden3 = db_session["orden3"]
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "ABONO",
        "monto_declarado": 300000,
        "pagos": [
            {"metodo": "Transferencia", "monto": 300000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["monto_cobrado"] == 300000
    assert data["nuevo_saldo_pendiente"] == 500000
    assert data["estado_actualizado"] == "Reservada"
    assert data["qr_generado"] is None

    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == orden3.id_orden).first()
        assert orden_db.monto_pendiente == 500000
        assert orden_db.estado_orden == "Reservada"
        assert orden_db.id_cajera == user_caja.id_usuario
        assert orden_db.qr_transaccional_salida is None
    finally:
        db.close()


def test_registrar_cobro_backorder_abono_exitoso(client, db_session):
    """
    Registra abono a una reserva backorder (precio 1.200.000, abonado previo 900.000, pendiente 300.000).
    Abona $200.000 con Crédito.
    Verifica:
    - monto_abonado incrementado a $1.100.000
    - estado_reserva = 'Confirmada'
    - nuevo_saldo_pendiente = $100.000
    - qr_generado es None
    - Transaccion_Pago con id_reserva persistido
    """
    user_admin = db_session["admin_user"]
    reserva1 = db_session["reserva1"]
    headers = get_auth_header(user_admin)

    payload = {
        "tipo_operacion": "BACKORDER",
        "id_documento": str(reserva1.id_reserva),
        "modalidad": "ABONO",
        "monto_declarado": 200000,
        "pagos": [
            {"metodo": "Credito", "monto": 200000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["monto_cobrado"] == 200000
    assert data["nuevo_saldo_pendiente"] == 100000
    assert data["estado_actualizado"] == "Confirmada"
    assert data["qr_generado"] is None
    assert data["folio"].startswith("RES-")

    db = TestingSessionLocal()
    try:
        res_db = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_reserva == reserva1.id_reserva).first()
        assert res_db.monto_abonado == 1100000
        assert res_db.estado_reserva == "Confirmada"

        pago_db = db.query(Transaccion_Pago).filter(
            Transaccion_Pago.id_pago == uuid.UUID(data["transacciones_ids"][0])
        ).first()
        assert pago_db.id_reserva == reserva1.id_reserva
        assert pago_db.id_orden is None
        assert pago_db.metodo_pago == "Credito"
        assert pago_db.monto == 200000
    finally:
        db.close()


def test_registrar_cobro_rechazo_descuadre_400(client, db_session):
    """
    Rechaza con 400 si la suma de los métodos de pago no coincide con monto_declarado.
    """
    user_caja = db_session["caja_user"]
    orden3 = db_session["orden3"]
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "ABONO",
        "monto_declarado": 200000,
        "pagos": [
            {"metodo": "Efectivo", "monto": 100000},
            {"metodo": "Debito", "monto": 50000} # Suma = 150.000 != 200.000
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 400
    assert "Descuadre financiero" in response.json()["detail"]


def test_registrar_cobro_rechazo_sobrepago_orden_400(client, db_session):
    """
    Rechaza con 400 si monto_declarado supera el saldo pendiente de la orden.
    """
    user_caja = db_session["caja_user"]
    orden3 = db_session["orden3"] # Saldo actual es $500.000
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 600000, # Supera saldo de 500.000
        "pagos": [
            {"metodo": "Efectivo", "monto": 600000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 400
    assert "Sobrepago rechazado" in response.json()["detail"]


def test_registrar_cobro_rechazo_sobrepago_backorder_400(client, db_session):
    """
    Rechaza con 400 si monto_declarado supera el saldo restante de la reserva backorder.
    """
    user_caja = db_session["caja_user"]
    reserva1 = db_session["reserva1"] # Saldo actual es $100.000
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "BACKORDER",
        "id_documento": str(reserva1.id_reserva),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 150000, # Supera saldo de 100.000
        "pagos": [
            {"metodo": "Efectivo", "monto": 150000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 400
    assert "Sobrepago rechazado" in response.json()["detail"]


def test_registrar_cobro_rechazo_monto_cero_o_negativo_422(client, db_session):
    """
    Rechaza con 422 Unprocessable Entity si algún monto es menor o igual a 0.
    """
    user_caja = db_session["caja_user"]
    orden3 = db_session["orden3"]
    headers = get_auth_header(user_caja)

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "ABONO",
        "monto_declarado": 0,
        "pagos": [
            {"metodo": "Efectivo", "monto": 0}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 422


def test_registrar_cobro_bloqueo_rol_invalido_403(client, db_session):
    """
    Rechaza con 403 Forbidden a usuarios con rol Vendedor (id_rol=2) o Bodeguero (id_rol=1).
    """
    user_vendedor = db_session["vendedor_user"]
    user_bodeguero = db_session["bodeguero_user"]
    orden3 = db_session["orden3"]

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "ABONO",
        "monto_declarado": 50000,
        "pagos": [
            {"metodo": "Efectivo", "monto": 50000}
        ]
    }

    # Probar con Vendedor
    resp_vendedor = client.post(
        "/api/v1/caja/cobros/registrar",
        json=payload,
        headers=get_auth_header(user_vendedor)
    )
    assert resp_vendedor.status_code == 403
    assert "Acceso restringido" in resp_vendedor.json()["detail"]

    # Probar con Bodeguero
    resp_bodeguero = client.post(
        "/api/v1/caja/cobros/registrar",
        json=payload,
        headers=get_auth_header(user_bodeguero)
    )
    assert resp_bodeguero.status_code == 403
    assert "Acceso restringido" in resp_bodeguero.json()["detail"]


def test_registrar_cobro_no_autenticado_401(client, db_session):
    """
    Rechaza con 401 Unauthorized si no se envía header Authorization Bearer.
    """
    orden3 = db_session["orden3"]
    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(orden3.id_orden),
        "modalidad": "ABONO",
        "monto_declarado": 50000,
        "pagos": [
            {"metodo": "Efectivo", "monto": 50000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload)
    assert response.status_code == 401


def test_registrar_cobro_documento_no_encontrado_404(client, db_session):
    """
    Retorna 404 Not Found si el id_documento no existe en la base de datos.
    """
    user_caja = db_session["caja_user"]
    headers = get_auth_header(user_caja)

    uuid_inexistente = str(uuid.uuid4())
    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": uuid_inexistente,
        "modalidad": "LIQUIDACION",
        "monto_declarado": 50000,
        "pagos": [
            {"metodo": "Efectivo", "monto": 50000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 404
    assert "No se encontró" in response.json()["detail"]


def test_registrar_cobro_orden_sin_activos_mantiene_qr_nulo(client, db_session):
    """
    Tarea 1: Verifica que al liquidar una orden de venta cuyos ítems son únicamente
    misceláneos o servicios (todos con id_activo = NULL), la orden pasa automáticamente
    a 'Completada' (cero clics para el vendedor) y el campo qr_transaccional_salida permanece en None.
    """
    user_caja = db_session["caja_user"]
    user_vendedor = db_session["vendedor_user"]
    headers = get_auth_header(user_caja)

    db = TestingSessionLocal()
    try:
        orden_misc = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=db_session["orden1"].id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            qr_transaccional_salida=None,
            total_venta=75000,
            monto_pendiente=75000,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
        )
        db.add(orden_misc)
        db.flush()

        det_misc = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_misc.id_orden,
            id_activo=None,
            descripcion_manual="Servicio de Diagnóstico y Limpieza",
            cantidad=1,
            precio_unitario=75000,
            precio_final=75000,
            estado_preparacion="Listo",
        )
        db.add(det_misc)
        db.commit()
        id_orden_misc = orden_misc.id_orden
    finally:
        db.close()

    payload = {
        "tipo_operacion": "ORDEN",
        "id_documento": str(id_orden_misc),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 75000,
        "pagos": [
            {"metodo": "Transferencia", "monto": 75000}
        ]
    }

    response = client.post("/api/v1/caja/cobros/registrar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["nuevo_saldo_pendiente"] == 0
    assert data["estado_actualizado"] == "Completada"
    assert data["qr_generado"] is None

    # Verificar en BD
    db = TestingSessionLocal()
    try:
        orden_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden_misc).first()
        assert orden_db.estado_orden == "Completada"
        assert orden_db.monto_pendiente == 0
        assert orden_db.qr_transaccional_salida is None
    finally:
        db.close()


def test_flujo_completo_backorder_dos_pagos_abono_y_liquidacion_con_atribucion(client, db_session):
    """
    Verifica el flujo integral de cobro de un Backorder en dos fases:
    1. Primer pago (Abono): No requiere ni exige SKU (el activo físico aún no existe).
       Se registra el abono, reserva pasa a 'Confirmada' y se sincroniza Orden_Venta vinculada.
    2. Segundo pago (Liquidación final): Exige obligatoriamente el SKU del activo físico que ya arribó.
       Saldar la orden marca la reserva 'Completada', el activo como 'Vendido', la Orden_Venta como 'Pagada'
       y emite el código QR transaccional de salida.
    """
    user_caja = db_session["caja_user"]
    headers = get_auth_header(user_caja)

    db = TestingSessionLocal()
    try:
        id_orden = uuid.uuid4()
        id_reserva = uuid.uuid4()
        id_activo = uuid.uuid4()
        cliente = db.query(Cliente).first()

        # Activo que llegará a bodega más adelante
        activo_arribado = Activo_Inventariado(
            id_activo=id_activo,
            sku_qr_fisico="MOT-TEST-9999",
            id_categoria=1,
            id_estado=1, # Disponible
            id_sucursal_actual=1,
            precio_referencia=1000000,
        )
        db.add(activo_arribado)

        orden = Orden_Venta(
            id_orden=id_orden,
            id_cliente=cliente.id_cliente,
            id_vendedor=db_session["vendedor_user"].id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=1000000,
            monto_pendiente=1000000,
            abono_requerido=200000,
        )
        db.add(orden)
        db.flush()

        reserva = Reservas_Backorder(
            id_reserva=id_reserva,
            id_cliente=cliente.id_cliente,
            id_vendedor=db_session["vendedor_user"].id_usuario,
            id_orden=id_orden,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Nissan",
            modelo_requerido="Qashqai",
            anio_requerido=2020,
            precio_acordado=1000000,
            monto_abonado=0,
            abono_requerido=200000,
            estado_reserva="Pendiente",
            fecha_creacion=datetime.now(timezone.utc),
        )
        db.add(reserva)

        detalle = Detalle_Orden(
            id_orden=id_orden,
            id_activo=None,
            descripcion_manual="[RESERVA EN VERDE] Motor Nissan Qashqai",
            cantidad=1,
            precio_unitario=1000000,
            precio_final=1000000,
            estado_preparacion="Pendiente",
        )
        db.add(detalle)
        db.commit()
    finally:
        db.close()

    # ── FASE 1: PRIMER PAGO (ABONO INICIAL) ──────────────────────────────────
    payload_abono = {
        "tipo_operacion": "BACKORDER",
        "id_documento": str(id_reserva),
        "modalidad": "ABONO",
        "monto_declarado": 200000,
        "sku_activo_atribuido": None,  # En el abono inicial NO hay activo físico aún
        "pagos": [
            {"metodo": "Efectivo", "monto": 200000}
        ]
    }

    resp_abono = client.post("/api/v1/caja/cobros/registrar", json=payload_abono, headers=headers)
    assert resp_abono.status_code == 200, f"Error en abono: {resp_abono.text}"
    data_abono = resp_abono.json()
    assert data_abono["success"] is True
    assert data_abono["monto_cobrado"] == 200000
    assert data_abono["nuevo_saldo_pendiente"] == 800000
    assert data_abono["estado_actualizado"] == "Confirmada"
    assert data_abono["qr_generado"] is None  # Sin QR de salida en abono

    # Verificar estado en BD tras Fase 1
    db = TestingSessionLocal()
    try:
        res_db = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_reserva == id_reserva).first()
        assert res_db.monto_abonado == 200000
        assert res_db.estado_reserva == "Confirmada"

        ord_db = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
        assert ord_db.monto_pendiente == 800000
        assert ord_db.estado_orden == "Reservada"
    finally:
        db.close()

    # ── FASE 2: LIQUIDACIÓN COMPLETA SIN SKU FÍSICO (EL ACTIVO AÚN NO LLEGA) ──
    payload_sin_sku = {
        "tipo_operacion": "BACKORDER",
        "id_documento": str(id_reserva),
        "modalidad": "LIQUIDACION",
        "monto_declarado": 800000,
        "sku_activo_atribuido": None,
        "pagos": [
            {"metodo": "Debito", "monto": 800000}
        ]
    }

    resp_sin_sku = client.post("/api/v1/caja/cobros/registrar", json=payload_sin_sku, headers=headers)
    assert resp_sin_sku.status_code == 200, f"Error en liquidación sin SKU: {resp_sin_sku.text}"
    data_sin_sku = resp_sin_sku.json()
    assert data_sin_sku["success"] is True
    assert data_sin_sku["monto_cobrado"] == 800000
    assert data_sin_sku["nuevo_saldo_pendiente"] == 0
    assert data_sin_sku["qr_generado"] is None  # Sin QR hasta que el vendedor asigne el activo

    # Verificar estado en BD: Orden pagada pero sin activo ni QR
    db = TestingSessionLocal()
    try:
        res_db2 = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_reserva == id_reserva).first()
        assert res_db2.monto_abonado == 1000000
        assert res_db2.id_activo_asignado is None

        ord_db2 = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
        assert ord_db2.estado_orden == "Pagada"
        assert ord_db2.monto_pendiente == 0
        assert ord_db2.qr_transaccional_salida is None
    finally:
        db.close()

    # Verificar segregación en Mis Ventas: NO aparece en normal, SÍ aparece en por_asignar
    user_vendedor = db_session["vendedor_user"]
    headers_vendedor = get_auth_header(user_vendedor)

    resp_mis_ventas_normal = client.get("/api/v1/ordenes/mis-ventas?todas=true&seccion=normal", headers=headers_vendedor)
    assert resp_mis_ventas_normal.status_code == 200
    ids_normal = [o["id_orden"] for o in resp_mis_ventas_normal.json()]
    assert str(id_orden) not in ids_normal, "La orden por asignar no debe aparecer en el historial normal"

    resp_mis_ventas_por_asignar = client.get("/api/v1/ordenes/mis-ventas?seccion=por_asignar", headers=headers_vendedor)
    assert resp_mis_ventas_por_asignar.status_code == 200
    ids_por_asignar = [o["id_orden"] for o in resp_mis_ventas_por_asignar.json()]
    assert str(id_orden) in ids_por_asignar, "La orden por asignar debe aparecer en la sección por_asignar"

    # ── FASE 3: LLEGA EL ACTIVO A BODEGA (PALETIZADO) Y EL VENDEDOR LO ASIGNA ──
    # Cambiar estado del activo a Paletizado para verificar que lo acepte
    db = TestingSessionLocal()
    try:
        est_pal = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Paletizado").first()
        if not est_pal:
            est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
            db.add(est_pal)
            db.flush()
        act_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == id_activo).first()
        act_db.id_estado = est_pal.id_estado
        db.commit()
    finally:
        db.close()

    payload_asignacion = {
        "sku_activo": "MOT-TEST-9999",
        "forzar_atribucion": True
    }
    resp_asig = client.post(f"/api/v1/ordenes/{id_orden}/asignar-activo-backorder", json=payload_asignacion, headers=headers_vendedor)
    assert resp_asig.status_code == 200, f"Error al asignar activo: {resp_asig.text}"
    data_asig = resp_asig.json()
    assert data_asig["success"] is True
    assert data_asig["qr_transaccional_salida"] is not None
    assert data_asig["qr_transaccional_salida"].startswith("TX-QR-")

    # Verificar que ahora SÍ aparece en normal con su QR y NO en por_asignar
    resp_mis_ventas_normal2 = client.get("/api/v1/ordenes/mis-ventas?todas=true&seccion=normal", headers=headers_vendedor)
    ids_normal2 = [o["id_orden"] for o in resp_mis_ventas_normal2.json()]
    assert str(id_orden) in ids_normal2, "Tras ser asignada, debe aparecer en el historial normal"

    resp_mis_ventas_por_asignar2 = client.get("/api/v1/ordenes/mis-ventas?seccion=por_asignar", headers=headers_vendedor)
    ids_por_asignar2 = [o["id_orden"] for o in resp_mis_ventas_por_asignar2.json()]
    assert str(id_orden) not in ids_por_asignar2, "Tras ser asignada, ya no debe aparecer en por_asignar"

    # Verificar estado en BD: Activo vendido y orden con QR
    db = TestingSessionLocal()
    try:
        res_db3 = db.query(Reservas_Backorder).filter(Reservas_Backorder.id_reserva == id_reserva).first()
        assert res_db3.id_activo_asignado == id_activo
        assert res_db3.estado_reserva == "Completada"

        ord_db3 = db.query(Orden_Venta).filter(Orden_Venta.id_orden == id_orden).first()
        assert ord_db3.qr_transaccional_salida == data_asig["qr_transaccional_salida"]

        activo_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == id_activo).first()
        assert activo_db.id_estado == 3  # Vendido
    finally:
        db.close()

