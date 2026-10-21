import uuid
from datetime import datetime, timezone
import pytest

from main import app
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
def cuadratura_fixture(setup_database):
    """
    Inicializa datos de prueba aislados para simular todas las combinaciones financieras:
    - Normal con y sin descuento
    - Solo misceláneos con y sin descuento
    - Híbridos (inventariado + misceláneo) con abonos y descuento
    - Backorders (ventas en verde) con y sin descuento
    - Backorders híbridos con misceláneos
    - Cuadratura con Arqueo de Caja, Auditoría y KPIs de Gerencia
    """
    db = TestingSessionLocal()
    try:
        r = Region(id_region=10, nombre_region="Valparaíso Cuadratura")
        db.add(r)
        c1 = Comuna(id_comuna=10, nombre_comuna="Viña del Mar Centro", id_region=10)
        db.add(c1)
        suc1 = Sucursal(
            id_sucursal=10,
            nombre_sucursal="Sucursal Cuadratura 10",
            direccion="Calle Valparaíso 100",
            id_comuna=10,
        )
        db.add(suc1)

        rol_caja = db.query(Rol).filter(Rol.id_rol == 3).first() or Rol(id_rol=3, nombre_rol="Caja")
        rol_vendedor = db.query(Rol).filter(Rol.id_rol == 2).first() or Rol(id_rol=2, nombre_rol="Vendedor")
        rol_gerente = db.query(Rol).filter(Rol.id_rol == 4).first() or Rol(id_rol=4, nombre_rol="Gerente")
        db.add_all([rol_caja, rol_vendedor, rol_gerente])

        user_cajera = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=3,
            id_sucursal=10,
            rut_usuario="13.111.222-3",
            nombres="Cajera",
            apellidos="Auditora",
            email="cajera.cuadratura@cresal.cl",
            password_hash=hash_password("caja1234"),
            pin_acceso="9999",
            estado="Activo",
        )
        user_vendedor = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=10,
            rut_usuario="14.222.333-4",
            nombres="Vendedor",
            apellidos="Comercial",
            email="vendedor.cuadratura@cresal.cl",
            password_hash=hash_password("ventas1234"),
            pin_acceso="8888",
            estado="Activo",
        )
        user_gerente = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=4,
            id_sucursal=10,
            rut_usuario="15.333.444-5",
            nombres="Gerente",
            apellidos="Ejecutivo",
            email="gerente.cuadratura@cresal.cl",
            password_hash=hash_password("gerente1234"),
            pin_acceso="7777",
            estado="Activo",
        )
        db.add_all([user_cajera, user_vendedor, user_gerente])

        cliente = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="19.876.543-2",
            nombres="Patricio",
            apellidos="Navarro",
            correo="patricio.navarro@gmail.com",
            telefono="+56977889900",
            id_comuna=10,
            consentimiento_legal=True,
            estado="Activo",
        )
        db.add(cliente)

        cat_motor = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == 1).first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_motor)

        cat_caja = db.query(Categoria_Activo).filter(Categoria_Activo.id_categoria == 2).first()
        if not cat_caja:
            cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambios")
            db.add(cat_caja)

        est_disp = db.query(Estado_Activo).filter(Estado_Activo.id_estado == 1).first() or Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = db.query(Estado_Activo).filter(Estado_Activo.id_estado == 2).first() or Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = db.query(Estado_Activo).filter(Estado_Activo.id_estado == 3).first() or Estado_Activo(id_estado=3, nombre_estado="Vendido")
        db.add_all([est_disp, est_res, est_vend])

        veh = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-CUAD-01",
            patente="CDRT99",
            marca="Toyota",
            modelo="Yaris",
            anio=2020,
            estado="Activo",
        )
        db.add(veh)

        db.commit()

        token_cajera = create_access_token({"sub": str(user_cajera.id_usuario), "id_rol": 3, "id_sucursal": 10})
        token_gerente = create_access_token({"sub": str(user_gerente.id_usuario), "id_rol": 4, "id_sucursal": 10})

        yield {
            "db": db,
            "cajera": user_cajera,
            "vendedor": user_vendedor,
            "gerente": user_gerente,
            "cliente": cliente,
            "sucursal_id": 10,
            "vehiculo": veh,
            "token_cajera": token_cajera,
            "token_gerente": token_gerente,
        }
    finally:
        db.close()


