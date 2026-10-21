# test_bodega_optimizaciones.py
# Suite de pruebas automatizadas para la HU de Bodega y Traslados (Fase 1 - Backend)

import uuid
import pytest
from datetime import datetime
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor, Orden_Venta,
    Detalle_Orden, Despacho, Cliente, Tracking_Logistico
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    """Inicializa datos maestros para el módulo de pruebas de bodega y traslados."""
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

        com2 = db.query(Comuna).filter_by(id_comuna=2).first()
        if not com2:
            com2 = Comuna(id_comuna=2, nombre_comuna="Limache", id_region=1)
            db.add(com2)
            db.flush()

        # 2. Sucursales (1: Viña del Mar, 2: Limache)
        suc1 = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc1:
            suc1 = Sucursal(
                id_sucursal=1,
                nombre_sucursal="Casa Matriz - Viña",
                direccion="Camino Internacional 4105",
                id_comuna=1
            )
            db.add(suc1)
            db.flush()

        suc2 = db.query(Sucursal).filter_by(id_sucursal=2).first()
        if not suc2:
            suc2 = Sucursal(
                id_sucursal=2,
                nombre_sucursal="Sucursal Limache",
                direccion="Avenida Palmira Romano Sur 500",
                id_comuna=2
            )
            db.add(suc2)
            db.flush()

        # 3. Roles
        rol_vendedor = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_vendedor:
            rol_vendedor = Rol(id_rol=1, nombre_rol="Vendedor")
            db.add(rol_vendedor)
            db.flush()

        rol_bodeguero = db.query(Rol).filter_by(id_rol=2).first()
        if not rol_bodeguero:
            rol_bodeguero = Rol(id_rol=2, nombre_rol="Bodeguero")
            db.add(rol_bodeguero)
            db.flush()

        # 4. Usuarios
        # Vendedor en Viña
        u_vend = db.query(Usuario).filter_by(rut_usuario="11.111.111-1").first()
        if not u_vend:
            u_vend = Usuario(
                id_usuario=uuid.uuid4(),
                id_rol=1,
                id_sucursal=1,
                rut_usuario="11.111.111-1",
                nombres="Gonzalo",
                apellidos="Ventas",
                email="gonzalo.ventas@cresal.cl",
                password_hash="hash",
                pin_acceso="1111",
                estado="Activo"
            )
            db.add(u_vend)
            db.flush()

        # Bodeguero en Viña (Sucursal 1)
        u_bod_vina = db.query(Usuario).filter_by(rut_usuario="22.222.222-2").first()
        if not u_bod_vina:
            u_bod_vina = Usuario(
                id_usuario=uuid.uuid4(),
                id_rol=2,
                id_sucursal=1,
                rut_usuario="22.222.222-2",
                nombres="Patricio",
                apellidos="Bodega Viña",
                email="patricio.vina@cresal.cl",
                password_hash="hash",
                pin_acceso="2222",
                estado="Activo"
            )
            db.add(u_bod_vina)
            db.flush()

        # Bodeguero en Limache (Sucursal 2)
        u_bod_lim = db.query(Usuario).filter_by(rut_usuario="33.333.333-3").first()
        if not u_bod_lim:
            u_bod_lim = Usuario(
                id_usuario=uuid.uuid4(),
                id_rol=2,
                id_sucursal=2,
                rut_usuario="33.333.333-3",
                nombres="Mauricio",
                apellidos="Bodega Limache",
                email="mauricio.limache@cresal.cl",
                password_hash="hash",
                pin_acceso="3333",
                estado="Activo"
            )
            db.add(u_bod_lim)
            db.flush()

        # 5. Categorías y Estados
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

        est_desarme = db.query(Estado_Activo).filter_by(id_estado=5).first()
        if not est_desarme:
            est_desarme = Estado_Activo(id_estado=5, nombre_estado="En Desarme")
            db.add(est_desarme)

        est_pal = db.query(Estado_Activo).filter_by(id_estado=7).first()
        if not est_pal:
            est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
            db.add(est_pal)

        db.commit()
        yield db
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_headers_vendedor(db_session):
    u = db_session.query(Usuario).filter_by(rut_usuario="11.111.111-1").first()
    token = create_access_token(data={"sub": str(u.id_usuario)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_bodega_vina(db_session):
    u = db_session.query(Usuario).filter_by(rut_usuario="22.222.222-2").first()
    token = create_access_token(data={"sub": str(u.id_usuario)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_bodega_limache(db_session):
    u = db_session.query(Usuario).filter_by(rut_usuario="33.333.333-3").first()
    token = create_access_token(data={"sub": str(u.id_usuario)})
    return {"Authorization": f"Bearer {token}"}


def test_retencion_tareas_en_estado_2_y_estado_3(client, db_session, auth_headers_vendedor, auth_headers_bodega_vina):
    """
    Regla 1: Validar que las tareas de preparación permanezcan en el panel de bodega
    tanto cuando el activo está en estado 2 (Reservado) como cuando pasa a estado 3 (Vendido tras pago en caja).
    No debe desaparecer hasta que el bodeguero complete la preparación.
    """
    # 1. Crear vehículo y activo inventariado en Viña (id_sucursal_actual = 1)
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-RET-{uuid.uuid4().hex[:4].upper()}",
        patente=f"RT{uuid.uuid4().hex[:4].upper()}",
        marca="Toyota",
        modelo="Hilux",
        anio=2021,
    )
    db_session.add(veh)
    db_session.flush()

    sku = f"SKU-RET-{uuid.uuid4().hex[:6].upper()}"
    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=sku,
        id_categoria=1,
        id_estado=1,  # Disponible
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="P-01",
        ubicacion_pallet="PAL-01",
        precio_referencia=750000,
        qr_impreso=True,
        estado="Activo",
    )
    db_session.add(activo)
    db_session.commit()

    # 2. Crear Orden de Venta (Pasa el activo a id_estado = 2 Reservado)
    payload_orden = {
        "cliente": {
            "rut_cliente": "18.888.888-8",
            "nombres": "Andrés",
            "apellidos": "Retención",
            "telefono": "+56988888888",
            "comuna": "Viña del Mar",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "consentimiento_legal": True,
        "instrucciones_bodega": "Limpiar y revisar aceite antes de entrega",
        "id_sucursal": 1,
        "items": [
            {
                "id_activo": str(activo.id_activo),
                "cantidad": 1,
                "precio_final": 750000,
                "notas_preparacion": "Limpiar y revisar aceite",
            }
        ],
    }

    res_orden = client.post("/api/v1/ordenes", json=payload_orden, headers=auth_headers_vendedor)
    assert res_orden.status_code == 201, res_orden.text
    orden_data = res_orden.json()
    id_orden = orden_data["id_orden"]

    # Verificar que el activo está en estado 2 (Reservado)
    db_session.refresh(activo)
    assert activo.id_estado == 2

    # 3. Consultar tablero de bodega en Viña (sucursal_id = 1) -> Tarea DEBE estar visible
    res_bodega_1 = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega_1.status_code == 200
    tareas_1 = res_bodega_1.json()

    tarea_encontrada = next((t for t in tareas_1 if t.get("id_activo") == str(activo.id_activo)), None)
    assert tarea_encontrada is not None, "La tarea debe aparecer en bodega cuando el activo está Reservado (id_estado = 2)"
    assert tarea_encontrada["tipo_alerta"] == "PREPARACION"
    assert tarea_encontrada["estado_bloqueo"] == "ESPERANDO PAGO EN CAJA"

    # 4. Simular pago en caja: Orden pasa a 'Pagada', monto_pendiente = 0, activo pasa a id_estado = 3 (Vendido)
    orden_db = db_session.query(Orden_Venta).filter_by(id_orden=uuid.UUID(id_orden)).first()
    orden_db.estado_orden = "Pagada"
    orden_db.monto_pendiente = 0
    activo.id_estado = 3  # Vendido
    db_session.commit()

    # 5. Consultar tablero de bodega en Viña nuevamente -> Tarea DEBE SEGUIR VISIBLE (Retención)
    res_bodega_2 = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega_2.status_code == 200
    tareas_2 = res_bodega_2.json()

    tarea_retenida = next((t for t in tareas_2 if t.get("id_activo") == str(activo.id_activo)), None)
    assert tarea_retenida is not None, "La tarea NO debe desaparecer cuando el activo pasa a Vendido (id_estado = 3) tras pago en caja"
    assert tarea_retenida["tipo_alerta"] == "LIBERADA"
    assert tarea_retenida["estado_bloqueo"] is None
    assert tarea_retenida["accion_requerida"] == "ESCANEAR EN BARRERA"

    # 6. Bodeguero marca 'Listo' la preparación física en la orden ya Pagada
    res_listo = client.patch(
        f"/api/v1/bodega/tareas/{tarea_retenida['id_detalle']}/completar-preentrega",
        headers=auth_headers_bodega_vina
    )
    assert res_listo.status_code == 200

    # 7. La tarea DEBE SEGUIR VISIBLE como LIBERADA porque aún no se entrega en barrera
    res_bodega_3 = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega_3.status_code == 200
    tarea_post_listo = next((t for t in res_bodega_3.json() if t.get("id_activo") == str(activo.id_activo)), None)
    assert tarea_post_listo is not None, "La orden Pagada DEBE permanecer como LIBERADA incluso después de marcar 'Listo'"
    assert tarea_post_listo["tipo_alerta"] == "LIBERADA"
    assert tarea_post_listo["estado_preparacion"] == "Listo"
    assert tarea_post_listo["accion_requerida"] == "ESCANEAR EN BARRERA"


def test_accion_listo_completar_preentrega_exitoso(client, db_session, auth_headers_vendedor, auth_headers_bodega_vina):
    """
    Regla 1 (Acción 'Listo'): Al invocar PATCH /api/v1/bodega/tareas/{id_detalle}/completar-preentrega,
    la tarea se marca como 'Listo' y desaparece del panel de pendientes de bodega.
    """
    # 1. Crear vehículo y activo
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-LST-{uuid.uuid4().hex[:4].upper()}",
        patente=f"LS{uuid.uuid4().hex[:4].upper()}",
        marca="Nissan",
        modelo="Qashqai",
        anio=2019,
    )
    db_session.add(veh)
    db_session.flush()

    sku = f"SKU-LST-{uuid.uuid4().hex[:6].upper()}"
    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=sku,
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="P-02",
        ubicacion_pallet="PAL-04",
        precio_referencia=600000,
        qr_impreso=True,
        estado="Activo",
    )
    db_session.add(activo)
    db_session.commit()

    # 2. Crear orden
    payload_orden = {
        "cliente": {
            "rut_cliente": "17.777.777-7",
            "nombres": "Bernardo",
            "apellidos": "O'Higgins",
            "comuna": "Viña del Mar",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "consentimiento_legal": True,
        "id_sucursal": 1,
        "items": [
            {
                "id_activo": str(activo.id_activo),
                "cantidad": 1,
                "precio_final": 600000,
                "notas_preparacion": "Desengrasar y embalar en film protector",
            }
        ],
    }

    res_orden = client.post("/api/v1/ordenes", json=payload_orden, headers=auth_headers_vendedor)
    assert res_orden.status_code == 201

    # Obtener el id_detalle
    res_bodega = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega.status_code == 200
    tarea = next(t for t in res_bodega.json() if t.get("id_activo") == str(activo.id_activo))
    id_detalle = tarea["id_detalle"]
    assert id_detalle is not None

    # 3. Bodeguero marca la preparación como 'Listo'
    res_patch = client.patch(
        f"/api/v1/bodega/tareas/{id_detalle}/completar-preentrega",
        headers=auth_headers_bodega_vina
    )
    assert res_patch.status_code == 200, res_patch.text
    patch_data = res_patch.json()
    assert patch_data["preparacion_lista"] is True
    assert patch_data["estado_preparacion"] == "Listo"
    assert "fecha_preparacion" in patch_data

    # 4. Verificar persistencia en base de datos
    det_db = db_session.query(Detalle_Orden).filter_by(id_detalle=uuid.UUID(id_detalle)).first()
    assert det_db.preparacion_lista is True
    assert det_db.estado_preparacion == "Listo"

    # 5. Verificar que la tarea DESAPARECE del panel de pendientes de bodega
    res_bodega_post = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega_post.status_code == 200
    tareas_post = res_bodega_post.json()
    tarea_desaparecida = next((t for t in tareas_post if t.get("id_detalle") == id_detalle), None)
    assert tarea_desaparecida is None, "La tarea debe desaparecer del panel de pendientes una vez marcada como 'Listo'"


def test_completar_preentrega_404_no_encontrado(client, auth_headers_bodega_vina):
    """Validar que un UUID inexistente responda con 404 Not Found."""
    fake_id = uuid.uuid4()
    res = client.patch(
        f"/api/v1/bodega/tareas/{fake_id}/completar-preentrega",
        headers=auth_headers_bodega_vina
    )
    assert res.status_code == 404
    assert f"Línea de detalle con ID '{fake_id}' no encontrada." in res.json()["detail"]


def test_traslado_limache_a_vina_asignacion_origen(client, db_session, auth_headers_vendedor, auth_headers_bodega_vina, auth_headers_bodega_limache):
    """
    Regla 2: Lógica de Traslado entre Sucursales (Viña - Limache).
    Si un activo está ubicado en id_sucursal_actual == 2 (Limache) y se vende en Viña (id_sucursal == 1),
    genera automáticamente la tarea de preparación y traslado asignada a la sucursal de origen (Limache id_sucursal == 2)
    y registra el Tracking_Logistico.
    """
    # 1. Crear activo ubicado físicamente en Limache (id_sucursal_actual = 2)
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-TRS-{uuid.uuid4().hex[:4].upper()}",
        patente=f"TR{uuid.uuid4().hex[:4].upper()}",
        marca="Hyundai",
        modelo="Tucson",
        anio=2020,
    )
    db_session.add(veh)
    db_session.flush()

    sku = f"SKU-TRS-{uuid.uuid4().hex[:6].upper()}"
    activo_limache = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=sku,
        id_categoria=1,
        id_estado=1,  # Disponible
        id_sucursal_actual=2,  # Ubicado en LIMACHE
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="PAS-L1",
        ubicacion_pallet="PAL-L3",
        precio_referencia=900000,
        qr_impreso=True,
        estado="Activo",
    )
    db_session.add(activo_limache)
    db_session.commit()

    # 2. Venta generada en Viña del Mar (id_sucursal = 1) con tipo_entrega = 'Traslado'
    payload_traslado = {
        "cliente": {
            "rut_cliente": "16.666.666-6",
            "nombres": "Camila",
            "apellidos": "Traslados",
            "comuna": "Viña del Mar",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "tipo_entrega": "Traslado",
        "id_sucursal_destino": 1,
        "consentimiento_legal": True,
        "id_sucursal": 1,  # Venta en Viña del Mar
        "items": [
            {
                "id_activo": str(activo_limache.id_activo),
                "cantidad": 1,
                "precio_final": 900000,
                "notas_preparacion": "Paletizar para flete de las 14:00 hrs",
            }
        ],
    }

    res_orden = client.post("/api/v1/ordenes", json=payload_traslado, headers=auth_headers_vendedor)
    assert res_orden.status_code == 201, res_orden.text
    id_orden = res_orden.json()["id_orden"]

    # 3. Validar que se generó Tracking_Logistico automático y NO Despacho
    tracking = db_session.query(Tracking_Logistico).filter_by(id_activo=activo_limache.id_activo).first()
    assert tracking is not None, "Debe generarse un registro de Tracking_Logistico para el traslado"
    assert tracking.id_sucursal_origen == 2, "La sucursal de origen debe ser Limache (2)"
    assert tracking.id_sucursal_destino == 1, "La sucursal de destino debe ser Viña del Mar (1)"
    assert tracking.estado_traslado == "Pendiente"

    desp_db = db_session.query(Despacho).filter_by(id_orden=uuid.UUID(id_orden)).first()
    assert desp_db is None, "No debe crearse registro en Despacho para traslados internos entre sucursales"

    # 4. Validar que la tarea NO aparece en la bodega de Viña (sucursal_id = 1)
    res_bodega_vina = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega_vina.status_code == 200
    tarea_en_vina = next((t for t in res_bodega_vina.json() if t.get("id_activo") == str(activo_limache.id_activo)), None)
    assert tarea_en_vina is None, "La tarea NO debe aparecer en la bodega de Viña porque la pieza aún está en Limache"

    # 5. Validar que la tarea SÍ aparece en la bodega de Limache (sucursal_id = 2)
    res_bodega_limache = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=2", headers=auth_headers_bodega_limache)
    assert res_bodega_limache.status_code == 200
    tareas_limache = res_bodega_limache.json()
    tarea_en_limache = next((t for t in tareas_limache if t.get("id_activo") == str(activo_limache.id_activo)), None)
    assert tarea_en_limache is not None, "La tarea DEBE aparecer en la bodega de Limache (origen)"
    assert tarea_en_limache["tipo_alerta"] == "TRASLADO"
    assert tarea_en_limache["es_traslado"] is True
    assert tarea_en_limache["id_sucursal_origen"] == 2
    assert tarea_en_limache["id_sucursal_destino"] == 1

    # 6. Bodeguero de Limache completa la preparación para traslado
    id_det_limache = tarea_en_limache["id_detalle"]
    res_listo_lim = client.patch(
        f"/api/v1/bodega/tareas/{id_det_limache}/completar-preentrega",
        headers=auth_headers_bodega_limache
    )
    assert res_listo_lim.status_code == 200
    assert res_listo_lim.json()["preparacion_lista"] is True

    # 7. Validar que el tracking logístico se actualizó a 'Listo para Traslado'
    db_session.refresh(tracking)
    assert tracking.estado_traslado == "Listo para Traslado"

    # 8. Validar que desaparece de las tareas pendientes de Limache
    res_bodega_lim_post = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=2", headers=auth_headers_bodega_limache)
    tarea_lim_post = next((t for t in res_bodega_lim_post.json() if t.get("id_detalle") == id_det_limache), None)
    assert tarea_lim_post is None, "La tarea debe desaparecer de la bodega de Limache una vez completada"


def test_traslado_validaciones_sucursales_invalidas(client, db_session, auth_headers_vendedor):
    """Validar rechazo si la sucursal de traslado no es válida o si origen y destino coinciden."""
    # 1. Crear activo en Viña (1)
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-VAL-{uuid.uuid4().hex[:4].upper()}",
        patente=f"VL{uuid.uuid4().hex[:4].upper()}",
        marca="Toyota",
        modelo="Corolla",
        anio=2018,
    )
    db_session.add(veh)
    db_session.flush()

    sku = f"SKU-VAL-{uuid.uuid4().hex[:6].upper()}"
    activo = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=sku,
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        precio_referencia=500000,
        qr_impreso=True,
        estado="Activo",
    )
    db_session.add(activo)
    db_session.commit()

    # Caso A: Sucursal de destino no válida (ej. sucursal 99)
    payload_invalido_1 = {
        "cliente": {
            "rut_cliente": "15.555.555-5",
            "nombres": "Error",
            "apellidos": "Sucursal",
            "consentimiento_legal": True,
        },
        "tipo_entrega": "Traslado",
        "id_sucursal_destino": 99,  # Inválido
        "consentimiento_legal": True,
        "id_sucursal": 1,
        "items": [
            {
                "id_activo": str(activo.id_activo),
                "cantidad": 1,
                "precio_final": 500000,
            }
        ],
    }
    res_1 = client.post("/api/v1/ordenes", json=payload_invalido_1, headers=auth_headers_vendedor)
    assert res_1.status_code == 400
    assert "La sucursal de destino no es válida" in res_1.json()["detail"]

    # Caso B: Mismo origen y destino para un traslado explícito
    payload_invalido_2 = {
        "cliente": {
            "rut_cliente": "15.555.555-5",
            "nombres": "Error",
            "apellidos": "MismaSucursal",
            "consentimiento_legal": True,
        },
        "tipo_entrega": "Traslado",
        "id_sucursal_destino": 1,  # Activo ya está en 1
        "consentimiento_legal": True,
        "id_sucursal": 1,
        "items": [
            {
                "id_activo": str(activo.id_activo),
                "cantidad": 1,
                "precio_final": 500000,
            }
        ],
    }
    res_2 = client.post("/api/v1/ordenes", json=payload_invalido_2, headers=auth_headers_vendedor)
    assert res_2.status_code == 400
    assert "La sucursal de origen y destino no pueden ser iguales" in res_2.json()["detail"]


