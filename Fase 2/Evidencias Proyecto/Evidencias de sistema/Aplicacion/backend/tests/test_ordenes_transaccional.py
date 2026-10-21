# test_ordenes_transaccional.py
# Suite de pruebas automatizadas para el Motor Transaccional de Órdenes (HU-3.4)

import uuid
import pytest
from datetime import datetime, timezone, timedelta
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
    db = TestingSessionLocal()
    try:
        # 1. Región y Comunas
        reg = db.query(Region).filter_by(id_region=1).first()
        if not reg:
            reg = Region(id_region=1, nombre_region="Valparaíso")
            db.add(reg)
            db.flush()

        com1 = db.query(Comuna).filter_by(id_comuna=1).first()
        if not com1:
            com1 = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(com1)
            db.flush()

        # 2. Sucursal
        suc = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc:
            suc = Sucursal(
                id_sucursal=1,
                nombre_sucursal="Casa Matriz - Viña",
                direccion="Camino Internacional 4105",
                id_comuna=1
            )
            db.add(suc)
            db.flush()

        # 3. Rol y Usuario Vendedor
        rol_vendedor = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_vendedor:
            rol_vendedor = Rol(id_rol=1, nombre_rol="Vendedor")
            db.add(rol_vendedor)
            db.flush()

        user_vendedor = db.query(Usuario).filter_by(rut_usuario="33.333.333-3").first()
        if not user_vendedor:
            u_id = uuid.uuid4()
            user_vendedor = Usuario(
                id_usuario=u_id,
                id_rol=1,
                id_sucursal=1,
                rut_usuario="33.333.333-3",
                nombres="Carlos",
                apellidos="Ventas",
                email="carlos.ventas.ordenes@cresal.cl",
                password_hash="hash",
                pin_acceso="9876",
                estado="Activo"
            )
            db.add(user_vendedor)
            db.flush()

        # 4. Categorías y Estados de Activo
        cat_motor = db.query(Categoria_Activo).filter_by(nombre_categoria="Motor").first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_motor)

        est_disp = db.query(Estado_Activo).filter_by(nombre_estado="Disponible").first()
        if not est_disp:
            est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
            db.add(est_disp)

        est_res = db.query(Estado_Activo).filter_by(nombre_estado="Reservado").first()
        if not est_res:
            est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
            db.add(est_res)

        est_vend = db.query(Estado_Activo).filter_by(nombre_estado="Vendido").first()
        if not est_vend:
            est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
            db.add(est_vend)

        db.commit()

        # 5. Vehículo y Activos de Prueba
        veh = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2024-01",
            patente="ABCD12",
            marca="Toyota",
            modelo="Yaris",
            anio=2019,
            traccion="4x2"
        )
        db.add(veh)
        db.flush()

        # Activo 1: Disponible para venta
        id_activo_1 = uuid.uuid4()
        activo_1 = Activo_Inventariado(
            id_activo=id_activo_1,
            sku_qr_fisico="MOT-TOY-YAR-001",
            id_categoria=1,
            id_estado=1, # Disponible
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-02",
            ubicacion_pallet="PL-14",
            precio_referencia=520000,
            estado="Activo",
            qr_impreso=True
        )

        # Activo 2: Ya vendido (No disponible)
        id_activo_2 = uuid.uuid4()
        activo_2 = Activo_Inventariado(
            id_activo=id_activo_2,
            sku_qr_fisico="MOT-TOY-YAR-002",
            id_categoria=1,
            id_estado=3, # Vendido
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            ubicacion_pasillo="P-02",
            ubicacion_pallet="PL-15",
            precio_referencia=500000,
            estado="Activo",
            qr_impreso=True
        )

        db.add_all([activo_1, activo_2])
        db.commit()

        yield {
            "vendedor": user_vendedor,
            "activo_disponible": activo_1,
            "activo_vendido": activo_2,
        }
    finally:
        db.close()


@pytest.fixture
def auth_headers(db_session):
    user = db_session["vendedor"]
    token = create_access_token(
        data={"sub": str(user.id_usuario)},
        expires_delta=timedelta(hours=1)
    )
    return {"Authorization": f"Bearer {token}"}