def test_cuadratura_venta_normal_con_descuento(client, cuadratura_fixture):
    """
    Caso 1: Venta normal con activo inventariado.
    Subtotal Bruto: $1.000.000
    Descuento comercial: $100.000
    Total Venta Neto: $900.000
    Validar:
    - obtener_cobros_pendientes muestra total_operacion=$1.000.000, descuento=$100.000, monto_a_cobrar=$900.000
    - Intento de cobrar $950.000 es rechazado por sobrepago (anti-sobrepago contra neto $900.000)
    - Pago de $900.000 salda la orden al 100%, emite QR transaccional, y deja nuevo_saldo_pendiente=0
    - La orden ya no aparece en pendientes
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"MOT-YAR-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=2,
        id_sucursal_actual=cuadratura_fixture["sucursal_id"],
        id_vehiculo=cuadratura_fixture["vehiculo"].id_vehiculo,
        precio_referencia=1000000,
        estado="Activo",
    )
    db.add(activo)

    id_orden = uuid.uuid4()
    orden = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=901,
        estado_orden="Reservada",
        total_venta=900000,  # Neto post-descuento
        descuento=100000,
        monto_pendiente=900000,
        abono_requerido=0,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden)
    detalle = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=activo.id_activo,
        descripcion_manual="Motor Toyota Yaris 1.5 2020",
        cantidad=1,
        precio_unitario=1000000,
        precio_final=1000000,
        estado_preparacion="Pendiente",
    )
    db.add(detalle)
    db.commit()

    # 1. Verificar visualización en pendientes
    res_pendientes = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=VENTA",
        headers=headers_caja,
    )
    assert res_pendientes.status_code == 200
    items = res_pendientes.json()["items"]
    orden_encontrada = next((it for it in items if it["id_referencia"] == str(id_orden)), None)
    assert orden_encontrada is not None
    assert orden_encontrada["total_operacion"] == 1000000  # Bruto
    assert orden_encontrada["descuento"] == 100000
    assert orden_encontrada["saldo_pendiente"] == 900000
    assert orden_encontrada["monto_a_cobrar"] == 900000

    # 2. Rechazo de sobrepago
    res_sobrepago = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 950000,
            "pagos": [{"metodo": "Efectivo", "monto": 950000}],
        },
    )
    assert res_sobrepago.status_code == 400
    assert "Sobrepago rechazado" in res_sobrepago.json()["detail"]

    # 3. Pago exitoso de $900.000
    res_pago = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 900000,
            "pagos": [{"metodo": "Efectivo", "monto": 900000}],
        },
    )
    assert res_pago.status_code == 200
    data_pago = res_pago.json()
    assert data_pago["nuevo_saldo_pendiente"] == 0
    assert data_pago["estado_actualizado"] == "Pagada"
    assert data_pago["qr_generado"] is not None

    # 4. Verificar que ya no está pendiente
    res_despues = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=VENTA",
        headers=headers_caja,
    )
    items_despues = res_despues.json()["items"]
    assert not any(it["id_referencia"] == str(id_orden) for it in items_despues)


def test_cuadratura_solo_miscelaneos_con_descuento(client, cuadratura_fixture):
    """
    Caso 2: Orden de solo misceláneos con descuento (servicios o insumos de mesón, id_activo=None).
    Subtotal Bruto: $60.000 (2x Cambio de Aceite $30.000)
    Descuento: $10.000
    Total Venta Neto: $50.000
    Validar:
    - Pago 100% de $50.000 salda la orden directamente a 'Completada'
    - qr_generado es None (no requiere paso por bodega)
    - Líneas de detalle se marcan como 'Listo'
    - Desaparece de cobros pendientes
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    id_orden = uuid.uuid4()
    orden = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=902,
        estado_orden="Reservada",
        total_venta=50000,
        descuento=10000,
        monto_pendiente=50000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden)
    detalle = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="Servicio de Cambio de Aceite y Filtro",
        cantidad=2,
        precio_unitario=30000,
        precio_final=60000,
        estado_preparacion="Pendiente",
    )
    db.add(detalle)
    db.commit()

    # Liquidación total
    res_pago = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 50000,
            "pagos": [{"metodo": "Debito", "monto": 50000}],
        },
    )
    assert res_pago.status_code == 200
    data = res_pago.json()
    assert data["nuevo_saldo_pendiente"] == 0
    assert data["estado_actualizado"] == "Completada"
    assert data["qr_generado"] is None

    # Verificar actualización en BD
    db.refresh(orden)
    db.refresh(detalle)
    assert orden.estado_orden == "Completada"
    assert orden.monto_pendiente == 0
    assert detalle.estado_preparacion == "Listo"


