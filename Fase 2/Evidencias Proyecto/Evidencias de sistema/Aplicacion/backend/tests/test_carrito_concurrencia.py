import uuid
import pytest
from datetime import datetime, timezone, timedelta

from models import (
    Region,
    Comuna,
    Sucursal,
    Rol,
    Usuario,
    Categoria_Activo,
    Estado_Activo,
    Vehiculo_Origen,
    Activo_Inventariado,
)
from core.security import create_access_token
from conftest import TestingSessionLocal
from routers.carrito import limpiar_reservas_expiradas


@pytest.fixture(scope="module")
def db_session(setup_database):
    db = TestingSessionLocal()
    try:
        # Seed Región, Comuna, Sucursal
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        db.add(c)

        suc = Sucursal(
            id_sucursal=1,
            nombre_sucursal="Casa Matriz - Viña",
            direccion="Av Libertad 123",
            id_comuna=1,
        )
        db.add(suc)

        # Roles
        rol_vendedor = Rol(id_rol=1, nombre_rol="Vendedor")
        db.add(rol_vendedor)

        # Usuarios Vendedores
        u1_id = uuid.uuid4()
        u2_id = uuid.uuid4()
        vendedor_1 = Usuario(
            id_usuario=u1_id,
            id_rol=1,
            id_sucursal=1,
            rut_usuario="11.111.111-1",
            nombres="Carlos",
            apellidos="Ventas",
            email="carlos.vendedor@cresal.cl",
            password_hash="hash1",
            pin_acceso="1111",
            estado="Activo",
        )
        vendedor_2 = Usuario(
            id_usuario=u2_id,
            id_rol=1,
            id_sucursal=1,
            rut_usuario="22.222.222-2",
            nombres="Andrea",
            apellidos="Comercial",
            email="andrea.vendedor@cresal.cl",
            password_hash="hash2",
            pin_acceso="2222",
            estado="Activo",
        )
        db.add_all([vendedor_1, vendedor_2])

        # Categorías y Estados
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        db.add(cat_motor)

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_baja = Estado_Activo(id_estado=4, nombre_estado="De Baja")
        db.add_all([est_disp, est_res, est_vend, est_baja])

        # Vehículo de origen
        v = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-HU03-01",
            patente="CRSL03",
            vin="12345678901234567",
            marca="Nissan",
            modelo="Qashqai",
            anio=2021,
        )
        db.add(v)

        db.commit()

        yield {
            "u1_id": u1_id,
            "u2_id": u2_id,
            "token_vendedor_1": create_access_token({"sub": str(u1_id)}),
            "token_vendedor_2": create_access_token({"sub": str(u2_id)}),
            "id_vehiculo": v.id_vehiculo,
        }
    finally:
        db.close()


def test_reserva_exitosa_activo_disponible(client, db_session):
    """
    Tarea 2: Reserva exitosa por un vendedor.
    Debe retornar 200, actualizar id_estado a 2 e incrementar version_lock.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-CONC-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=1,  # Disponible
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=750000,
        version_lock=1,
        estado="Activo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers = {"Authorization": f"Bearer {db_session['token_vendedor_1']}"}
    payload = {
        "id_activo": str(activo_id),
        "version_lock_esperado": 1,
    }

    response = client.post("/api/v1/carrito/reservar", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["id_activo"] == str(activo_id)
    assert data["version_lock"] == 2
    assert data["reservado_por"] == str(db_session["u1_id"])
    assert data["reserva_expira_en"] is not None

    # Verificar persistencia en base de datos
    db = TestingSessionLocal()
    act_db = db.query(Activo_Inventariado).filter_by(id_activo=activo_id).first()
    assert act_db.id_estado == 2
    assert act_db.version_lock == 2
    assert act_db.reservado_por == db_session["u1_id"]
    db.close()


def test_reserva_concurrente_colision_retorna_409(client, db_session):
    """
    Tarea 4 (Pytest Concurrencia):
    Dos vendedores intentan reservar el mismo activo con el mismo version_lock esperado.
    El primero gana (200), el segundo recibe 409 con el mensaje intuitivo exacto.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-RACE-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=900000,
        version_lock=1,
        estado="Activo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers_v1 = {"Authorization": f"Bearer {db_session['token_vendedor_1']}"}
    headers_v2 = {"Authorization": f"Bearer {db_session['token_vendedor_2']}"}

    payload = {
        "id_activo": str(activo_id),
        "version_lock_esperado": 1,
    }

    # 1. Primer vendedor reserva con éxito
    res1 = client.post("/api/v1/carrito/reservar", json=payload, headers=headers_v1)
    assert res1.status_code == 200
    assert res1.json()["version_lock"] == 2

    # 2. Segundo vendedor intenta reservar con el version_lock original (1) o cuando ya está reservado
    res2 = client.post("/api/v1/carrito/reservar", json=payload, headers=headers_v2)
    assert res2.status_code == 409
    detalle = res2.json()["detail"]
    assert "¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante." in detalle


