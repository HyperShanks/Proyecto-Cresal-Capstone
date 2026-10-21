import uuid
from datetime import datetime
import pytest
from conftest import TestingSessionLocal
import models
from core.security import create_access_token


@pytest.fixture
def auth_headers():
    db = TestingSessionLocal()
    try:
        # Sembrar Región y Comuna
        reg = db.query(models.Region).filter_by(id_region=1).first()
        if not reg:
            db.add(models.Region(id_region=1, nombre_region="Valparaíso"))
            db.flush()

        com = db.query(models.Comuna).filter_by(id_comuna=1).first()
        if not com:
            db.add(models.Comuna(id_comuna=1, id_region=1, nombre_comuna="Viña del Mar"))
            db.flush()

        # Sembrar Sucursales
        for suc_id, suc_nom in [(1, "Viña del Mar"), (2, "Limache")]:
            s = db.query(models.Sucursal).filter_by(id_sucursal=suc_id).first()
            if not s:
                db.add(models.Sucursal(id_sucursal=suc_id, nombre_sucursal=suc_nom, direccion="Calle Test", id_comuna=1))
                db.flush()

        # Sembrar Roles
        for r_id, r_nom in [(1, "Bodeguero"), (2, "Vendedor")]:
            r = db.query(models.Rol).filter_by(id_rol=r_id).first()
            if not r:
                db.add(models.Rol(id_rol=r_id, nombre_rol=r_nom))
                db.flush()

        # Sembrar Usuario
        user = db.query(models.Usuario).first()
        if not user:
            user = models.Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="11.111.111-1",
                nombres="Vendedor",
                apellidos="Test",
                email="vendedor_entregas@cresal.cl",
                id_rol=2,
                id_sucursal=1,
                password_hash="dummy_hash",
                pin_acceso="1234",
                estado="Activo",
            )
            db.add(user)
            db.flush()

        # Sembrar Estados de Activo necesarios
        for est_id, est_nom in [(1, "Disponible"), (2, "Reservado"), (3, "Vendido"), (5, "En Desarme"), (6, "Entregado")]:
            e = db.query(models.Estado_Activo).filter_by(id_estado=est_id).first()
            if not e:
                db.add(models.Estado_Activo(id_estado=est_id, nombre_estado=est_nom))

        # Sembrar Categorías
        for cat_id, cat_nom in [(1, "Motor"), (2, "Caja de Cambios")]:
            c = db.query(models.Categoria_Activo).filter_by(id_categoria=cat_id).first()
            if not c:
                db.add(models.Categoria_Activo(id_categoria=cat_id, nombre_categoria=cat_nom))

        db.commit()

        token = create_access_token(data={"sub": str(user.id_usuario), "id_rol": user.id_rol, "id_sucursal": 1})
        return {"Authorization": f"Bearer {token}"}
    finally:
        db.close()


def test_crear_orden_con_abono_parcial(client, auth_headers):
    """
    Verifica que al crear una orden con monto_abono parcial, el saldo pendiente
    se calcule correctamente y el estado inicial sea 'Reservada'.
    """
    db = TestingSessionLocal()
    try:
        # Crear activo disponible
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=f"ING-ABO-{uuid.uuid4().hex[:4].upper()}",
            patente=f"AB{uuid.uuid4().hex[:4].upper()}",
            marca="Toyota",
            modelo="Yaris",
            anio=2018,
        )
        db.add(veh)
        db.flush()

        activo = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-ABO-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=1,
            id_estado=1,  # Disponible
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            fecha_creacion=datetime.now(),
        )
        db.add(activo)
        db.commit()

        payload = {
            "cliente": {
                "rut_cliente": f"19.{uuid.uuid4().hex[:3]}.456-7",
                "nombres": "Carlos",
                "apellidos": "Abono",
                "telefono": "+56911223344",
                "comuna": "Viña del Mar",
                "consentimiento_legal": True,
            },
            "requiere_despacho": False,
            "tipo_entrega": "Retiro",
            "consentimiento_legal": True,
            "monto_abono": 200000,
            "items": [
                {
                    "id_activo": str(activo.id_activo),
                    "precio_final": 500000,
                    "cantidad": 1,
                    "notas_preparacion": "Preparar para retiro con abono",
                }
            ],
        }

        res = client.post("/api/v1/ordenes", json=payload, headers=auth_headers)
        assert res.status_code == 201, res.text
        data = res.json()
        assert data["total_venta"] == 500000
        assert data["monto_pendiente"] == 500000
        assert data["abono_requerido"] == 200000
        assert data["estado_orden"] == "Reservada"
    finally:
        db.close()