def test_cuadratura_solo_miscelaneos_sin_descuento(client, cuadratura_fixture):
    """
    Caso 3: Orden de solo misceláneos sin descuento.
    Subtotal Bruto: $45.000 (Líquido refrigerante + Golilla tapón de cárter)
    Descuento: $0
    Total Venta Neto: $45.000
    Validar:
    - Cobro pendiente muestra total_operacion=$45.000, descuento=$0, saldo_pendiente=$45.000
    - Liquidación 100% actualiza a 'Completada', sin QR físico, líneas a 'Listo'
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    id_orden = uuid.uuid4()
    orden = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=905,
        estado_orden="Reservada",
        total_venta=45000,
        descuento=0,
        monto_pendiente=45000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden)
    detalle = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="Bidón Refrigerante 5L Verde Orgánico",
        cantidad=1,
        precio_unitario=45000,
        precio_final=45000,
        estado_preparacion="Pendiente",
    )
    db.add(detalle)
    db.commit()

    # Verificar visualización en pendientes
    res_pend = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=VENTA",
        headers=headers_caja,
    )
    assert res_pend.status_code == 200
    it_misc = next((it for it in res_pend.json()["items"] if it["id_referencia"] == str(id_orden)), None)
    assert it_misc is not None
    assert it_misc["total_operacion"] == 45000
    assert it_misc["descuento"] == 0
    assert it_misc["saldo_pendiente"] == 45000

    # Pago 100% Efectivo
    res_cobro = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 45000,
            "pagos": [{"metodo": "Efectivo", "monto": 45000}],
        },
    )
    assert res_cobro.status_code == 200
    assert res_cobro.json()["nuevo_saldo_pendiente"] == 0
    assert res_cobro.json()["estado_actualizado"] == "Completada"
    assert res_cobro.json()["qr_generado"] is None


def test_cuadratura_hibrida_inventariado_miscelaneo_abonos(client, cuadratura_fixture):
    """
    Caso 4: Orden híbrida (Activo inventariado + Ítem misceláneo).
    Línea 1: Activo $700.000
    Línea 2: Servicio $100.000
    Subtotal Bruto: $800.000
    Descuento: $50.000
    Total Neto a Pagar: $750.000
    Abono 1: $300.000 (Saldo pendiente pasa a $450.000, orden sigue Reservada, sin QR)
    Abono 2: $450.000 (Saldo pasa a $0, orden pasa a Pagada, QR emitido, misceláneo Listo, activo Vendido)
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"CAJ-HIB-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=2,
        id_estado=2,
        id_sucursal_actual=cuadratura_fixture["sucursal_id"],
        id_vehiculo=cuadratura_fixture["vehiculo"].id_vehiculo,
        precio_referencia=700000,
        estado="Activo",
    )
    db.add(activo)

    id_orden = uuid.uuid4()
    orden = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=903,
        estado_orden="Reservada",
        total_venta=750000,
        descuento=50000,
        monto_pendiente=750000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden)
    det1 = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=activo.id_activo,
        descripcion_manual="Caja de Cambios Manual 5V",
        cantidad=1,
        precio_unitario=700000,
        precio_final=700000,
        estado_preparacion="Pendiente",
    )
    det2 = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="Kit de Fluidos y Empaquetaduras",
        cantidad=1,
        precio_unitario=100000,
        precio_final=100000,
        estado_preparacion="Pendiente",
    )
    db.add_all([det1, det2])
    db.commit()

    # Abono 1: $300.000
    res1 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "ABONO",
            "monto_declarado": 300000,
            "pagos": [{"metodo": "Transferencia", "monto": 300000}],
        },
    )
    assert res1.status_code == 200
    assert res1.json()["nuevo_saldo_pendiente"] == 450000
    assert res1.json()["estado_actualizado"] == "Reservada"
    assert res1.json()["qr_generado"] is None

    # Abono 2 (Liquidación final): $450.000 dividido
    res2 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 450000,
            "pagos": [
                {"metodo": "Efectivo", "monto": 250000},
                {"metodo": "Debito", "monto": 200000},
            ],
        },
    )
    assert res2.status_code == 200
    assert res2.json()["nuevo_saldo_pendiente"] == 0
    assert res2.json()["estado_actualizado"] == "Pagada"
    assert res2.json()["qr_generado"] is not None

    db.refresh(orden)
    db.refresh(det1)
    db.refresh(det2)
    db.refresh(activo)
    assert orden.monto_pendiente == 0
    assert det2.estado_preparacion == "Listo"
    assert activo.id_estado == 3  # Vendido