def test_reserva_activo_inactivo_o_de_baja_retorna_400(client, db_session):
    """
    Sección 3: Intento de agregar pieza dañada / de baja / mantenimiento.
    Debe responder con 400 Bad Request y mensaje amigable.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-BAJA-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=4,  # De Baja
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=100000,
        version_lock=1,
        estado="Inactivo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers = {"Authorization": f"Bearer {db_session['token_vendedor_1']}"}
    payload = {
        "id_activo": str(activo_id),
        "version_lock_esperado": 1,
    }

    response = client.post("/api/v1/carrito/reservar", json=payload, headers=headers)
    assert response.status_code == 400
    assert "El artículo seleccionado se encuentra en mantenimiento o fue dado de baja del inventario." in response.json()["detail"]


def test_liberar_reserva_voluntaria_exitoso(client, db_session):
    """
    Endpoint POST /api/v1/carrito/liberar/{id_activo}.
    Reversa id_estado a 1 (Disponible) e incrementa version_lock.
    Permite que otro vendedor lo reserve después.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-LIB-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=450000,
        version_lock=1,
        estado="Activo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers_v1 = {"Authorization": f"Bearer {db_session['token_vendedor_1']}"}
    headers_v2 = {"Authorization": f"Bearer {db_session['token_vendedor_2']}"}

    # 1. Vendedor 1 reserva
    res_reserva = client.post(
        "/api/v1/carrito/reservar",
        json={"id_activo": str(activo_id), "version_lock_esperado": 1},
        headers=headers_v1,
    )
    assert res_reserva.status_code == 200
    v_lock_actual = res_reserva.json()["version_lock"]
    assert v_lock_actual == 2

    # 2. Vendedor 1 libera
    res_liberar = client.post(f"/api/v1/carrito/liberar/{activo_id}", headers=headers_v1)
    assert res_liberar.status_code == 200
    data_lib = res_liberar.json()
    assert data_lib["version_lock"] == 3

    # 3. Vendedor 2 puede ahora reservarlo usando el nuevo version_lock (3)
    res_v2 = client.post(
        "/api/v1/carrito/reservar",
        json={"id_activo": str(activo_id), "version_lock_esperado": 3},
        headers=headers_v2,
    )
    assert res_v2.status_code == 200
    assert res_v2.json()["version_lock"] == 4
    assert res_v2.json()["reservado_por"] == str(db_session["u2_id"])


def test_heartbeat_extiende_expiracion(client, db_session):
    """
    Endpoint POST /api/v1/carrito/heartbeat.
    Extiende la expiración de las reservas activas del vendedor logueado.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-HB-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=300000,
        version_lock=1,
        estado="Activo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers = {"Authorization": f"Bearer {db_session['token_vendedor_1']}"}

    # Reservar
    client.post(
        "/api/v1/carrito/reservar",
        json={"id_activo": str(activo_id), "version_lock_esperado": 1},
        headers=headers,
    )

    # Ejecutar Heartbeat
    res_hb = client.post("/api/v1/carrito/heartbeat", headers=headers)
    assert res_hb.status_code == 200
    data_hb = res_hb.json()
    assert data_hb["activos_renovados"] >= 1
    assert data_hb["nueva_expiracion"] is not None


def test_limpieza_automatica_reservas_expiradas(client, db_session):
    """
    Tarea 3: Invalida reservas caducadas (reserva_expira_en < now_utc).
    Reversa id_estado a 1 y permite que el activo vuelva a aparecer en el catálogo.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    hace_10_min = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(minutes=10)

    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-EXP-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=2,  # Reservado
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=620000,
        version_lock=2,
        estado="Activo",
        reservado_por=db_session["u1_id"],
        reserva_expira_en=hace_10_min,  # Expirada
    )
    db.add(activo)
    db.commit()

    # Ejecutar función de limpieza
    liberados = limpiar_reservas_expiradas(db)
    assert liberados >= 1

    # Verificar que el activo quedó disponible
    act_limpio = db.query(Activo_Inventariado).filter_by(id_activo=activo_id).first()
    assert act_limpio.id_estado == 1
    assert act_limpio.reservado_por is None
    assert act_limpio.reserva_expira_en is None
    assert act_limpio.version_lock == 3
    db.close()


def test_consultar_mis_reservas_con_tiempo_restante(client, db_session):
    """
    Endpoint GET /api/v1/carrito/mis-reservas.
    Retorna la lista de activos reservados por el usuario logueado con segundos_restantes.
    """
    db = TestingSessionLocal()
    activo_id = uuid.uuid4()
    activo = Activo_Inventariado(
        id_activo=activo_id,
        sku_qr_fisico=f"SKU-MIS-{uuid.uuid4().hex[:6].upper()}",
        id_categoria=1,
        id_estado=1,
        id_sucursal_actual=1,
        id_vehiculo=db_session["id_vehiculo"],
        precio_referencia=220000,
        version_lock=1,
        estado="Activo",
    )
    db.add(activo)
    db.commit()
    db.close()

    headers = {"Authorization": f"Bearer {db_session['token_vendedor_2']}"}

    client.post(
        "/api/v1/carrito/reservar",
        json={"id_activo": str(activo_id), "version_lock_esperado": 1},
        headers=headers,
    )

    res = client.get("/api/v1/carrito/mis-reservas", headers=headers)
    assert res.status_code == 200
    items = res.json()
    assert len(items) >= 1
    mi_item = next((it for it in items if it["id_activo"] == str(activo_id)), None)
    assert mi_item is not None
    assert mi_item["segundos_restantes"] > 0
    assert mi_item["precio_referencia"] == 220000
    assert mi_item["id_categoria"] == 1
    assert "sku_qr_fisico" in mi_item