def test_entregas_envios_endpoint_y_filtros(client, auth_headers):
    """
    Verifica que GET /api/v1/ordenes/entregas-envios liste correctamente órdenes de retiro
    y de despacho según la sucursal activa, permitiendo búsqueda por Folio/RUT/Nombre.
    """
    db = TestingSessionLocal()
    try:
        user = db.query(models.Usuario).first()

        # 1. Cliente para Retiro
        cli_retiro = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="12.345.678-9",
            nombres="Roberto",
            apellidos="Retiro",
            telefono="+56912345678",
            consentimiento_legal=True,
        )
        db.add(cli_retiro)
        db.flush()

        orden_retiro = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli_retiro.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=f"ORD-RET-{uuid.uuid4().hex[:6].upper()}",
            total_venta=150000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_retiro)
        db.flush()

        det_retiro = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_retiro.id_orden,
            descripcion_manual="Filtro de Aceite Misceláneo",
            cantidad=2,
            precio_final=75000,
            estado_preparacion="Listo",
        )
        db.add(det_retiro)

        # 2. Cliente para Despacho
        cli_despacho = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="15.999.888-7",
            nombres="Daniela",
            apellidos="Despacho",
            telefono="+56987654321",
            consentimiento_legal=True,
        )
        db.add(cli_despacho)
        db.flush()

        orden_despacho = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli_despacho.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=f"ORD-DESP-{uuid.uuid4().hex[:6].upper()}",
            total_venta=300000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_despacho)
        db.flush()

        despacho = models.Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=orden_despacho.id_orden,
            id_comuna_destino=1,
            direccion_envio="Av. Libertad 500, Viña del Mar",
            receptor_nombres="Daniela Despacho",
            receptor_rut="15.999.888-7",
            receptor_telefono="+56987654321",
            empresa_transporte="Chilexpress",
            costo_envio=5000,
            estado_despacho="Por Enviar",
        )
        db.add(despacho)

        det_despacho = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_despacho.id_orden,
            descripcion_manual="Kit de Distribución",
            cantidad=1,
            precio_final=300000,
            estado_preparacion="Pendiente",
        )
        db.add(det_despacho)

        db.commit()

        # A. Consulta de todos los pedidos de la sucursal 1
        res_todos = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=auth_headers)
        assert res_todos.status_code == 200, res_todos.text
        data_todos = res_todos.json()
        folios = [item["folio"] for item in data_todos]
        assert orden_retiro.folio in folios
        assert orden_despacho.folio in folios

        # B. Consulta filtrada por tipo 'retiro'
        res_ret = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&tipo=retiro", headers=auth_headers)
        assert res_ret.status_code == 200
        data_ret = res_ret.json()
        assert all(item["tipo_entrega"] == "Retiro" for item in data_ret)
        assert orden_retiro.folio in [item["folio"] for item in data_ret]

        # C. Consulta filtrada por tipo 'despacho'
        res_desp = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&tipo=despacho", headers=auth_headers)
        assert res_desp.status_code == 200
        data_desp = res_desp.json()
        assert all(item["tipo_entrega"] == "Despacho" for item in data_desp)
        assert orden_despacho.folio in [item["folio"] for item in data_desp]

        # D. Búsqueda por RUT
        res_rut = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&busqueda=15.999.888-7", headers=auth_headers)
        assert res_rut.status_code == 200
        data_rut = res_rut.json()
        assert len(data_rut) >= 1
        assert data_rut[0]["cliente"]["rut_cliente"] == "15.999.888-7"
    finally:
        db.close()


def test_confirmar_entrega_tienda_y_marcar_despacho_enviado(client, auth_headers):
    """
    Verifica el cierre de ciclo:
    1. Confirmar entrega en tienda (PATCH /api/v1/ordenes/{id_orden}/entregar) -> estado 'Despachada'.
    2. Marcar despacho como enviado (PATCH /api/v1/despachos/{id_despacho}/enviar) -> estado 'Enviado' y 'Despachada'.
    """
    db = TestingSessionLocal()
    try:
        user = db.query(models.Usuario).first()

        # Activo inventariado vinculado
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=f"ING-ENT-{uuid.uuid4().hex[:4].upper()}",
            patente=f"ET{uuid.uuid4().hex[:4].upper()}",
            marca="Nissan",
            modelo="Qashqai",
            anio=2020,
        )
        db.add(veh)
        db.flush()

        activo_ret = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-ET-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=1,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo="A",
            ubicacion_pallet="1",
            qr_impreso=True,
            fecha_creacion=datetime.now(),
        )
        db.add(activo_ret)
        db.flush()

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente=f"18.{uuid.uuid4().hex[:3]}.111-2",
            nombres="Esteban",
            apellidos="Entrega",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.flush()

        # 1. Orden de Retiro Pagada
        orden_ret = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            total_venta=400000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_ret)
        db.flush()

        det_ret = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_ret.id_orden,
            id_activo=activo_ret.id_activo,
            cantidad=1,
            precio_final=400000,
            estado_preparacion="Listo",
        )
        db.add(det_ret)
        db.commit()

        # Confirmar Entrega de Retiro
        res_ret = client.patch(f"/api/v1/ordenes/{orden_ret.id_orden}/entregar", headers=auth_headers)
        assert res_ret.status_code == 200, res_ret.text
        data_ret = res_ret.json()
        assert data_ret["estado_orden"] == "Completada"
        assert data_ret["activos_finalizados"] == 1

        db.refresh(activo_ret)
        assert activo_ret.id_estado == 6  # Entregado
        assert activo_ret.ubicacion_pasillo is None

        # 2. Orden de Despacho
        orden_desp = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            total_venta=100000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_desp)
        db.flush()

        despacho = models.Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=orden_desp.id_orden,
            id_comuna_destino=1,
            direccion_envio="Calle Los Pinos 123",
            receptor_nombres="Esteban Entrega",
            receptor_rut="18.111.111-2",
            receptor_telefono="+56900000000",
            empresa_transporte="Starken",
            costo_envio=4500,
            estado_despacho="Por Enviar",
        )
        db.add(despacho)
        db.commit()

        # Marcar Despacho como Enviado
        res_desp = client.patch(f"/api/v1/despachos/{despacho.id_despacho}/enviar", headers=auth_headers)
        assert res_desp.status_code == 200, res_desp.text
        data_desp = res_desp.json()
        assert data_desp["estado_despacho"] == "Enviado"
        assert data_desp["estado_orden"] == "Despachada"
    finally:
        db.close()