def test_alertas_impresion_qr_todos_activos_sin_qr(client, db_session, auth_headers_bodega_vina):
    """
    Verifica que la bandeja de impresión / re-impresión QR en bodega:
    - Incluya activos paletizados con qr_impreso = False (independientemente de si tienen pasillo/pallet asignado).
    - Excluya activos en estado En Desarme (5) o no paletizados.
    - Excluya activos con qr_impreso = True o pertenecientes a otra sucursal.
    """
    # 1. Crear vehículo
    veh = Vehiculo_Origen(
        id_vehiculo=uuid.uuid4(),
        numero_ingreso=f"ING-QR-{uuid.uuid4().hex[:4].upper()}",
        patente=f"QR{uuid.uuid4().hex[:4].upper()}",
        marca="Mazda",
        modelo="3",
        anio=2020,
    )
    db_session.add(veh)
    db_session.flush()

    # Activo A: Paletizado (7) con qr_impreso = False -> DEBE APARECER
    act_a = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"SKU-QRA-{uuid.uuid4().hex[:4].upper()}",
        id_categoria=1,
        id_estado=7,  # Paletizado
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="P-03",
        ubicacion_pallet="PAL-12",
        precio_referencia=600000,
        qr_impreso=False,
        estado="Activo",
    )

    # Activo B: En Desarme (5) con qr_impreso = False -> NO DEBE APARECER (aún no paletizado)
    act_b = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"SKU-QRB-{uuid.uuid4().hex[:4].upper()}",
        id_categoria=2,
        id_estado=5,  # En Desarme / Sin Paletizar
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo=None,
        ubicacion_pallet=None,
        precio_referencia=450000,
        qr_impreso=False,
        estado="Activo",
    )

    # Activo C: Paletizado (7) pero sin pasillo/pallet ("S/P") con qr_impreso = False -> DEBE APARECER
    act_c = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"SKU-QRC-{uuid.uuid4().hex[:4].upper()}",
        id_categoria=1,
        id_estado=7,  # Paletizado
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="S/P",
        ubicacion_pallet="S/P",
        precio_referencia=500000,
        qr_impreso=False,
        estado="Activo",
    )

    # Activo D: Paletizado con qr_impreso = True -> NO DEBE APARECER
    act_d = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"SKU-QRD-{uuid.uuid4().hex[:4].upper()}",
        id_categoria=1,
        id_estado=7,  # Paletizado
        id_sucursal_actual=1,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="P-01",
        ubicacion_pallet="PAL-01",
        precio_referencia=500000,
        qr_impreso=True,
        estado="Activo",
    )

    # Activo E: Paletizado en otra sucursal (2) con qr_impreso = False -> NO DEBE APARECER en sucursal 1
    act_e = Activo_Inventariado(
        id_activo=uuid.uuid4(),
        sku_qr_fisico=f"SKU-QRE-{uuid.uuid4().hex[:4].upper()}",
        id_categoria=1,
        id_estado=7,  # Paletizado
        id_sucursal_actual=2,
        id_vehiculo=veh.id_vehiculo,
        ubicacion_pasillo="P-02",
        ubicacion_pallet="PAL-02",
        precio_referencia=500000,
        qr_impreso=False,
        estado="Activo",
    )

    db_session.add_all([act_a, act_b, act_c, act_d, act_e])
    db_session.commit()

    # 2. Consultar tareas pendientes de bodega en Viña
    res = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res.status_code == 200
    tareas = res.json()

    ids_impresion = [t["id_activo"] for t in tareas if t["tipo_alerta"] == "IMPRESION"]

    assert str(act_a.id_activo) in ids_impresion, "El activo A (Paletizado) DEBE aparecer en impresión"
    assert str(act_b.id_activo) not in ids_impresion, "El activo B (En Desarme / estado 5) NO DEBE aparecer en impresión"
    assert str(act_c.id_activo) in ids_impresion, "El activo C (Paletizado sin ubicación física) DEBE aparecer en impresión"
    assert str(act_d.id_activo) not in ids_impresion, "El activo D (con qr_impreso = True) NO debe aparecer en impresión"
    assert str(act_e.id_activo) not in ids_impresion, "El activo E (otra sucursal) NO debe aparecer en impresión de sucursal 1"


