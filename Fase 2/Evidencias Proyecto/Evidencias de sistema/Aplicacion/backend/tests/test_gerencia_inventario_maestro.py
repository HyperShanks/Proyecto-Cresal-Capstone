# backend/tests/test_gerencia_inventario_maestro.py
"""
Suite de Pruebas Automatizadas para HU-5.3:
Maestro de Inventario Global y Tasación de Repuestos Paletizados.
"""

import uuid
from datetime import datetime, timezone
import pytest

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
    Detalle_Motor,
    Detalle_Caja_Cambio,
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_maestro(setup_database):
    db = TestingSessionLocal()
    try:
        # Geografía y Sucursales
        r = Region(id_region=30, nombre_region="Valparaíso")
        db.add(r)
        c1 = Comuna(id_comuna=301, nombre_comuna="Viña del Mar", id_region=30)
        c2 = Comuna(id_comuna=302, nombre_comuna="Limache", id_region=30)
        db.add_all([c1, c2])

        suc1 = Sucursal(id_sucursal=31, nombre_sucursal="Casa Matriz (Viña)", direccion="Av. Libertad 100", id_comuna=301)
        suc2 = Sucursal(id_sucursal=32, nombre_sucursal="Patio Desarme (Limache)", direccion="Av. Palmira 200", id_comuna=302)
        db.add_all([suc1, suc2])

        # Roles
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_gerente = Rol(id_rol=4, nombre_rol="Gerente")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        db.add_all([rol_vendedor, rol_gerente, rol_admin])

        # Usuarios
        gerente_id = uuid.uuid4()
        admin_id = uuid.uuid4()
        vendedor_id = uuid.uuid4()

        gerente = Usuario(
            id_usuario=gerente_id,
            id_rol=4,
            id_sucursal=31,
            rut_usuario="14.222.333-4",
            nombres="Roberto",
            apellidos="Gerente",
            email="gerente.maestro@cresal.cl",
            password_hash="hash",
            pin_acceso="1234",
            estado="Activo",
        )
        admin = Usuario(
            id_usuario=admin_id,
            id_rol=5,
            id_sucursal=31,
            rut_usuario="15.333.444-5",
            nombres="Admin",
            apellidos="Sistema",
            email="admin.maestro@cresal.cl",
            password_hash="hash",
            pin_acceso="5555",
            estado="Activo",
        )
        vendedor = Usuario(
            id_usuario=vendedor_id,
            id_rol=2,
            id_sucursal=31,
            rut_usuario="16.444.555-6",
            nombres="Vendedor",
            apellidos="Prueba",
            email="vendedor.maestro@cresal.cl",
            password_hash="hash",
            pin_acceso="2222",
            estado="Activo",
        )
        db.add_all([gerente, admin, vendedor])

        # Categorías
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motores")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Cajas de Cambio")
        db.add_all([cat_motor, cat_caja])

        # Estados de Activo (1: Disponible, 2: Reservado, 3: Vendido, 7: Paletizado)
        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_ven = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
        db.add_all([est_disp, est_res, est_ven, est_pal])

        # Vehículos
        veh1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-501",
            marca="Toyota",
            modelo="Hilux",
            anio=2021,
            traccion="4x4",
        )
        veh2 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-502",
            marca="Hyundai",
            modelo="Accent",
            anio=2019,
            traccion="4x2",
        )
        db.add_all([veh1, veh2])

        # Activo 1: Motor Paletizado SIN PRECIO en Sucursal 31
        act1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=act1_id,
            sku_qr_fisico="MOT-5001-A1",
            id_categoria=1,
            id_estado=7,  # Paletizado
            id_sucursal_actual=31,
            id_vehiculo=veh1.id_vehiculo,
            ubicacion_galpon="1",
            ubicacion_pasillo="A",
            ubicacion_pallet="4",
            precio_referencia=None,
            version_lock=1,
            estado="Activo",
        )
        mot1 = Detalle_Motor(
            id_activo=act1_id,
            numero_motor="1GD-887766",
            cilindrada="2.8",
            combustible="Diesel",
            transmision_tipo="Automática",
        )

        # Activo 2: Caja de Cambios Paletizada SIN PRECIO en Sucursal 32
        act2_id = uuid.uuid4()
        act2 = Activo_Inventariado(
            id_activo=act2_id,
            sku_qr_fisico="CAJ-5002-B2",
            id_categoria=2,
            id_estado=7,  # Paletizado
            id_sucursal_actual=32,
            id_vehiculo=veh2.id_vehiculo,
            ubicacion_galpon="1",
            ubicacion_pasillo="B",
            ubicacion_pallet="2",
            precio_referencia=0,
            version_lock=1,
            estado="Activo",
        )
        caj2 = Detalle_Caja_Cambio(
            id_activo=act2_id,
            transmision_tipo="Mecánica",
        )

        # Activo 3: Motor Disponible CON PRECIO en Sucursal 31
        act3_id = uuid.uuid4()
        act3 = Activo_Inventariado(
            id_activo=act3_id,
            sku_qr_fisico="MOT-5003-C3",
            id_categoria=1,
            id_estado=1,  # Disponible
            id_sucursal_actual=31,
            id_vehiculo=veh1.id_vehiculo,
            ubicacion_galpon="1",
            ubicacion_pasillo="C",
            ubicacion_pallet="8",
            precio_referencia=1450000,
            version_lock=1,
            estado="Activo",
        )

        db.add_all([act1, mot1, act2, caj2, act3])
        db.commit()

        yield {
            "gerente_id": gerente_id,
            "admin_id": admin_id,
            "vendedor_id": vendedor_id,
            "act1_id": act1_id,
            "act2_id": act2_id,
            "act3_id": act3_id,
        }
    finally:
        db.close()