def test_listar_vendedores_y_filtros_cliente_vendedor_privacidad(client, auth_headers):
    """
    Verifica:
    1. GET /api/v1/ordenes/vendedores lista vendedores activos.
    2. Creación de orden con id_vendedor_asignado.
    3. Filtros por busqueda_cliente, busqueda_vendedor y estado_pago.
    4. Regla de visibilidad/privacidad para ventas asignadas.
    """
    db = TestingSessionLocal()
    try:
        # Crear segundo vendedor en la sucursal 1
        vend2 = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="22.222.222-2",
            nombres="Pedro",
            apellidos="Asignado",
            email="pedro_asig@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy_hash",
            pin_acceso="5678",
            estado="Activo",
        )
        db.add(vend2)
        db.commit()

        # 1. Probar GET /api/v1/ordenes/vendedores
        res_vends = client.get("/api/v1/ordenes/vendedores?sucursal_id=1", headers=auth_headers)
        assert res_vends.status_code == 200, res_vends.text
        vends_data = res_vends.json()
        assert any(v["id_usuario"] == str(vend2.id_usuario) for v in vends_data)

        # 2. Crear Cliente y Orden asignada específicamente a vend2
        cli_privado = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="20.333.444-5",
            nombres="Camila",
            apellidos="Privada",
            telefono="+56933334444",
            consentimiento_legal=True,
        )
        db.add(cli_privado)
        db.flush()

        orden_privada = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli_privado.id_cliente,
            id_vendedor=vend2.id_usuario,
            id_vendedor_asignado=vend2.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            qr_transaccional_salida=f"ORD-PRIV-{uuid.uuid4().hex[:6].upper()}",
            total_venta=250000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_privada)
        db.flush()

        det_priv = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_privada.id_orden,
            descripcion_manual="Radiador de Calefacción",
            cantidad=1,
            precio_final=250000,
            estado_preparacion="Listo",
        )
        db.add(det_priv)
        db.commit()

        # 3. Consultar como vend2 (asignado)
        token_vend2 = create_access_token(data={"sub": str(vend2.id_usuario), "id_rol": 2, "id_sucursal": 1})
        headers_vend2 = {"Authorization": f"Bearer {token_vend2}"}

        res_vend2 = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&busqueda_cliente=Camila", headers=headers_vend2)
        assert res_vend2.status_code == 200
        data_v2 = res_vend2.json()
        assert len(data_v2) >= 1
        assert data_v2[0]["folio"] == orden_privada.folio
        assert data_v2[0]["vendedor_asignado_nombre"] == "Pedro Asignado"

        # 4. Probar filtro por vendedor
        res_fv = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&busqueda_vendedor=Pedro", headers=headers_vend2)
        assert res_fv.status_code == 200
        data_fv = res_fv.json()
        assert any(item["folio"] == orden_privada.folio for item in data_fv)

        # 5. Probar filtro por estado_pago
        res_pagados = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&estado_pago=pagados", headers=headers_vend2)
        assert res_pagados.status_code == 200
        assert all(item["monto_pendiente"] == 0 for item in res_pagados.json())
    finally:
        db.close()


def test_rechazo_entrega_qr_no_impreso(client, auth_headers):
    """
    Verifica que confirmar entrega en tienda falla con 400 si el activo físico no tiene el QR impreso.
    """
    db = TestingSessionLocal()
    try:
        user = db.query(models.Usuario).first()
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=f"ING-NOQR-{uuid.uuid4().hex[:4].upper()}",
            patente=f"NQ{uuid.uuid4().hex[:4].upper()}",
            marca="Toyota",
            modelo="Corolla",
            anio=2021,
        )
        db.add(veh)
        db.flush()

        activo_sin_qr = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-NQ-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=1,
            id_estado=3,  # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            qr_impreso=False,
            fecha_creacion=datetime.now(),
        )
        db.add(activo_sin_qr)
        db.flush()

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente=f"19.{uuid.uuid4().hex[:3]}.999-1",
            nombres="Prueba",
            apellidos="SinQR",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.flush()

        orden = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Pagada",
            total_venta=200000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden)
        db.flush()

        det = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden.id_orden,
            id_activo=activo_sin_qr.id_activo,
            cantidad=1,
            precio_final=200000,
            estado_preparacion="Listo",
        )
        db.add(det)
        db.commit()

        # Intentar confirmar entrega sin QR impreso
        res = client.patch(f"/api/v1/ordenes/{orden.id_orden}/entregar", headers=auth_headers)
        assert res.status_code == 400
        assert "qr" in res.json()["detail"].lower() and "imprima la etiqueta" in res.json()["detail"].lower()
    finally:
        db.close()


