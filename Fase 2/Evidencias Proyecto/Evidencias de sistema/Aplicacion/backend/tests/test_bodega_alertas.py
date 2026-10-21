# test_bodega_alertas.py
# Suite de pruebas automatizadas para SPEC-HU-06: Resumen de Alertas y Tareas de Bodega

import uuid
import pytest
from datetime import datetime, timezone
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Orden_Venta, Detalle_Orden, Cliente
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

        # 2. Sucursales
        suc1 = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc1:
            suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Camino Internacional 4105", id_comuna=1)
            db.add(suc1)
            db.flush()

        suc2 = db.query(Sucursal).filter_by(id_sucursal=2).first()
        if not suc2:
            suc2 = Sucursal(id_sucursal=2, nombre_sucursal="Sucursal Limache", direccion="Av. Palmira Romano 500", id_comuna=1)
            db.add(suc2)
            db.flush()

        # 3. Roles
        roles_data = [
            (1, "Bodeguero"),
            (2, "Vendedor"),
            (3, "Cajero"),
            (4, "Supervisor"),
            (5, "Administrador"),
        ]
        for r_id, r_nom in roles_data:
            r = db.query(Rol).filter_by(id_rol=r_id).first()
            if not r:
                db.add(Rol(id_rol=r_id, nombre_rol=r_nom))
        db.flush()

        # 4. Estados Activo
        estados_data = [
            (1, "Disponible"),
            (2, "Reservado"),
            (3, "Vendido"),
            (5, "Pendiente de Paletizado"),
            (7, "Paletizado"),
        ]
        for e_id, e_nom in estados_data:
            e = db.query(Estado_Activo).filter_by(id_estado=e_id).first()
            if not e:
                db.add(Estado_Activo(id_estado=e_id, nombre_estado=e_nom))
        db.flush()

        # 5. Categoría
        cat = db.query(Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat:
            cat = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat)
            db.flush()

        # 6. Bodeguero Usuario
        user_bodega = db.query(Usuario).filter_by(rut_usuario="15555555-5").first()
        if not user_bodega:
            user_bodega = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="15555555-5",
                nombres="Carlos",
                apellidos="Bodega",
                email="carlos.bodega.alertas@cresal.cl",
                password_hash="mock_hash",
                id_rol=1,
                id_sucursal=1,
                pin_acceso="9981",
                estado="Activo",
            )
            db.add(user_bodega)
            db.flush()

        # 7. Vendedor Usuario
        user_vendedor = db.query(Usuario).filter_by(rut_usuario="16666666-6").first()
        if not user_vendedor:
            user_vendedor = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="16666666-6",
                nombres="Valeska",
                apellidos="Vendedora",
                email="valeska.vendedora.alertas@cresal.cl",
                password_hash="mock_hash",
                id_rol=2,
                id_sucursal=1,
                pin_acceso="9982",
                estado="Activo",
            )
            db.add(user_vendedor)
            db.flush()

        # 8. Cliente Mock
        cliente = db.query(Cliente).filter_by(rut_cliente="17777777-7").first()
        if not cliente:
            cliente = Cliente(
                id_cliente=uuid.uuid4(),
                rut_cliente="17777777-7",
                nombres="Ignacio",
                apellidos="Alertas",
                id_comuna=1,
                consentimiento_legal=True,
                estado="Activo",
            )
            db.add(cliente)
            db.flush()

        db.commit()
        yield db
    finally:
        db.close()


@pytest.fixture
def auth_token_bodeguero(db_session):
    user = db_session.query(Usuario).filter_by(rut_usuario="15555555-5").first()
    return create_access_token(data={"sub": str(user.id_usuario), "id_rol": user.id_rol, "id_sucursal": user.id_sucursal})


def test_obtener_resumen_alertas_vacio(client, auth_token_bodeguero):
    """Verifica que /resumen-alertas retorna 0 en todos los campos cuando no hay tareas activas."""
    headers = {"Authorization": f"Bearer {auth_token_bodeguero}"}
    response = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=999", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "total_tareas" in data
    assert "desglose_preparacion" in data
    assert "desglose_entregas" in data
    assert "desglose_reingresos" in data
    assert data["total_tareas"] == 0
    assert data["desglose_preparacion"] == 0
    assert data["desglose_entregas"] == 0
    assert data["desglose_reingresos"] == 0


