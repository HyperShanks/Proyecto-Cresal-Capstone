# backend/tests/test_gerencia_backorders.py
"""
Suite de Pruebas Automatizadas para HU-5.4:
Acoplamiento de Tasación de Vehículos para Desarme y Monitoreo Centralizado de Backorders.
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
    Cliente,
    Reservas_Backorder,
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_backorders(setup_database):
    db = TestingSessionLocal()
    try:
        # Geografía y Sucursales
        r = Region(id_region=40, nombre_region="Metropolitana")
        db.add(r)
        c1 = Comuna(id_comuna=401, nombre_comuna="Santiago Centro", id_region=40)
        c2 = Comuna(id_comuna=402, nombre_comuna="San Bernardo", id_region=40)
        db.add_all([c1, c2])

        suc1 = Sucursal(id_sucursal=41, nombre_sucursal="Sucursal 10 de Julio", direccion="Av. 10 de Julio 1200", id_comuna=401)
        suc2 = Sucursal(id_sucursal=42, nombre_sucursal="Patio San Bernardo", direccion="Av. Portales 800", id_comuna=402)
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
            id_sucursal=41,
            rut_usuario="14.333.444-5",
            nombres="Carlos",
            apellidos="Gerente Backorders",
            email="gerente.backorders@cresal.cl",
            password_hash="hash",
            pin_acceso="1234",
            estado="Activo",
        )
        admin = Usuario(
            id_usuario=admin_id,
            id_rol=5,
            id_sucursal=41,
            rut_usuario="15.444.555-6",
            nombres="Admin",
            apellidos="Backorders",
            email="admin.backorders@cresal.cl",
            password_hash="hash",
            pin_acceso="5555",
            estado="Activo",
        )
        vendedor = Usuario(
            id_usuario=vendedor_id,
            id_rol=2,
            id_sucursal=41,
            rut_usuario="16.555.666-7",
            nombres="Pedro",
            apellidos="Ventas",
            email="pedro.ventas@cresal.cl",
            password_hash="hash",
            pin_acceso="2222",
            estado="Activo",
        )
        db.add_all([gerente, admin, vendedor])

        # Clientes
        cli1_id = uuid.uuid4()
        cli1 = Cliente(
            id_cliente=cli1_id,
            rut_cliente="18.111.222-3",
            nombres="Juan",
            apellidos="Pérez",
            correo="juan.perez@email.com",
            telefono="+56 9 8765 4321",
            id_comuna=401,
            estado="Activo",
        )
        cli2_id = uuid.uuid4()
        cli2 = Cliente(
            id_cliente=cli2_id,
            rut_cliente="19.222.333-4",
            nombres="María",
            apellidos="González",
            correo="maria.gonzalez@email.com",
            telefono="+56 9 1234 5678",
            id_comuna=402,
            estado="Activo",
        )
        db.add_all([cli1, cli2])

        # Categorías y Estados
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motores")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Cajas de Cambio")
        db.add_all([cat_motor, cat_caja])

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        db.add(est_disp)

        # Vehículo y Activo físico asignado a una reserva
        veh1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-601",
            marca="Nissan",
            modelo="Terrano",
            anio=2018,
            traccion="4x4",
        )
        db.add(veh1)

        act_asignado_id = uuid.uuid4()
        act_asignado = Activo_Inventariado(
            id_activo=act_asignado_id,
            sku_qr_fisico="MOT-6001-A1",
            id_categoria=1,
            id_estado=1,
            id_sucursal_actual=41,
            id_vehiculo=veh1.id_vehiculo,
            precio_referencia=950000,
            version_lock=1,
            estado="Activo",
        )
        db.add(act_asignado)

        # 4 Reservas Backorder para probar diversos escenarios:
        # Res 1: Sucursal 41, Pendiente, SIN pieza física asignada
        res1_id = uuid.uuid4()
        res1 = Reservas_Backorder(
            id_reserva=res1_id,
            id_cliente=cli1_id,
            id_vendedor=vendedor_id,
            id_sucursal_registro=41,
            id_categoria_requerida=1,
            marca_requerida="Toyota",
            modelo_requerido="Yaris",
            anio_requerido=2017,
            combustible_requerido="Bencina",
            transmision_requerida="Mecánica",
            precio_acordado=850000,
            monto_abonado=250000,
            id_activo_asignado=None,
            estado_reserva="Pendiente",
            fecha_creacion=datetime.now(timezone.utc),
        )

        # Res 2: Sucursal 41, Confirmada, CON pieza física asignada
        res2_id = uuid.uuid4()
        res2 = Reservas_Backorder(
            id_reserva=res2_id,
            id_cliente=cli2_id,
            id_vendedor=vendedor_id,
            id_sucursal_registro=41,
            id_categoria_requerida=1,
            marca_requerida="Nissan",
            modelo_requerido="Terrano",
            anio_requerido=2018,
            combustible_requerido="Diesel",
            transmision_requerida="Manual",
            precio_acordado=950000,
            monto_abonado=300000,
            id_activo_asignado=act_asignado_id,
            estado_reserva="Confirmada",
            fecha_creacion=datetime.now(timezone.utc),
        )

        # Res 3: Sucursal 42, Completada (ya liquidada), sin activo asignado actualmente
        res3_id = uuid.uuid4()
        res3 = Reservas_Backorder(
            id_reserva=res3_id,
            id_cliente=cli1_id,
            id_vendedor=vendedor_id,
            id_sucursal_registro=42,
            id_categoria_requerida=2,
            marca_requerida="Chevrolet",
            modelo_requerido="Sail",
            anio_requerido=2016,
            combustible_requerido="Bencina",
            transmision_requerida="Mecánica",
            precio_acordado=400000,
            monto_abonado=400000,
            id_activo_asignado=None,
            estado_reserva="Completada",
            fecha_creacion=datetime.now(timezone.utc),
        )

        # Res 4: Sucursal 42, Anulada
        res4_id = uuid.uuid4()
        res4 = Reservas_Backorder(
            id_reserva=res4_id,
            id_cliente=cli2_id,
            id_vendedor=vendedor_id,
            id_sucursal_registro=42,
            id_categoria_requerida=2,
            marca_requerida="Suzuki",
            modelo_requerido="Swift",
            anio_requerido=2020,
            combustible_requerido="Bencina",
            transmision_requerida="Automática",
            precio_acordado=600000,
            monto_abonado=100000,
            id_activo_asignado=None,
            estado_reserva="Anulada",
            fecha_creacion=datetime.now(timezone.utc),
        )

        db.add_all([res1, res2, res3, res4])
        db.commit()

        yield {
            "gerente_id": gerente_id,
            "admin_id": admin_id,
            "vendedor_id": vendedor_id,
            "res1_id": res1_id,
            "res2_id": res2_id,
            "res3_id": res3_id,
            "res4_id": res4_id,
            "act_asignado_id": act_asignado_id,
        }
    finally:
        db.close()


@pytest.fixture
def auth_headers_gerente(db_backorders):
    token = create_access_token(data={"sub": str(db_backorders["gerente_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_admin(db_backorders):
    token = create_access_token(data={"sub": str(db_backorders["admin_id"])})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_vendedor(db_backorders):
    token = create_access_token(data={"sub": str(db_backorders["vendedor_id"])})
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS RBAC
# ─────────────────────────────────────────────────────────────────────────────

def test_backorders_acceso_permitido_gerente(client, auth_headers_gerente):
    """Verifica que Gerente (id_rol = 4) acceda exitosamente a la lista y KPIs."""
    res_list = client.get("/api/v1/gerencia/backorders", headers=auth_headers_gerente)
    assert res_list.status_code == 200
    data_list = res_list.json()
    assert "items" in data_list
    assert "total_count" in data_list
    assert "total_recaudado_senas" in data_list
    assert data_list["total_count"] >= 4

    res_kpis = client.get("/api/v1/gerencia/backorders/kpis", headers=auth_headers_gerente)
    assert res_kpis.status_code == 200
    data_kpis = res_kpis.json()
    assert "total_activos" in data_kpis
    assert "capital_retenido" in data_kpis
    assert "listos_para_liquidar" in data_kpis


def test_backorders_acceso_permitido_admin(client, auth_headers_admin):
    """Verifica que Administrador (id_rol = 5) tenga acceso."""
    res = client.get("/api/v1/gerencia/backorders", headers=auth_headers_admin)
    assert res.status_code == 200


def test_backorders_bloqueo_vendedor(client, auth_headers_vendedor):
    """Verifica que Vendedor (id_rol = 2) no tenga acceso (403 Forbidden)."""
    res = client.get("/api/v1/gerencia/backorders", headers=auth_headers_vendedor)
    assert res.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS DE KPIs Y BALANCES ECONÓMICOS
# ─────────────────────────────────────────────────────────────────────────────

def test_backorders_kpis_calculos_precisos(client, auth_headers_gerente, db_backorders):
    """
    Verifica que los KPIs de backorders calculen:
    - total_activos: Reservas en Pendiente o Confirmada (Res1 + Res2 = 2)
    - capital_retenido: Suma de monto_abonado de activas (250.000 + 300.000 = 550.000)
    - listos_para_liquidar: Activas con id_activo_asignado != null (Res2 = 1)
    """
    res = client.get("/api/v1/gerencia/backorders/kpis?id_sucursal=41", headers=auth_headers_gerente)
    assert res.status_code == 200
    kpis = res.json()
    assert kpis["total_activos"] == 2
    assert kpis["capital_retenido"] == 550000
    assert kpis["listos_para_liquidar"] == 1


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS DE FILTROS Y BÚSQUEDA PREDICTIVA
# ─────────────────────────────────────────────────────────────────────────────

def test_backorders_filtro_sucursal_y_estado(client, auth_headers_gerente):
    """Verifica el filtrado por sucursal y por estado de reserva."""
    # Filtrar por Sucursal 42
    res_suc42 = client.get("/api/v1/gerencia/backorders?id_sucursal=42", headers=auth_headers_gerente)
    assert res_suc42.status_code == 200
    data_suc42 = res_suc42.json()
    assert data_suc42["total_count"] == 2
    for item in data_suc42["items"]:
        assert item["id_sucursal"] == 42

    # Filtrar por Estado Confirmada
    res_conf = client.get("/api/v1/gerencia/backorders?estado=Confirmada", headers=auth_headers_gerente)
    assert res_conf.status_code == 200
    data_conf = res_conf.json()
    assert all(item["estado_reserva"] == "Confirmada" for item in data_conf["items"])


def test_backorders_busqueda_predictiva(client, auth_headers_gerente):
    """Verifica la búsqueda por texto (q) en marca, modelo, cliente o vendedor."""
    # Búsqueda por modelo 'Terrano'
    res_terrano = client.get("/api/v1/gerencia/backorders?q=Terrano", headers=auth_headers_gerente)
    assert res_terrano.status_code == 200
    data = res_terrano.json()
    assert len(data["items"]) >= 1
    assert any("Terrano" in item["modelo_requerido"] for item in data["items"])

    # Búsqueda por cliente 'Pérez'
    res_perez = client.get("/api/v1/gerencia/backorders?q=Pérez", headers=auth_headers_gerente)
    assert res_perez.status_code == 200
    data_perez = res_perez.json()
    assert any("Pérez" in item["cliente_nombre"] for item in data_perez["items"])


# ─────────────────────────────────────────────────────────────────────────────
# PRUEBAS DE TRAZABILIDAD Y MATRICES DE ASIGNACIÓN FÍSICA
# ─────────────────────────────────────────────────────────────────────────────

def test_backorders_trazabilidad_activo_asignado(client, auth_headers_gerente, db_backorders):
    """
    Verifica que la reserva vinculada a una pieza física retorne activo_asignado_sku
    y que saldo_pendiente = max(0, precio_acordado - monto_abonado).
    """
    res = client.get("/api/v1/gerencia/backorders?estado=Confirmada", headers=auth_headers_gerente)
    assert res.status_code == 200
    items = res.json()["items"]
    res_confirmada = next((item for item in items if item["id_reserva"] == str(db_backorders["res2_id"])), None)
    assert res_confirmada is not None
    assert res_confirmada["activo_asignado_sku"] == "MOT-6001-A1"
    assert res_confirmada["precio_acordado"] == 950000
    assert res_confirmada["monto_abonado"] == 300000
    assert res_confirmada["saldo_pendiente"] == 650000
    assert res_confirmada["folio"].startswith("RES-")