def test_actualizar_estado_despacho_independiente_de_orden(client, auth_headers):
    """
    Verifica que PATCH /api/v1/despachos/{id_despacho}/estado actualiza únicamente
    estado_despacho ('Por Enviar' <-> 'Enviado') sin modificar el estado de la orden
    ni marcarla como Completada/Entregada.
    """
    db = TestingSessionLocal()
    try:
        cliente = db.query(models.Cliente).first()
        vendedor = db.query(models.Usuario).filter(models.Usuario.id_rol == 2).first()

        orden = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente.id_cliente,
            id_vendedor=vendedor.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=90000,
            monto_pendiente=90000,
        )
        db.add(orden)
        db.flush()

        despacho = models.Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=orden.id_orden,
            id_comuna_destino=1,
            direccion_envio="Av. Siempre Viva 742",
            receptor_nombres="Homero Simpson",
            receptor_rut="12.345.678-9",
            receptor_telefono="+56911223344",
            empresa_transporte="Chilexpress",
            estado_despacho="Por Enviar",
        )
        db.add(despacho)
        db.commit()

        # 1. Cambiar a "Enviado"
        res1 = client.patch(
            f"/api/v1/despachos/{despacho.id_despacho}/estado",
            json={"nuevo_estado": "Enviado"},
            headers=auth_headers,
        )
        assert res1.status_code == 200, res1.text
        data1 = res1.json()
        assert data1["estado_despacho"] == "Enviado"
        assert data1["estado_orden"] == "Reservada"  # No cambia

        db.refresh(orden)
        assert orden.estado_orden == "Reservada"

        # 2. Conmutar de vuelta a "Por Enviar"
        res2 = client.patch(
            f"/api/v1/despachos/{despacho.id_despacho}/estado",
            json={"nuevo_estado": "Por Enviar"},
            headers=auth_headers,
        )
        assert res2.status_code == 200, res2.text
        data2 = res2.json()
        assert data2["estado_despacho"] == "Por Enviar"
        assert data2["estado_orden"] == "Reservada"

        db.refresh(orden)
        assert orden.estado_orden == "Reservada"
    finally:
        db.close()


def test_ventas_en_verde_no_pagadas_o_sin_qr_no_aparecen_en_entregas_envios(client, auth_headers):
    """
    Verifica que las ventas en verde que no están 100% pagadas o no cuentan con QR
    transaccional (activo no asignado) no se listen en entregas y envíos.
    """
    db = TestingSessionLocal()
    try:
        user = db.query(models.Usuario).first()
        cliente = db.query(models.Cliente).first()

        # 1. Crear Orden de Venta en Verde con saldo pendiente y sin QR
        id_orden_bo = uuid.uuid4()
        orden_bo = models.Orden_Venta(
            id_orden=id_orden_bo,
            id_cliente=cliente.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=500000,
            monto_pendiente=500000,
            qr_transaccional_salida=None,
        )
        db.add(orden_bo)
        db.flush()

        reserva = models.Reservas_Backorder(
            id_reserva=uuid.uuid4(),
            id_cliente=cliente.id_cliente,
            id_vendedor=user.id_usuario,
            id_orden=id_orden_bo,
            id_sucursal_registro=1,
            id_categoria_requerida=1,
            marca_requerida="Nissan",
            modelo_requerido="Qashqai",
            precio_acordado=500000,
            monto_abonado=0,
            abono_requerido=250000,
            id_activo_asignado=None,
            estado_reserva="Pendiente",
        )
        db.add(reserva)

        detalle = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=id_orden_bo,
            descripcion_manual="[RESERVA EN VERDE] Motor - Nissan Qashqai",
            cantidad=1,
            precio_unitario=500000,
            precio_final=500000,
            estado_preparacion="Pendiente",
        )
        db.add(detalle)
        db.commit()

        # Caso A: Con saldo pendiente -> NO debe aparecer
        res_a = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=auth_headers)
        assert res_a.status_code == 200
        folios_a = [item["folio"] for item in res_a.json()]
        assert orden_bo.folio not in folios_a

        # Caso B: Pagada pero sin QR asignado -> NO debe aparecer
        orden_bo.monto_pendiente = 0
        orden_bo.estado_orden = "Pagada"
        db.commit()

        res_b = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=auth_headers)
        assert res_b.status_code == 200
        folios_b = [item["folio"] for item in res_b.json()]
        assert orden_bo.folio not in folios_b

        # Caso C: Pagada y con QR asignado -> SÍ debe aparecer
        orden_bo.qr_transaccional_salida = f"TX-QR-{uuid.uuid4()}"
        db.commit()

        res_c = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=auth_headers)
        assert res_c.status_code == 200
        folios_c = [item["folio"] for item in res_c.json()]
        assert orden_bo.folio in folios_c

    finally:
        db.close()