def test_orden_miscelaneos_no_genera_tareas_bodega(client, db_session, auth_headers_vendedor, auth_headers_bodega_vina):
    """
    Verifica que al crearse una orden de solo venta libre / misceláneos (id_activo is None),
    NO le llega ninguna tarea de preparación ni alerta al bodeguero.
    """
    payload_orden = {
        "cliente": {
            "rut_cliente": "19.999.999-9",
            "nombres": "Arturo",
            "apellidos": "Prat",
            "comuna": "Valparaíso",
            "consentimiento_legal": True,
        },
        "requiere_despacho": False,
        "consentimiento_legal": True,
        "id_sucursal": 1,
        "items": [
            {
                "descripcion_manual": "Ampolleta H4 y Fusible 15A",
                "cantidad": 2,
                "precio_final": 15000,
            }
        ],
    }

    res = client.post("/api/v1/ordenes", json=payload_orden, headers=auth_headers_vendedor)
    assert res.status_code == 201
    orden_data = res.json()
    id_orden = orden_data["id_orden"]
    folio = orden_data["folio"]

    # Consultar tareas de bodega
    res_bodega = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=auth_headers_bodega_vina)
    assert res_bodega.status_code == 200
    tareas = res_bodega.json()

    # Ninguna tarea debe pertenecer a esta orden de misceláneos
    tareas_de_esta_orden = [
        t for t in tareas
        if t.get("id_orden") == id_orden or t.get("folio") == folio or t.get("orden_ref") == folio
    ]
    assert len(tareas_de_esta_orden) == 0, f"Error: Bodega recibió tareas para orden de misceláneos: {tareas_de_esta_orden}"