# ── TEST 1: Camino Feliz Híbrido (Inventariado + Venta Libre + Despacho) ─────
def test_crear_orden_camino_feliz_hibrido(client, db_session, auth_headers):
    activo_disp = db_session["activo_disponible"]

    payload = {
        "cliente": {
            "rut_cliente": "18.765.432-1",
            "nombres": "Juan",
            "apellidos": "Pérez González",
            "telefono": "+56912345678",
            "correo": "juan.perez@gmail.com",
            "comuna": "Viña del Mar",
            "consentimiento_legal": True
        },
        "requiere_despacho": True,
        "despacho": {
            "direccion_envio": "Av. Libertad 1234, Depto 402",
            "comuna_destino": "Viña del Mar",
            "receptor_rut": "18.765.432-1",
            "receptor_nombres": "Juan Pérez",
            "receptor_telefono": "+56912345678",
            "empresa_transporte": "Cresal Express",
            "costo_envio": 5000
        },
        "consentimiento_legal": True,
        "instrucciones_bodega": "Embalar con film protector",
        "items": [
            {
                "id_activo": str(activo_disp.id_activo),
                "notas_preparacion": "Entregar con poleas instaladas",
                "cantidad": 1,
                "precio_unitario": 520000,
                "precio_final": 520000
            },
            {
                "descripcion_manual": "Pernos Culata Reforzados",
                "notas_preparacion": "Verificar hilo métrico",
                "cantidad": 2,
                "precio_unitario": 15000,
                "precio_final": 15000
            }
        ]
    }

    # 1. Ejecutar POST /api/v1/ordenes
    response = client.post("/api/v1/ordenes", json=payload, headers=auth_headers)
    assert response.status_code == 201

    data = response.json()
    assert "id_orden" in data
    assert data["estado_orden"] == "Reservada"
    assert data["total_venta"] == 550000  # 520.000 + (15.000 * 2)
    assert data["monto_pendiente"] == 550000
    assert data["total_items"] == 2
    assert data["qr_transaccional_salida"] is None

    id_orden = data["id_orden"]

    # 2. Verificar consistencia ACID en la base de datos
    db = TestingSessionLocal()
    try:
        # Cabecera
        orden_db = db.query(Orden_Venta).filter_by(id_orden=uuid.UUID(id_orden)).first()
        assert orden_db is not None
        assert orden_db.total_venta == 550000
        assert orden_db.estado_orden == "Reservada"
        assert orden_db.qr_transaccional_salida is None
        assert db.query(Transaccion_Pago).filter_by(id_orden=orden_db.id_orden).count() == 0

        # Cliente
        cliente_db = db.query(Cliente).filter_by(id_cliente=orden_db.id_cliente).first()
        assert cliente_db is not None
        assert cliente_db.rut_cliente == "18.765.432-1"
        assert cliente_db.nombres == "Juan"

        # Despacho
        despacho_db = db.query(Despacho).filter_by(id_orden=orden_db.id_orden).first()
        assert despacho_db is not None
        assert despacho_db.direccion_envio == "Av. Libertad 1234, Depto 402"
        assert despacho_db.receptor_nombres == "Juan Pérez"

        # Detalle de Líneas
        detalles = db.query(Detalle_Orden).filter_by(id_orden=orden_db.id_orden).all()
        assert len(detalles) == 2

        # Transición de Estado del Activo a 'Reservado'
        activo_check = db.query(Activo_Inventariado).filter_by(id_activo=activo_disp.id_activo).first()
        estado_reservado = db.query(Estado_Activo).filter_by(nombre_estado="Reservado").first()
        assert activo_check.id_estado == estado_reservado.id_estado

    finally:
        db.close()


# ── TEST 2: Rollback ACID si un activo no está disponible ───────────────────
def test_crear_orden_falla_por_activo_no_disponible_rollback(client, db_session, auth_headers):
    activo_vendido = db_session["activo_vendido"]

    payload = {
        "cliente": {
            "rut_cliente": "19.888.777-6",
            "nombres": "Pedro",
            "apellidos": "Soto",
            "consentimiento_legal": True
        },
        "requiere_despacho": False,
        "consentimiento_legal": True,
        "items": [
            {
                "id_activo": str(activo_vendido.id_activo),
                "cantidad": 1,
                "precio_final": 500000
            }
        ]
    }

    response = client.post("/api/v1/ordenes", json=payload, headers=auth_headers)
    assert response.status_code == 409
    assert "no está disponible" in response.json()["detail"]

    # Verificar que NO se persistió ninguna orden
    db = TestingSessionLocal()
    try:
        cliente_inexistente = db.query(Cliente).filter_by(rut_cliente="19.888.777-6").first()
        assert cliente_inexistente is None
    finally:
        db.close()


# ── TEST 3: Rechazo si falta consentimiento legal (Ley 21.719) ──────────────
def test_crear_orden_falla_sin_consentimiento_legal(client, db_session, auth_headers):
    payload = {
        "cliente": {
            "rut_cliente": "12.345.678-9",
            "nombres": "Ana",
            "apellidos": "López",
            "consentimiento_legal": False
        },
        "consentimiento_legal": False,
        "items": [
            {
                "descripcion_manual": "Filtro de Aceite",
                "cantidad": 1,
                "precio_final": 10000
            }
        ]
    }

    response = client.post("/api/v1/ordenes", json=payload, headers=auth_headers)
    assert response.status_code == 400
    assert "Ley N° 21.719" in response.json()["detail"]