def test_venta_libre_online_permanece_pagada_hasta_entrega(client, auth_headers):
    """
    Verifica que una venta libre (solo misceláneos) emitida online y asignada a un vendedor:
    1. Al pagarse en caja queda en estado 'Pagada' (NO pasa directo a 'Completada').
    2. Aparece en el listado de Entregas y Envíos para el vendedor asignado con saldo $0.
    3. Al confirmar entrega en tienda ('/{id_orden}/entregar'), pasa a 'Completada' y sale del listado.
    """
    db = TestingSessionLocal()
    try:
        user_cajero = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="22.111.333-4",
            nombres="Cajero",
            apellidos="Test",
            email="cajero_test@cresal.cl",
            id_rol=3,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="8880",
            estado="Activo",
        )
        db.add(user_cajero)

        vend_asignado = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="23.456.789-0",
            nombres="Vendedor",
            apellidos="Responsable",
            email="resp@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="8881",
            estado="Activo",
        )
        db.add(vend_asignado)

        online_seller = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="24.567.890-1",
            nombres="Marcela",
            apellidos="Online",
            email="online@cresal.cl",
            id_rol=7,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="8882",
            estado="Activo",
        )
        db.add(online_seller)

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="25.678.901-2",
            nombres="Cliente",
            apellidos="Online",
            telefono="+56911223344",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.flush()

        # 1. Crear Orden de Venta Libre con id_vendedor_asignado
        orden_libre = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=online_seller.id_usuario,
            id_vendedor_asignado=vend_asignado.id_usuario,
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=35000,
            monto_pendiente=35000,
            abono_requerido=0,
            fecha_creacion=datetime.now(),
        )
        db.add(orden_libre)
        db.flush()

        det_libre = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_libre.id_orden,
            id_activo=None,
            descripcion_manual="Tapa de Radiador y Manguera Superior (Venta Libre)",
            cantidad=1,
            precio_final=35000,
            estado_preparacion="Listo",
        )
        db.add(det_libre)
        db.commit()

        # 2. Pagar la orden en Caja con saldo 0
        token_cajero = create_access_token(data={"sub": str(user_cajero.id_usuario), "id_rol": 4, "id_sucursal": 1})
        headers_caj = {"Authorization": f"Bearer {token_cajero}"}

        pago_payload = {
            "monto": 35000,
            "metodo_pago": "Efectivo",
            "tipo_comprobante": "Boleta",
        }
        res_pago = client.post(f"/api/v1/ordenes/{orden_libre.id_orden}/pagar", json=pago_payload, headers=headers_caj)
        assert res_pago.status_code == 200, res_pago.text
        data_pago = res_pago.json()
        assert data_pago["estado_orden"] == "Pagada", f"Se esperaba Pagada pero fue {data_pago['estado_orden']}"

        # 3. Consultar como Vendedor Asignado en Entregas y Envíos
        token_asig = create_access_token(data={"sub": str(vend_asignado.id_usuario), "id_rol": 2, "id_sucursal": 1})
        headers_asig = {"Authorization": f"Bearer {token_asig}"}

        res_entregas = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=headers_asig)
        assert res_entregas.status_code == 200
        data_entregas = res_entregas.json()
        item_encontrado = next((x for x in data_entregas if x["id_orden"] == str(orden_libre.id_orden)), None)
        assert item_encontrado is not None, "La orden debe ser visible para el vendedor asignado"
        assert item_encontrado["monto_pendiente"] == 0
        assert item_encontrado["preparacion_lista"] is True

        # 4. Confirmar Entrega en Tienda por el vendedor asignado
        res_entrega = client.patch(f"/api/v1/ordenes/{orden_libre.id_orden}/entregar", headers=headers_asig)
        assert res_entrega.status_code == 200, res_entrega.text
        assert res_entrega.json()["estado_orden"] == "Completada"

        # 5. La orden ya no debe aparecer en entregas-envios
        res_post = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=headers_asig)
        assert res_post.status_code == 200
        assert not any(x["id_orden"] == str(orden_libre.id_orden) for x in res_post.json())

    finally:
        db.close()