@pytest.fixture
def auth_headers_gerente(db_maestro):
    token = create_access_token(data={"sub": str(db_maestro["gerente_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_admin(db_maestro):
    token = create_access_token(data={"sub": str(db_maestro["admin_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_vendedor(db_maestro):
    token = create_access_token(data={"sub": str(db_maestro["vendedor_id"])})
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS RBAC Y ACCESO
# ─────────────────────────────────────────────────────────────────────────────

def test_maestro_inventario_acceso_permitido_gerente(client, auth_headers_gerente):
    """Verifica que Gerente (id_rol = 4) pueda consultar el maestro de inventario."""
    res = client.get("/api/v1/inventario/maestro", headers=auth_headers_gerente)
    assert res.status_code == 200
    data = res.json()
    assert "items" in data
    assert "total_count" in data
    assert "pendientes_tasacion_count" in data
    assert data["total_count"] >= 3


def test_maestro_inventario_acceso_permitido_admin(client, auth_headers_admin):
    """Verifica que Administrador (id_rol = 5) pueda consultar el maestro de inventario."""
    res = client.get("/api/v1/inventario/maestro", headers=auth_headers_admin)
    assert res.status_code == 200


def test_maestro_inventario_bloqueo_vendedor(client, auth_headers_vendedor):
    """Verifica que Vendedor (id_rol = 2) no tenga acceso al maestro gerencial."""
    res = client.get("/api/v1/inventario/maestro", headers=auth_headers_vendedor)
    assert res.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS DE FILTROS Y CONSOLIDACIÓN MULTI-SUCURSAL
# ─────────────────────────────────────────────────────────────────────────────

def test_maestro_inventario_filtro_sucursal(client, auth_headers_gerente):
    """Verifica el filtrado por sucursal específica vs consolidado global."""
    res_suc31 = client.get("/api/v1/inventario/maestro?id_sucursal=31", headers=auth_headers_gerente)
    assert res_suc31.status_code == 200
    data_suc31 = res_suc31.json()
    for item in data_suc31["items"]:
        assert item["id_sucursal_actual"] == 31


def test_maestro_inventario_filtro_solo_sin_tasar(client, auth_headers_gerente, db_maestro):
    """Verifica que solo_sin_tasar=true retorne únicamente piezas paletizadas o con precio nulo/cero."""
    res = client.get("/api/v1/inventario/maestro?solo_sin_tasar=true", headers=auth_headers_gerente)
    assert res.status_code == 200
    data = res.json()
    assert data["total_count"] >= 2
    for item in data["items"]:
        assert item["precio_referencia"] is None or item["precio_referencia"] == 0 or item["estado_activo"] == "Paletizado"


def test_maestro_inventario_busqueda_q(client, auth_headers_gerente):
    """Verifica la búsqueda libre de texto por SKU y modelo."""
    res = client.get("/api/v1/inventario/maestro?q=MOT-5001", headers=auth_headers_gerente)
    assert res.status_code == 200
    data = res.json()
    assert data["total_count"] == 1
    assert data["items"][0]["sku_qr_fisico"] == "MOT-5001-A1"


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS DE FIJACIÓN DE PRECIOS Y TRANSICIÓN DE ESTADO (HU-5.3)
# ─────────────────────────────────────────────────────────────────────────────

def test_gerente_fijar_precio_activo_paletizado(client, auth_headers_gerente, db_maestro):
    """
    Verifica que el Gerente pueda tasar un activo paletizado:
    - Actualiza precio_referencia a un entero positivo.
    - Muta el estado a 'Disponible' (id_estado = 1).
    - Incrementa version_lock.
    - Actualiza fecha_actualizacion en UTC.
    """
    act1_id = str(db_maestro["act1_id"])
    payload = {"precio_referencia": 1850000}

    res = client.patch(f"/api/v1/inventario/{act1_id}/precio", json=payload, headers=auth_headers_gerente)
    assert res.status_code == 200
    data = res.json()
    assert data["precio_referencia"] == 1850000
    assert data["estado_activo"] == "Disponible"

    # Verificar directamente en la BD
    db = TestingSessionLocal()
    try:
        activo_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == uuid.UUID(act1_id)).first()
        assert activo_db.precio_referencia == 1850000
        assert activo_db.id_estado == 1
        assert activo_db.version_lock == 2
        assert activo_db.fecha_actualizacion is not None
    finally:
        db.close()


def test_gerente_fijar_precio_invalido_rechazado(client, auth_headers_gerente, db_maestro):
    """Verifica que un valor menor o igual a cero sea rechazado con 422 Unprocessable Entity."""
    act2_id = str(db_maestro["act2_id"])
    res = client.patch(f"/api/v1/inventario/{act2_id}/precio", json={"precio_referencia": 0}, headers=auth_headers_gerente)
    assert res.status_code == 422