# ── TEST 4: Rechazo si requiere despacho pero no envía datos ────────────────
def test_crear_orden_falla_despacho_incompleto(client, db_session, auth_headers):
    payload = {
        "cliente": {
            "rut_cliente": "12.345.678-9",
            "nombres": "Ana",
            "apellidos": "López",
            "consentimiento_legal": True
        },
        "requiere_despacho": True,
        "despacho": None,
        "consentimiento_legal": True,
        "items": [
            {
                "descripcion_manual": "Filtro de Aire",
                "cantidad": 1,
                "precio_final": 12000
            }
        ]
    }

    response = client.post("/api/v1/ordenes", json=payload, headers=auth_headers)
    assert response.status_code == 400
    assert "datos de despacho" in response.json()["detail"]


# ── TEST 5: Integración con Tablero de Bodega (Alertas de Tarea) ────────────
def test_integracion_bodega_alertas_con_orden_derivada(client, db_session, auth_headers):
    # Consultar tareas pendientes de bodega para la sucursal 1
    response = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers)
    assert response.status_code == 200

    tareas = response.json()
    assert isinstance(tareas, list)
    # Debe existir al menos una alerta tipo PREPARACION
    alertas_prep = [t for t in tareas if t["tipo_alerta"] == "PREPARACION"]
    assert len(alertas_prep) >= 1

    primera_alerta = alertas_prep[0]
    assert primera_alerta["estado_bloqueo"] == "ESPERANDO PAGO EN CAJA"
    assert "Entregar con poleas instaladas" in primera_alerta["nota_especial"]


# ── TEST 6: Consultar Orden por ID ──────────────────────────────────────────
def test_consultar_orden_por_id(client, db_session, auth_headers):
    # Buscar una orden existente en BD
    db = TestingSessionLocal()
    try:
        orden = db.query(Orden_Venta).first()
        assert orden is not None
        id_orden = str(orden.id_orden)
    finally:
        db.close()

    response = client.get(f"/api/v1/ordenes/{id_orden}", headers=auth_headers)
    assert response.status_code == 200

    data = response.json()
    assert data["id_orden"] == id_orden
    assert "cliente" in data
    assert "detalles" in data


# ── TEST 7: Buscar Cliente por RUT Existente ────────────────────────────────
def test_buscar_cliente_por_rut_existente(client, db_session, auth_headers):
    # Cliente creado en los tests anteriores: 18.765.432-1
    response = client.get("/api/v1/clientes/18.765.432-1", headers=auth_headers)
    assert response.status_code == 200

    data = response.json()
    assert data["rut_cliente"] == "18.765.432-1"
    assert data["nombres"] == "Juan"
    assert "Pérez" in data["apellidos"]
    assert "comuna" in data


# ── TEST 8: Buscar Cliente por RUT No Existente Retorna 404 ─────────────────
def test_buscar_cliente_por_rut_no_existente_retorna_404(client, db_session, auth_headers):
    response = client.get("/api/v1/clientes/99.999.999-9", headers=auth_headers)
    assert response.status_code == 404
    data = response.json()
    assert "no encontrado" in data["detail"]


# ── TEST 9: Múltiples Órdenes Consecutivas con Consumidor Final (6.666.666-6) ──
def test_ordenes_multiples_consumidor_final_sin_colision(client, db_session, auth_headers):
    """Verifica que múltiples órdenes con Consumidor Final (6.666.666-6) reutilicen el mismo cliente sin error de clave única."""
    payload_1 = {
        "cliente": {
            "rut_cliente": "6.666.666-6",
            "nombres": "Consumidor",
            "apellidos": "Final",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "items": [
            {
                "descripcion_manual": "Ampolleta H4 Repuesto Consumidor 1",
                "cantidad": 1,
                "precio_final": 5000,
            }
        ],
    }

    res_1 = client.post("/api/v1/ordenes", json=payload_1, headers=auth_headers)
    assert res_1.status_code == 201, res_1.text
    id_orden_1 = res_1.json()["id_orden"]

    payload_2 = {
        "cliente": {
            "rut_cliente": "6.666.666-6",
            "nombres": "Consumidor",
            "apellidos": "Final",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "items": [
            {
                "descripcion_manual": "Líquido de Frenos DOT4 Consumidor 2",
                "cantidad": 2,
                "precio_final": 8000,
            }
        ],
    }

    res_2 = client.post("/api/v1/ordenes", json=payload_2, headers=auth_headers)
    assert res_2.status_code == 201, res_2.text
    id_orden_2 = res_2.json()["id_orden"]

    # Verificar que ambas órdenes se crearon exitosamente y apuntan al mismo cliente
    db = TestingSessionLocal()
    try:
        orden_1 = db.query(Orden_Venta).filter_by(id_orden=uuid.UUID(id_orden_1)).first()
        orden_2 = db.query(Orden_Venta).filter_by(id_orden=uuid.UUID(id_orden_2)).first()
        assert orden_1 is not None
        assert orden_2 is not None
        assert orden_1.id_cliente == orden_2.id_cliente

        clientes_genericos = db.query(Cliente).filter(
            Cliente.rut_cliente.in_(["6.666.666-6", "66666666-6"])
        ).all()
        assert len(clientes_genericos) == 1, "Debe existir exactamente 1 registro de Consumidor Final en BD"
    finally:
        db.close()