def test_jefe_ventas_puede_crear_orden_a_nombre_de_online(client):
    """
    Verifica que el Jefe de Ventas (id_rol == 6) pueda crear una orden a nombre de la Vendedora Online (id_rol == 7)
    mediante el checkout wizard:
    - id_vendedor queda fijado a la vendedora online (comisiones/métricas para ella)
    - id_vendedor_asignado queda fijado al Jefe de Ventas (responsable físico de entrega en tienda)
    """
    db = TestingSessionLocal()
    try:
        # 1. Asegurar roles
        for r_id, r_nom in [(6, "Jefe de Ventas"), (7, "Vendedora Online")]:
            if not db.query(models.Rol).filter_by(id_rol=r_id).first():
                db.add(models.Rol(id_rol=r_id, nombre_rol=r_nom))
        db.flush()

        # 2. Jefe de Ventas y Vendedora Online
        jefe = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="12.345.678-9",
            nombres="Gaston",
            apellidos="Jefe",
            email="jefe_test@cresal.cl",
            id_rol=6,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9991",
            estado="Activo",
        )
        db.add(jefe)

        online = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="13.456.789-0",
            nombres="Marcela",
            apellidos="Online",
            email="marcela_test@cresal.cl",
            id_rol=7,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9992",
            estado="Activo",
        )
        db.add(online)

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="14.567.890-1",
            nombres="Cliente",
            apellidos="Referido",
            telefono="+56911223355",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.commit()

        token_jefe = create_access_token(data={"sub": str(jefe.id_usuario), "id_rol": 6, "id_sucursal": 1})
        headers_jefe = {"Authorization": f"Bearer {token_jefe}"}

        # 3. Payload checkout wizard con id_vendedor_titular = online.id_usuario
        payload = {
            "id_cliente": str(cli.id_cliente),
            "tipo_entrega": "Retiro",
            "total_venta": 15000,
            "monto_pendiente": 15000,
            "items_manuales": [
                {
                    "descripcion": "Filtro de Aceite Test",
                    "cantidad": 1,
                    "precio_unitario": 15000,
                }
            ],
            "id_vendedor_titular": str(online.id_usuario),
        }

        res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=headers_jefe)
        assert res.status_code == 201, res.text
        data = res.json()
        id_orden = uuid.UUID(data["id_orden"])

        orden_db = db.query(models.Orden_Venta).filter_by(id_orden=id_orden).first()
        assert orden_db is not None
        assert orden_db.id_vendedor == online.id_usuario, "La orden debe estar atribuida comercialmente a Marcela Online"
        assert orden_db.id_vendedor_asignado == jefe.id_usuario, "El Jefe de Ventas debe quedar como responsable físico de entrega"

        # 4. Verificar aislamiento en /mis-ventas
        token_online = create_access_token(data={"sub": str(online.id_usuario), "id_rol": 7, "id_sucursal": 1})
        headers_online = {"Authorization": f"Bearer {token_online}"}

        # Marcela Online SÍ debe verla en su historial de ventas
        res_mis_ventas_online = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_online)
        assert res_mis_ventas_online.status_code == 200
        ordenes_online_ids = [o["id_orden"] for o in res_mis_ventas_online.json()]
        assert str(id_orden) in ordenes_online_ids, "Marcela Online debe tener la orden en Mis Órdenes"

        # El Jefe de Ventas NO debe verla en su historial de ventas (es de Marcela)
        res_mis_ventas_jefe = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_jefe)
        assert res_mis_ventas_jefe.status_code == 200
        ordenes_jefe_ids = [o["id_orden"] for o in res_mis_ventas_jefe.json()]
        assert str(id_orden) not in ordenes_jefe_ids, "El Jefe de Ventas NO debe ver la venta en sus órdenes personales"

        # El Jefe de Ventas SÍ debe verla en /entregas-envios como responsable físico
        res_entregas_jefe = client.get("/api/v1/ordenes/entregas-envios", headers=headers_jefe)
        assert res_entregas_jefe.status_code == 200
        entregas_ids = [e["id_orden"] for e in res_entregas_jefe.json()]
        assert str(id_orden) in entregas_ids, "El Jefe de Ventas debe ver la orden en Entregas y Envíos"

    finally:
        db.close()


def test_vendedor_mesón_puede_crear_orden_a_nombre_de_otro(client):
    """
    Verifica que un Vendedor de mesón común (id_rol == 2) SÍ pueda atribuir órdenes a otro vendedor,
    recibiendo un HTTP 201 Created y fijando adecuadamente id_vendedor (comercial) e id_vendedor_asignado (físico).
    """
    db = TestingSessionLocal()
    try:
        # Asegurar roles
        for r_id, r_nom in [(2, "Vendedor"), (7, "Vendedora Online")]:
            if not db.query(models.Rol).filter_by(id_rol=r_id).first():
                db.add(models.Rol(id_rol=r_id, nombre_rol=r_nom))
        db.flush()

        vend = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="15.678.901-2",
            nombres="Vendedor",
            apellidos="Comun",
            email="vend_comun@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9993",
            estado="Activo",
        )
        db.add(vend)

        online = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="16.789.012-3",
            nombres="Marcela",
            apellidos="Online2",
            email="marcela2_test@cresal.cl",
            id_rol=7,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9994",
            estado="Activo",
        )
        db.add(online)

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="17.890.123-4",
            nombres="Cliente",
            apellidos="Test2",
            telefono="+56911223366",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.commit()

        token_vend = create_access_token(data={"sub": str(vend.id_usuario), "id_rol": 2, "id_sucursal": 1})
        headers_vend = {"Authorization": f"Bearer {token_vend}"}

        payload = {
            "id_cliente": str(cli.id_cliente),
            "tipo_entrega": "Retiro",
            "total_venta": 5000,
            "monto_pendiente": 5000,
            "items_manuales": [
                {
                    "descripcion": "Ampolleta H4",
                    "cantidad": 1,
                    "precio_unitario": 5000,
                }
            ],
            "id_vendedor_titular": str(online.id_usuario),
        }

        res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=headers_vend)
        assert res.status_code == 201, f"Se esperaba 201 pero fue {res.status_code}: {res.text}"
        data = res.json()
        id_orden = uuid.UUID(data["id_orden"])

        orden_db = db.query(models.Orden_Venta).filter_by(id_orden=id_orden).first()
        assert orden_db is not None
        assert orden_db.id_vendedor == online.id_usuario, "La orden debe quedar comercialmente a nombre de Marcela Online"
        assert orden_db.id_vendedor_asignado == vend.id_usuario, "El Vendedor de mesón debe quedar como responsable físico de entrega"

    finally:
        db.close()