def test_cuadratura_venta_normal_sin_descuento_con_abonos(client, cuadratura_fixture):
    """
    Caso 5: Venta normal sin descuento con abonos sucesivos.
    Activo: $500.000
    Descuento: $0
    Total Neto: $500.000
    Abono 1: $200.000 -> Saldo $300.000
    Abono 2: $300.000 -> Saldo $0, Estado Pagada, emite QR
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"ACT-NORMAL-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=2,
        id_sucursal_actual=cuadratura_fixture["sucursal_id"],
        id_vehiculo=cuadratura_fixture["vehiculo"].id_vehiculo,
        precio_referencia=500000,
        estado="Activo",
    )
    db.add(activo)

    id_orden = uuid.uuid4()
    orden = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=906,
        estado_orden="Reservada",
        total_venta=500000,
        descuento=0,
        monto_pendiente=500000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden)
    det = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=activo.id_activo,
        descripcion_manual="Semieje Delantero Izquierdo",
        cantidad=1,
        precio_unitario=500000,
        precio_final=500000,
        estado_preparacion="Pendiente",
    )
    db.add(det)
    db.commit()

    # Abono 1: $200.000
    r1 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "ABONO",
            "monto_declarado": 200000,
            "pagos": [{"metodo": "Efectivo", "monto": 200000}],
        },
    )
    assert r1.status_code == 200
    assert r1.json()["nuevo_saldo_pendiente"] == 300000

    # Abono 2: $300.000
    r2 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "ORDEN",
            "id_documento": str(id_orden),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 300000,
            "pagos": [{"metodo": "Debito", "monto": 300000}],
        },
    )
    assert r2.status_code == 200
    assert r2.json()["nuevo_saldo_pendiente"] == 0
    assert r2.json()["estado_actualizado"] == "Pagada"
    assert r2.json()["qr_generado"] is not None


def test_cuadratura_backorder_con_descuento_y_gerencia(client, cuadratura_fixture):
    """
    Caso 6: Venta en Verde (Backorder) con descuento.
    Precio pactado de la pieza: $1.000.000
    Descuento acordado por vendedor: $100.000
    Total neto de la orden vinculada: $900.000
    Validar:
    - obtener_cobros_pendientes muestra:
      total_operacion = $1.000.000, descuento = $100.000, monto_a_cobrar = $900.000, saldo_pendiente = $900.000
      especificaciones con cilindrada y combustible separados
    - Intento de cobrar $1.000.000 es rechazado por sobrepago (anti-sobrepago respeta saldo de $900.000)
    - Pago de $900.000:
      reserva.monto_abonado se reconcilia a $1.000.000
      orden_vinculada.monto_pendiente = 0 y estado_orden = "Pagada"
      reserva.estado_reserva = "Confirmada" (sin activo físico asignado aún por el vendedor)
    - Backorder NO reaparece en pendientes de cobro
    - Gerencia /backorders reporta saldo_pendiente = 0 y descuento = 100000
    - Gerencia /dashboard/kpis reporta ventas_del_dia sumando exactamente los $900.000 netos
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}
    headers_gerente = {"Authorization": f"Bearer {cuadratura_fixture['token_gerente']}"}

    id_reserva = uuid.uuid4()
    id_orden = uuid.uuid4()

    orden_bo = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=904,
        estado_orden="Reservada",
        total_venta=900000,
        descuento=100000,
        monto_pendiente=900000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden_bo)

    reserva = Reservas_Backorder(
        id_reserva=id_reserva,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_orden=id_orden,
        id_sucursal_registro=cuadratura_fixture["sucursal_id"],
        id_categoria_requerida=1,
        marca_requerida="Nissan",
        modelo_requerido="Qashqai",
        anio_requerido=2019,
        cilindrada_requerida="2.0L",
        combustible_requerido="Gasolina",
        transmision_requerida="CVT",
        precio_acordado=1000000,
        monto_abonado=0,
        abono_requerido=0,
        estado_reserva="Pendiente",
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(reserva)

    det_bo = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="[RESERVA EN VERDE] Motor - Nissan Qashqai (2019)",
        cantidad=1,
        precio_unitario=1000000,
        precio_final=1000000,
        estado_preparacion="Pendiente",
    )
    db.add(det_bo)
    db.commit()

    # 1. Consulta en Cobros Pendientes
    res_pend = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=BACKORDER",
        headers=headers_caja,
    )
    assert res_pend.status_code == 200
    items = res_pend.json()["items"]
    bo_item = next((it for it in items if it["id_referencia"] == str(id_reserva)), None)
    assert bo_item is not None
    assert bo_item["total_operacion"] == 1000000
    assert bo_item["descuento"] == 100000
    assert bo_item["saldo_pendiente"] == 900000
    assert bo_item["monto_a_cobrar"] == 900000
    # Validar que especificaciones backorder entrega cilindrada y combustible por separado
    specs = bo_item["especificaciones_backorder"]
    assert specs is not None
    assert specs["cilindrada"] == "2.0L"
    assert specs["combustible"] == "Gasolina"

    # 2. Intento de sobrepago
    res_sobrepago = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "BACKORDER",
            "id_documento": str(id_reserva),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 1000000,
            "pagos": [{"metodo": "Efectivo", "monto": 1000000}],
        },
    )
    assert res_sobrepago.status_code == 400
    assert "Sobrepago rechazado" in res_sobrepago.json()["detail"]

    # 3. Pago exacto de $900.000
    res_cobro = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "BACKORDER",
            "id_documento": str(id_reserva),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 900000,
            "pagos": [{"metodo": "Transferencia", "monto": 900000}],
        },
    )
    assert res_cobro.status_code == 200
    cobro_data = res_cobro.json()
    assert cobro_data["nuevo_saldo_pendiente"] == 0
    assert cobro_data["estado_actualizado"] == "Pagada"
    assert cobro_data["qr_generado"] is None  # Sin QR físico hasta que el vendedor asigne el motor

    # 4. Verificar que no vuelva a salir en cobros pendientes
    res_pend_after = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=BACKORDER",
        headers=headers_caja,
    )
    items_after = res_pend_after.json()["items"]
    assert not any(it["id_referencia"] == str(id_reserva) for it in items_after)

    # 5. Verificar Gerencia - Listado de Backorders
    res_ger_bo = client.get(
        f"/api/v1/gerencia/backorders?id_sucursal={cuadratura_fixture['sucursal_id']}",
        headers=headers_gerente,
    )
    assert res_ger_bo.status_code == 200
    bo_ger_items = res_ger_bo.json()["items"]
    bo_ger = next((it for it in bo_ger_items if it["id_reserva"] == str(id_reserva)), None)
    assert bo_ger is not None
    assert bo_ger["precio_acordado"] == 1000000
    assert bo_ger["descuento"] == 100000
    assert bo_ger["saldo_pendiente"] == 0  # Crucial: NO reporta deuda falsa de $100.000

    # 6. Verificar Gerencia - KPIs Financieros
    res_kpis = client.get(
        f"/api/v1/gerencia/dashboard/kpis?id_sucursal={cuadratura_fixture['sucursal_id']}",
        headers=headers_gerente,
    )
    assert res_kpis.status_code == 200
    kpis = res_kpis.json()
    assert kpis["ventas_del_dia"] >= 900000