def test_obtener_resumen_alertas_con_preparacion_y_reingreso(client, db_session, auth_token_bodeguero):
    """
    Crea:
    1. Una orden reservada con una pieza pendiente de preparación en sucursal 1.
    2. Una orden anulada con una pieza pendiente de reingreso en sucursal 1.
    3. Verifica que /resumen-alertas desglosa correctamente preparaciones, reingresos y total.
    """
    vehiculo = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-{uuid.uuid4().hex[:6]}",
        marca="Toyota",
        modelo="Hilux",
        anio=2021,
    )
    db_session.add(vehiculo)
    db_session.flush()

    # Activo 1: Reservado para preparación
    activo1 = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        id_vehiculo=vehiculo.id_vehiculo,
        id_categoria=1,
        id_estado=2,  # Reservado
        id_sucursal_actual=1,
        sku_qr_fisico=f"SKU-ALT-1-{uuid.uuid4().hex[:4]}",
        precio_referencia=250000,
        ubicacion_pasillo="P1",
        ubicacion_pallet="R1",
        qr_impreso=True,
        estado="Activo",
    )
    # Activo 2: Anulado pendiente de reingreso (id_estado = 2, no paletizado)
    activo2 = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        id_vehiculo=vehiculo.id_vehiculo,
        id_categoria=1,
        id_estado=2,
        id_sucursal_actual=1,
        sku_qr_fisico=f"SKU-ALT-2-{uuid.uuid4().hex[:4]}",
        precio_referencia=180000,
        ubicacion_pasillo="P2",
        ubicacion_pallet="R2",
        qr_impreso=True,
        estado="Activo",
    )
    db_session.add_all([activo1, activo2])
    db_session.flush()

    cliente = db_session.query(Cliente).filter_by(rut_cliente="17777777-7").first()
    vendedor = db_session.query(Usuario).filter_by(id_rol=2).first()

    # Orden 1: Reservada (genera tarea de preparación)
    orden_prep = Orden_Venta(
        id_orden=uuid.uuid4(),
        id_cliente=cliente.id_cliente,
        id_vendedor=vendedor.id_usuario,
        id_sucursal=1,
        estado_orden="Reservada",
        total_venta=250000,
        monto_pendiente=250000,
        qr_transaccional_salida=f"TX-ALT-{uuid.uuid4().hex[:8]}",
    )
    db_session.add(orden_prep)
    db_session.flush()

    detalle_prep = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=orden_prep.id_orden,
        id_activo=activo1.id_activo,
        precio_unitario=250000,
        precio_final=250000,
        cantidad=1,
        estado_preparacion="Pendiente",
    )
    db_session.add(detalle_prep)

    # Orden 2: Anulada (genera tarea de reingreso)
    orden_anulada = Orden_Venta(
        id_orden=uuid.uuid4(),
        id_cliente=cliente.id_cliente,
        id_vendedor=vendedor.id_usuario,
        id_sucursal=1,
        estado_orden="Anulada",
        total_venta=180000,
        monto_pendiente=0,
        fecha_actualizacion=datetime.now(timezone.utc),
    )
    db_session.add(orden_anulada)
    db_session.flush()

    detalle_anulado = Detalle_Orden(
        id_detalle=uuid.uuid4(),
        id_orden=orden_anulada.id_orden,
        id_activo=activo2.id_activo,
        precio_unitario=180000,
        precio_final=180000,
        cantidad=1,
    )
    db_session.add(detalle_anulado)
    db_session.commit()

    headers = {"Authorization": f"Bearer {auth_token_bodeguero}"}
    response = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=headers)
    assert response.status_code == 200
    data = response.json()

    assert data["desglose_preparacion"] >= 1
    assert data["desglose_reingresos"] >= 1
    assert data["total_tareas"] == (data["desglose_preparacion"] + data["desglose_entregas"] + data["desglose_reingresos"])


def test_completar_preentrega_decrementa_resumen(client, db_session, auth_token_bodeguero):
    """Verifica que al completar la pre-entrega de una pieza, el conteo de preparaciones se reduce."""
    detalle = (
        db_session.query(Detalle_Orden)
        .filter(Detalle_Orden.estado_preparacion == "Pendiente")
        .first()
    )
    assert detalle is not None

    headers = {"Authorization": f"Bearer {auth_token_bodeguero}"}

    # Obtener conteo inicial
    res1 = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=headers).json()
    conteo_previo = res1["desglose_preparacion"]

    # Marcar listo
    patch_res = client.patch(f"/api/v1/bodega/tareas/{detalle.id_detalle}/completar-preentrega", headers=headers)
    assert patch_res.status_code == 200

    # Obtener nuevo conteo
    res2 = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=headers).json()
    assert res2["desglose_preparacion"] == conteo_previo - 1