def test_vendedora_online_no_puede_crear_orden_a_nombre_de_otro(client):
    """
    Verifica que la Vendedora Online (id_rol == 7) NO pueda atribuir órdenes a otro vendedor,
    recibiendo un HTTP 403 Forbidden.
    """
    db = TestingSessionLocal()
    try:
        online = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="18.901.234-5",
            nombres="Vendedora",
            apellidos="OnlineBloqueada",
            email="online_bloq@cresal.cl",
            id_rol=7,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9995",
            estado="Activo",
        )
        db.add(online)

        otro_vend = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="19.012.345-6",
            nombres="Otro",
            apellidos="Vendedor",
            email="otro_vend@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9996",
            estado="Activo",
        )
        db.add(otro_vend)

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="20.123.456-7",
            nombres="Cliente",
            apellidos="OnlineTest",
            telefono="+56911223377",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.commit()

        token_online = create_access_token(data={"sub": str(online.id_usuario), "id_rol": 7, "id_sucursal": 1})
        headers_online = {"Authorization": f"Bearer {token_online}"}

        payload = {
            "id_cliente": str(cli.id_cliente),
            "tipo_entrega": "Retiro",
            "total_venta": 5000,
            "monto_pendiente": 5000,
            "items_manuales": [
                {
                    "descripcion": "Filtro de Polen",
                    "cantidad": 1,
                    "precio_unitario": 5000,
                }
            ],
            "id_vendedor_titular": str(otro_vend.id_usuario),
        }

        res = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=headers_online)
        assert res.status_code == 403, f"Se esperaba 403 pero fue {res.status_code}: {res.text}"
        assert "Acceso restringido: Solo el Jefe de Ventas, Vendedor o Administrador" in res.json()["detail"]

    finally:
        db.close()


def test_orden_venta_online_con_responsable_meson_es_visible_para_todos(client):
    """
    Verifica que cuando una orden online se emite con responsable 'Mesón General' (id_vendedor_asignado = None):
    1. La orden se crea exitosamente (201 Created).
    2. En GET /api/v1/ordenes/entregas-envios, es visible para cualquier vendedor de mesón (id_rol == 2)
       de la sucursal, incluso si no es el creador ni un asignado particular.
    3. vendedor_asignado_nombre retorna 'Mesón General (Todos)'.
    """
    db = TestingSessionLocal()
    try:
        # 1. Crear Vendedora Online y dos Vendedores de mesón distintos
        online_user = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="21.111.111-1",
            nombres="Romina",
            apellidos="Online",
            email="romina_online@cresal.cl",
            id_rol=7,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9997",
            estado="Activo",
        )
        db.add(online_user)

        vend_meson_1 = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="22.222.333-4",
            nombres="Claudio",
            apellidos="Mesonero",
            email="claudio_meson@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9998",
            estado="Activo",
        )
        db.add(vend_meson_1)

        vend_meson_2 = models.Usuario(
            id_usuario=uuid.uuid4(),
            rut_usuario="23.333.444-5",
            nombres="Daniel",
            apellidos="MesoneroDos",
            email="daniel_meson@cresal.cl",
            id_rol=2,
            id_sucursal=1,
            password_hash="dummy",
            pin_acceso="9999",
            estado="Activo",
        )
        db.add(vend_meson_2)

        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="24.444.555-6",
            nombres="Cliente",
            apellidos="MesonGeneral",
            telefono="+56911223388",
            consentimiento_legal=True,
        )
        db.add(cli)
        db.commit()

        # 2. Vendedora Online crea orden asignada a Mesón General (id_vendedor_asignado = None)
        token_online = create_access_token(data={"sub": str(online_user.id_usuario), "id_rol": 7, "id_sucursal": 1})
        headers_online = {"Authorization": f"Bearer {token_online}"}

        payload = {
            "id_cliente": str(cli.id_cliente),
            "tipo_entrega": "Retiro",
            "total_venta": 35000,
            "monto_pendiente": 35000,
            "items_manuales": [
                {
                    "descripcion": "Pastillas de Freno Online",
                    "cantidad": 1,
                    "precio_unitario": 35000,
                }
            ],
            "id_vendedor_asignado": None,  # Mesón General
        }

        res_crear = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=headers_online)
        assert res_crear.status_code == 201, res_crear.text
        id_orden = res_crear.json()["id_orden"]

        # 3. Consultar como Vendedor Mesón 1 (no es creador ni asignado específico)
        token_v1 = create_access_token(data={"sub": str(vend_meson_1.id_usuario), "id_rol": 2, "id_sucursal": 1})
        headers_v1 = {"Authorization": f"Bearer {token_v1}"}

        res_entregas_v1 = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=headers_v1)
        assert res_entregas_v1.status_code == 200
        ordenes_v1 = res_entregas_v1.json()
        item_v1 = next((o for o in ordenes_v1 if o["id_orden"] == id_orden), None)
        assert item_v1 is not None, "La orden de Mesón General DEBE ser visible para el Vendedor 1"
        assert item_v1["vendedor_asignado_nombre"] == "Mesón General (Todos)"

        # 4. Consultar como Vendedor Mesón 2
        token_v2 = create_access_token(data={"sub": str(vend_meson_2.id_usuario), "id_rol": 2, "id_sucursal": 1})
        headers_v2 = {"Authorization": f"Bearer {token_v2}"}

        res_entregas_v2 = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1", headers=headers_v2)
        assert res_entregas_v2.status_code == 200
        ordenes_v2 = res_entregas_v2.json()
        item_v2 = next((o for o in ordenes_v2 if o["id_orden"] == id_orden), None)
        assert item_v2 is not None, "La orden de Mesón General DEBE ser visible para el Vendedor 2"
        assert item_v2["vendedor_asignado_nombre"] == "Mesón General (Todos)"

    finally:
        db.close()