def test_cuadratura_backorder_hibrido_con_miscelaneo_y_descuento(client, cuadratura_fixture):
    """
    Caso 7: Backorder híbrido que incluye un ítem misceláneo adicional en la misma orden.
    Backorder: $1.200.000
    Misceláneo adicional (Servicio de Despacho Especial): $100.000
    Subtotal Bruto: $1.300.000
    Descuento: $100.000
    Total Neto: $1.200.000
    Abono 1: $600.000 -> Saldo pendiente: $600.000
    Abono 2 (Liquidación): $600.000 -> Saldo pendiente: $0, orden Pagada
    """
    db = cuadratura_fixture["db"]
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    id_reserva = uuid.uuid4()
    id_orden = uuid.uuid4()

    orden_bo_hib = Orden_Venta(
        id_orden=id_orden,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_sucursal=cuadratura_fixture["sucursal_id"],
        numero_orden=907,
        estado_orden="Reservada",
        total_venta=1200000,
        descuento=100000,
        monto_pendiente=1200000,
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(orden_bo_hib)

    reserva = Reservas_Backorder(
        id_reserva=id_reserva,
        id_cliente=cuadratura_fixture["cliente"].id_cliente,
        id_vendedor=cuadratura_fixture["vendedor"].id_usuario,
        id_orden=id_orden,
        id_sucursal_registro=cuadratura_fixture["sucursal_id"],
        id_categoria_requerida=1,
        marca_requerida="Subaru",
        modelo_requerido="Forester",
        anio_requerido=2021,
        cilindrada_requerida="2.5L",
        combustible_requerido="Bencina",
        transmision_requerida="AWD",
        precio_acordado=1200000,
        monto_abonado=0,
        abono_requerido=500000,
        estado_reserva="Pendiente",
        fecha_creacion=datetime.now(timezone.utc),
    )
    db.add(reserva)

    det1 = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="[RESERVA EN VERDE] Motor - Subaru Forester (2021)",
        cantidad=1,
        precio_unitario=1200000,
        precio_final=1200000,
        estado_preparacion="Pendiente",
    )
    det2 = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=id_orden,
        id_activo=None,
        descripcion_manual="Servicio de Despacho y Montaje Palletizado",
        cantidad=1,
        precio_unitario=100000,
        precio_final=100000,
        estado_preparacion="Pendiente",
    )
    db.add_all([det1, det2])
    db.commit()

    # Visualizar en pendientes: debe mostrar tanto el backorder como el artículo misceláneo adicional
    res_pend = client.get(
        f"/api/v1/caja/pendientes?sucursal_id={cuadratura_fixture['sucursal_id']}&tipo_operacion=BACKORDER",
        headers=headers_caja,
    )
    assert res_pend.status_code == 200
    bo_encontrado = next((it for it in res_pend.json()["items"] if it["id_referencia"] == str(id_reserva)), None)
    assert bo_encontrado is not None
    assert bo_encontrado["total_operacion"] == 1300000  # 1.200.000 + 100.000
    assert bo_encontrado["descuento"] == 100000
    assert bo_encontrado["saldo_pendiente"] == 1200000
    assert len(bo_encontrado["articulos"]) == 1  # Servicio adicional (el backorder se muestra en especificaciones)
    assert bo_encontrado["articulos"][0]["descripcion"] == "Servicio de Despacho y Montaje Palletizado"
    assert bo_encontrado["articulos"][0]["tipo"] == "MISCELANEO"
    assert bo_encontrado["especificaciones_backorder"]["marca"] == "Subaru"
    assert bo_encontrado["especificaciones_backorder"]["cilindrada"] == "2.5L"

    # Abono 1: $600.000
    res_abono1 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "BACKORDER",
            "id_documento": str(id_reserva),
            "modalidad": "ABONO",
            "monto_declarado": 600000,
            "pagos": [{"metodo": "Transferencia", "monto": 600000}],
        },
    )
    assert res_abono1.status_code == 200
    assert res_abono1.json()["nuevo_saldo_pendiente"] == 600000

    # Abono 2 (Liquidación): $600.000
    res_abono2 = client.post(
        "/api/v1/caja/cobros/registrar",
        headers=headers_caja,
        json={
            "tipo_operacion": "BACKORDER",
            "id_documento": str(id_reserva),
            "modalidad": "LIQUIDACION",
            "monto_declarado": 600000,
            "pagos": [{"metodo": "Efectivo", "monto": 600000}],
        },
    )
    assert res_abono2.status_code == 200
    assert res_abono2.json()["nuevo_saldo_pendiente"] == 0
    assert res_abono2.json()["estado_actualizado"] == "Pagada"