def test_obtener_tareas_pendientes_incluye_reingresos(client, auth_token_bodeguero):
    """Verifica que /tareas-pendientes retorna las tareas de REINGRESO para Logística Inversa."""
    headers = {"Authorization": f"Bearer {auth_token_bodeguero}"}
    response = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=headers)
    assert response.status_code == 200
    tareas = response.json()
    assert isinstance(tareas, list)
    
    reingresos = [t for t in tareas if t["tipo_alerta"] == "REINGRESO"]
    assert len(reingresos) >= 1
    tarea_reingreso = reingresos[0]
    assert tarea_reingreso["accion_requerida"] == "REINGRESAR / PALETIZAR"
    assert tarea_reingreso["sku_qr_fisico"] is not None
    assert "ORD" in tarea_reingreso["orden_ref"]


def test_alertas_impresion_excluye_en_desarme_y_cuenta_paletizados(client, db_session, auth_token_bodeguero):
    """
    Verifica que:
    1. Un activo en estado 'En Desarme' (5) con qr_impreso=False NO genere alerta de impresión.
    2. Un activo en estado 'Paletizado' (7) con qr_impreso=False SÍ genere alerta de impresión.
    3. Un activo en estado 'Reservado' (2) con qr_impreso=False (ej. orden creada antes de imprimir) SÍ genere alerta de impresión.
    """
    headers = {"Authorization": f"Bearer {auth_token_bodeguero}"}

    # Obtener conteo inicial de impresiones
    res_ini = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=headers).json()
    impresiones_previas = res_ini["desglose_entregas"]

    # Crear vehículo
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-PRN-{uuid.uuid4().hex[:4].upper()}",
        patente=f"PR{uuid.uuid4().hex[:4].upper()}",
        marca="Toyota",
        modelo="Yaris",
        anio=2019,
    )
    db_session.add(veh)
    db_session.flush()

    # Activo 1: En Desarme (5) con qr_impreso=False -> NO DEBE CONTARSE
    act_desarme = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        id_vehiculo=veh.id_vehiculo,
        id_categoria=1,
        id_estado=5,  # Pendiente de Paletizado / En Desarme
        id_sucursal_actual=1,
        sku_qr_fisico=f"SKU-DESARME-{uuid.uuid4().hex[:4]}",
        precio_referencia=200000,
        qr_impreso=False,
        estado="Activo",
    )

    # Activo 2: Paletizado (7) con qr_impreso=False -> SÍ DEBE CONTARSE
    act_paletizado = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        id_vehiculo=veh.id_vehiculo,
        id_categoria=1,
        id_estado=7,  # Paletizado
        id_sucursal_actual=1,
        sku_qr_fisico=f"SKU-PALETIZADO-{uuid.uuid4().hex[:4]}",
        precio_referencia=200000,
        ubicacion_pasillo="P4",
        ubicacion_pallet="R10",
        qr_impreso=False,
        estado="Activo",
    )

    # Activo 3: Reservado (2) con qr_impreso=False (ej. motor reservado antes de imprimir etiqueta) -> SÍ DEBE CONTARSE
    act_reservado = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        id_vehiculo=veh.id_vehiculo,
        id_categoria=1,
        id_estado=2,  # Reservado
        id_sucursal_actual=1,
        sku_qr_fisico=f"SKU-RESERVADO-{uuid.uuid4().hex[:4]}",
        precio_referencia=300000,
        ubicacion_pasillo="a",
        ubicacion_pallet="1",
        ubicacion_galpon="a",
        qr_impreso=False,
        estado="Activo",
    )

    db_session.add_all([act_desarme, act_paletizado, act_reservado])
    db_session.commit()

    # 1. Verificar en /resumen-alertas (+2: paletizado y reservado; desarme no cuenta)
    res_nuevo = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=headers).json()
    assert res_nuevo["desglose_entregas"] == impresiones_previas + 2, (
        "Activos Paletizado y Reservado sin QR impreso deben sumar; el activo en Desarme debe ser excluido."
    )

    # 2. Verificar en /tareas-pendientes
    res_tareas = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=headers).json()
    ids_impresion = [t["id_activo"] for t in res_tareas if t["tipo_alerta"] == "IMPRESION"]

    assert str(act_paletizado.id_activo) in ids_impresion, "El activo Paletizado DEBE aparecer en impresión"
    assert str(act_reservado.id_activo) in ids_impresion, "El activo Reservado con qr_impreso=False DEBE aparecer en impresión"
    assert str(act_desarme.id_activo) not in ids_impresion, "El activo En Desarme NO DEBE aparecer en impresión"