def test_entregas_envios_offline_resilience_paginacion_e_idempotencia(client, auth_headers):
    """
    SPEC-HU-RETIRO-ENVIOS:
    Valida:
    1. Carga ligera con limit y offset (paginación progresiva).
    2. Idempotencia en confirmar_entrega_tienda (reintento silencioso devuelve 200).
    3. Idempotencia en marcar_despacho_enviado (reintento silencioso devuelve 200).
    """
    db = TestingSessionLocal()
    try:
        # 1. Crear cliente
        cli = models.Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="22.222.222-2",
            nombres="Cliente",
            apellidos="Resiliente",
            correo="resiliente@cresal.cl",
            telefono="+56911223344",
        )
        db.add(cli)

        # 2. Crear activo con QR impreso
        act1 = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="RESIL-01",
            id_categoria=1,
            id_sucursal_actual=1,
            id_estado=1,
            qr_impreso=True,
        )
        act2 = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="RESIL-02",
            id_categoria=1,
            id_sucursal_actual=1,
            id_estado=1,
            qr_impreso=True,
        )
        db.add_all([act1, act2])
        db.commit()

        # 3. Crear orden de retiro
        user = db.query(models.Usuario).first()
        ord_ret = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            numero_orden=801,
            id_cliente=cli.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            total_venta=50000,
            monto_pendiente=0,
            estado_orden="Pagada",
            qr_transaccional_salida="QR-RESIL-01",
        )
        db.add(ord_ret)
        db.flush()

        det1 = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord_ret.id_orden,
            id_activo=act1.id_activo,
            cantidad=1,
            precio_final=50000,
            estado_preparacion="Listo",
        )
        db.add(det1)

        # 4. Crear orden de despacho
        ord_desp = models.Orden_Venta(
            id_orden=uuid.uuid4(),
            numero_orden=802,
            id_cliente=cli.id_cliente,
            id_vendedor=user.id_usuario,
            id_sucursal=1,
            total_venta=70000,
            monto_pendiente=0,
            estado_orden="Pagada",
            qr_transaccional_salida="QR-RESIL-02",
        )
        db.add(ord_desp)
        db.flush()

        det2 = models.Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord_desp.id_orden,
            id_activo=act2.id_activo,
            cantidad=1,
            precio_final=70000,
            estado_preparacion="Listo",
        )
        db.add(det2)

        desp = models.Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=ord_desp.id_orden,
            id_comuna_destino=1,
            direccion_envio="Av Libertad 123",
            receptor_nombres="Receptor Resiliente",
            receptor_rut="22.222.222-2",
            receptor_telefono="+56911223344",
            empresa_transporte="Chilexpress",
            estado_despacho="Por Enviar",
        )
        db.add(desp)
        db.commit()

        # 5. Probar paginación en listar_entregas_envios
        res_pag1 = client.get("/api/v1/ordenes/entregas-envios?sucursal_id=1&limit=1&offset=0", headers=auth_headers)
        assert res_pag1.status_code == 200
        assert len(res_pag1.json()) == 1

        # 6. Probar entrega y reintento idempotente
        res_entregar_1 = client.patch(f"/api/v1/ordenes/{ord_ret.id_orden}/entregar", headers=auth_headers)
        assert res_entregar_1.status_code == 200
        assert res_entregar_1.json()["estado_orden"] == "Completada"

        # Reintento por desconexión/microcorte
        res_entregar_reintento = client.patch(f"/api/v1/ordenes/{ord_ret.id_orden}/entregar", headers=auth_headers)
        assert res_entregar_reintento.status_code == 200
        assert "ya confirmada previamente" in res_entregar_reintento.json()["mensaje"].lower()

        # 7. Probar despacho y reintento idempotente
        res_desp_1 = client.patch(f"/api/v1/despachos/{desp.id_despacho}/enviar", headers=auth_headers)
        assert res_desp_1.status_code == 200
        assert res_desp_1.json()["estado_despacho"] == "Enviado"

        # Reintento de despacho
        res_desp_reintento = client.patch(f"/api/v1/despachos/{desp.id_despacho}/enviar", headers=auth_headers)
        assert res_desp_reintento.status_code == 200
        assert "ya se encontraba marcado como enviado" in res_desp_reintento.json()["mensaje"].lower()

    finally:
        db.close()