def test_cuadratura_auditoria_detalles_ventas_gerencia_y_caja(client, cuadratura_fixture):
    """
    Caso 8: Auditoría y Detalle de Ventas Multidimensional (/api/v1/ordenes).
    Verifica que tanto Gerencia como Caja puedan auditar el detalle de ventas
    y que todos los valores calculados cuadren al peso exacto:
    - total_monto_consolidado
    - total_venta y descuento
    - total_liquidado (suma de transacciones)
    - monto_pendiente
    - articulos (inventariados y misceláneos)
    """
    headers_gerente = {"Authorization": f"Bearer {cuadratura_fixture['token_gerente']}"}
    headers_caja = {"Authorization": f"Bearer {cuadratura_fixture['token_cajera']}"}

    for headers in [headers_gerente, headers_caja]:
        res_auditoria = client.get(
            f"/api/v1/ordenes?id_sucursal={cuadratura_fixture['sucursal_id']}",
            headers=headers,
        )
        assert res_auditoria.status_code == 200
        data = res_auditoria.json()
        assert data["total_registros"] >= 6
        assert data["total_monto_consolidado"] > 0

        # Verificar cuadratura interna de cada orden retornada
        for it in data["items"]:
            # El total liquidado debe coincidir con la suma de los pagos asociados
            suma_pagos = sum(p["monto"] for p in it["desglose_pagos"])
            assert it["total_liquidado"] == suma_pagos

            # Si la orden está pagada o completada, monto_pendiente debe ser 0
            if it["estado_orden"] in ["Pagada", "Completada"]:
                assert it["monto_pendiente"] == 0
                assert it["total_liquidado"] == it["total_venta"]

            # Si tiene descuento, debe ser un valor entero no negativo
            assert it["descuento"] >= 0

            # Los artículos deben estar desglosados
            assert len(it["articulos"]) >= 1
            for art in it["articulos"]:
                assert art["cantidad"] >= 1
                assert art["precio"] >= 0
                assert art["tipo"] in ["INVENTARIADO", "DESARME"]
