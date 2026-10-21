# test_jefe_ventas_precios.py
# Suite de pruebas automatizadas para HU-3.8: Panel de Jefe de Ventas y Asignación de Precios.

import uuid
import pytest

from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor, Detalle_Caja_Cambio
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    db = TestingSessionLocal()
    try:
        # Seed Geografía y Sucursal
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        db.add(c)
        suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 123", id_comuna=1)
        db.add(suc1)

        # Seed Roles
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_jefe = Rol(id_rol=6, nombre_rol="Jefe de Ventas")
        db.add_all([rol_vendedor, rol_jefe])

        # Usuarios
        jefe_id = uuid.uuid4()
        vendedor_id = uuid.uuid4()

        jefe_user = Usuario(
            id_usuario=jefe_id,
            id_rol=6,
            id_sucursal=1,
            rut_usuario="12.345.678-9",
            nombres="Jefe",
            apellidos="Comercial",
            email="jefeventas@cresal.cl",
            password_hash="hash",
            pin_acceso="6666",
            estado="Activo"
        )

        vendedor_user = Usuario(
            id_usuario=vendedor_id,
            id_rol=2,
            id_sucursal=1,
            rut_usuario="11.222.333-4",
            nombres="Vendedor",
            apellidos="Común",
            email="vendedor@cresal.cl",
            password_hash="hash",
            pin_acceso="1234",
            estado="Activo"
        )
        db.add_all([jefe_user, vendedor_user])

        # Categorías
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambio")
        db.add_all([cat_motor, cat_caja])

        # Estados de Activo (1: Disponible, 4: En Importación, 5: En Desarme, 6: Paletizado)
        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_import = Estado_Activo(id_estado=4, nombre_estado="En Importación")
        est_desarme = Estado_Activo(id_estado=5, nombre_estado="En Desarme")
        est_paletizado = Estado_Activo(id_estado=6, nombre_estado="Paletizado")
        db.add_all([est_disp, est_import, est_desarme, est_paletizado])

        # Vehículo
        v1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-2026-888",
            patente="HYUN99",
            marca="Hyundai",
            modelo="Accent",
            anio=2020,
            traccion="4x2",
            estado="Activo"
        )
        db.add(v1)

        # Activo 1: Paletizado, Con Ubicación, Sin Precio (precio_referencia = None) -> SÍ APARECE
        a1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=a1_id,
            sku_qr_fisico="MOT-HYU-ACC-001",
            id_categoria=1,
            id_estado=6,  # Paletizado
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=None,
            ubicacion_pasillo="P-03",
            ubicacion_pallet="PL-10",
            estado="Activo"
        )
        db.add(act1)

        motor1 = Detalle_Motor(
            id_activo=a1_id,
            numero_motor="G4LC123456",
            cilindrada="1.4L",
            combustible="Gasolina",
            transmision_tipo="Manual"
        )
        db.add(motor1)

        # Activo 2: Paletizado, Con Ubicación, Con precio = 0 -> SÍ APARECE
        a2_id = uuid.uuid4()
        act2 = Activo_Inventariado(
            id_activo=a2_id,
            sku_qr_fisico="CAJ-HYU-ACC-001",
            id_categoria=2,
            id_estado=6,  # Paletizado
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=0,
            ubicacion_pasillo="P-03",
            ubicacion_pallet="PL-11",
            estado="Activo"
        )
        db.add(act2)

        caja2 = Detalle_Caja_Cambio(
            id_activo=a2_id,
            transmision_tipo="Manual"
        )
        db.add(caja2)

        # Activo 3: Disponible (id_estado = 1), Con precio asignado ($450.000) -> NO APARECE
        a3_id = uuid.uuid4()
        act3 = Activo_Inventariado(
            id_activo=a3_id,
            sku_qr_fisico="MOT-HYU-ACC-002",
            id_categoria=1,
            id_estado=1,  # Disponible
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=450000,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PL-01",
            estado="Activo"
        )
        db.add(act3)

        # Activo 4: Paletizado pero SIN Ubicación Física (pasillo/pallet nulos) -> NO APARECE
        a4_id = uuid.uuid4()
        act4 = Activo_Inventariado(
            id_activo=a4_id,
            sku_qr_fisico="MOT-SIN-UBICACION",
            id_categoria=1,
            id_estado=6,  # Paletizado
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=None,
            ubicacion_pasillo=None,
            ubicacion_pallet=None,
            estado="Activo"
        )
        db.add(act4)

        # Activo 5: En Desarme (id_estado = 5) estado temprano -> NO APARECE
        a5_id = uuid.uuid4()
        act5 = Activo_Inventariado(
            id_activo=a5_id,
            sku_qr_fisico="MOT-EN-DESARME",
            id_categoria=1,
            id_estado=5,  # En Desarme
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=None,
            ubicacion_pasillo="P-04",
            ubicacion_pallet="PL-04",
            estado="Activo"
        )
        db.add(act5)

        # Activo 6: En Importación (id_estado = 4) estado temprano -> NO APARECE
        a6_id = uuid.uuid4()
        act6 = Activo_Inventariado(
            id_activo=a6_id,
            sku_qr_fisico="MOT-EN-IMPORTACION",
            id_categoria=1,
            id_estado=4,  # En Importación
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=None,
            ubicacion_pasillo="P-05",
            ubicacion_pallet="PL-05",
            estado="Activo"
        )
        db.add(act6)

        db.commit()

        yield {
            "jefe_user": jefe_user,
            "vendedor_user": vendedor_user,
            "activo_sin_precio": act1,
            "activo_precio_cero": act2,
            "activo_con_precio": act3,
            "activo_sin_ubicacion": act4,
            "activo_en_desarme": act5,
            "activo_en_importacion": act6,
            "vehiculo": v1,
        }

    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_headers_jefe(db_session):
    token = create_access_token(data={"sub": str(db_session["jefe_user"].id_usuario)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_vendedor(db_session):
    token = create_access_token(data={"sub": str(db_session["vendedor_user"].id_usuario)})
    return {"Authorization": f"Bearer {token}"}


# ── TEST 1: Control de Roles (RBAC) - Vendedor no puede acceder a pendientes ─
def test_pendientes_precio_acceso_denegado_para_rol_no_autorizado(client, auth_headers_vendedor):
    response = client.get("/api/v1/inventario/pendientes-precio", headers=auth_headers_vendedor)
    assert response.status_code == 403
    data = response.json()
    assert "Se requiere rol de Jefe de Ventas" in data["detail"]


# ── TEST 2: Jefe de Ventas consulta bandeja de pendientes de precio ──────────
def test_pendientes_precio_retorna_activos_paletizados_sin_precio_para_jefe_ventas(client, db_session, auth_headers_jefe):
    response = client.get("/api/v1/inventario/pendientes-precio", headers=auth_headers_jefe)
    assert response.status_code == 200

    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 2  # Solo activo 1 (None) y activo 2 (0) con ubicación física

    skus = [item["sku_qr_fisico"] for item in data]
    assert "MOT-HYU-ACC-001" in skus
    assert "CAJ-HYU-ACC-001" in skus
    assert "MOT-HYU-ACC-002" not in skus  # Ya tenía precio de $450.000
    assert "MOT-SIN-UBICACION" not in skus  # Sin pasillo/pallet
    assert "MOT-EN-DESARME" not in skus  # En Desarme (id_estado = 5)
    assert "MOT-EN-IMPORTACION" not in skus  # En Importación (id_estado = 4)

    # Verificar datos técnicos enriquecidos
    item_motor = next(item for item in data if item["sku_qr_fisico"] == "MOT-HYU-ACC-001")
    assert item_motor["marca"] == "Hyundai"
    assert item_motor["modelo"] == "Accent"
    assert item_motor["anio"] == 2020
    assert item_motor["cilindrada"] == "1.4L"
    assert item_motor["combustible"] == "Gasolina"
    assert item_motor["nombre_categoria"] == "Motor"
    assert item_motor["ubicacion_pasillo"] == "P-03"
    assert item_motor["ubicacion_pallet"] == "PL-10"
    assert item_motor["titulo_repuesto"] == "Motor - Hyundai Accent 2020"


# ── TEST 3: Verificación explícita de filtros de ubicación física y estados tempranos ──
def test_pendientes_precio_excluye_activos_sin_ubicacion_o_estados_tempranos(client, auth_headers_jefe):
    response = client.get("/api/v1/inventario/pendientes-precio", headers=auth_headers_jefe)
    assert response.status_code == 200

    skus = [item["sku_qr_fisico"] for item in response.json()]
    assert "MOT-SIN-UBICACION" not in skus
    assert "MOT-EN-DESARME" not in skus
    assert "MOT-EN-IMPORTACION" not in skus


# ── TEST 4: Asignar precio exitoso y transición automática a 'Disponible' (1) ────
def test_asignar_precio_exitoso_y_transicion_a_disponible(client, db_session, auth_headers_jefe):
    id_activo = str(db_session["activo_sin_precio"].id_activo)
    payload = {"precio_referencia": 580000}

    response = client.patch(
        f"/api/v1/inventario/{id_activo}/precio",
        json=payload,
        headers=auth_headers_jefe
    )
    assert response.status_code == 200

    data = response.json()
    assert data["id_activo"] == id_activo
    assert data["precio_referencia"] == 580000
    assert data["estado_activo"] == "Disponible"
    assert "asignado exitosamente" in data["mensaje"]

    # Verificar en Base de Datos
    db = TestingSessionLocal()
    try:
        activo_db = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_activo == uuid.UUID(id_activo)).first()
        assert activo_db.precio_referencia == 580000
        assert activo_db.id_estado == 1  # Disponible

        # Verificar que ya NO aparece en pendientes de precio
        response_pendientes = client.get("/api/v1/inventario/pendientes-precio", headers=auth_headers_jefe)
        assert response_pendientes.status_code == 200
        skus_pendientes = [i["sku_qr_fisico"] for i in response_pendientes.json()]
        assert "MOT-HYU-ACC-001" not in skus_pendientes
    finally:
        db.close()


# ── TEST 5: Asignar precio inválido (<= 0) retorna 422 ───────────────────────
def test_asignar_precio_invalido_menor_o_igual_a_cero_retorna_422(client, db_session, auth_headers_jefe):
    id_activo = str(db_session["activo_precio_cero"].id_activo)
    payload = {"precio_referencia": 0}

    response = client.patch(
        f"/api/v1/inventario/{id_activo}/precio",
        json=payload,
        headers=auth_headers_jefe
    )
    assert response.status_code == 422


# ── TEST 6: Asignar precio a activo inexistente retorna 404 ──────────────────
def test_asignar_precio_activo_inexistente_retorna_404(client, auth_headers_jefe):
    id_random = str(uuid.uuid4())
    payload = {"precio_referencia": 120000}

    response = client.patch(
        f"/api/v1/inventario/{id_random}/precio",
        json=payload,
        headers=auth_headers_jefe
    )
    assert response.status_code == 404


# ── TEST 7: Vendedor no tiene permiso para asignar precios (403) ────────────
def test_asignar_precio_acceso_denegado_para_vendedor(client, db_session, auth_headers_vendedor):
    id_activo = str(db_session["activo_precio_cero"].id_activo)
    payload = {"precio_referencia": 250000}

    response = client.patch(
        f"/api/v1/inventario/{id_activo}/precio",
        json=payload,
        headers=auth_headers_vendedor
    )
    assert response.status_code == 403
