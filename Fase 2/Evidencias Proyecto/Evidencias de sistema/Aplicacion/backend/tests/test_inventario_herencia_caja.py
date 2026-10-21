# test_inventario_herencia_caja.py
# Suite de pruebas automatizadas para SPEC-HU-TAREA-17:
# Visualización Compartida de Atributos Técnicos entre Motor y Caja de Cambios

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
def setup_herencia_test(setup_database):
    db = TestingSessionLocal()
    try:
        # 1. Región, Comuna y Sucursal
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

        suc = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc:
            suc = Sucursal(
                id_sucursal=1,
                nombre_sucursal="Casa Matriz - Viña",
                direccion="Camino Internacional 4105",
                id_comuna=1,
            )
            db.add(suc)
            db.flush()

        # 2. Rol
        rol_bodega = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_bodega:
            rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol_bodega)
            db.flush()

        # 3. Estados de Activo
        estados_requeridos = [(1, "Disponible"), (7, "Paletizado")]
        for e_id, e_nom in estados_requeridos:
            e = db.query(Estado_Activo).filter_by(nombre_estado=e_nom).first()
            if not e:
                db.add(Estado_Activo(id_estado=e_id, nombre_estado=e_nom))
        db.flush()

        # 4. Categorías de Activo
        cat_motor = db.query(Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_motor)

        cat_caja = db.query(Categoria_Activo).filter_by(id_categoria=2).first()
        if not cat_caja:
            cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambios")
            db.add(cat_caja)
        db.flush()

        # 5. Usuario
        user = db.query(Usuario).filter_by(rut_usuario="17777777-7").first()
        if not user:
            user = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="17777777-7",
                nombres="Carlos",
                apellidos="Operario",
                email="carlos.operario@cresal.cl",
                password_hash="mock_hash",
                id_rol=1,
                id_sucursal=1,
                pin_acceso="5555",
                estado="Activo",
            )
            db.add(user)
            db.flush()

        # 6. Vehículo Donante con Tracción 4x4
        vehiculo = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="8801",
            marca="Toyota",
            modelo="Hilux",
            anio=2022,
            patente="HHLL22",
            traccion="4x4",
            estado="Completado",
        )
        db.add(vehiculo)
        db.flush()

        # 7. Activo Motor asociado al vehículo
        id_motor = uuid.uuid4()
        activo_motor = Activo_Inventariado(
            id_activo=id_motor,
            sku_qr_fisico="QR-MOT-8801",
            id_categoria=1,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=vehiculo.id_vehiculo,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PAL-10",
            ubicacion_galpon="G-1",
            precio_referencia=2500000,
            estado="Activo",
        )
        db.add(activo_motor)
        db.flush()

        detalle_motor = Detalle_Motor(
            id_activo=id_motor,
            numero_motor="1GD-998877",
            cilindrada="2.8L",
            combustible="Diesel",
            transmision_tipo="Manual",
        )
        db.add(detalle_motor)

        # 8. Activo Caja de Cambios asociado al MISMO vehículo donante
        id_caja = uuid.uuid4()
        activo_caja = Activo_Inventariado(
            id_activo=id_caja,
            sku_qr_fisico="QR-CAJ-8801",
            id_categoria=2,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=vehiculo.id_vehiculo,
            ubicacion_pasillo="P-01",
            ubicacion_pallet="PAL-11",
            ubicacion_galpon="G-1",
            precio_referencia=850000,
            estado="Activo",
        )
        db.add(activo_caja)
        db.flush()

        detalle_caja = Detalle_Caja_Cambio(
            id_activo=id_caja,
            transmision_tipo="Manual 6V",
        )
        db.add(detalle_caja)

        # 9. Activo Caja Huérfana (sin vehículo ni motor) para casos borde
        id_caja_huerfana = uuid.uuid4()
        activo_caja_huerfana = Activo_Inventariado(
            id_activo=id_caja_huerfana,
            sku_qr_fisico="QR-CAJ-HUERFANA",
            id_categoria=2,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=None,
            ubicacion_pasillo="P-99",
            ubicacion_pallet="PAL-99",
            precio_referencia=400000,
            estado="Activo",
        )
        db.add(activo_caja_huerfana)
        db.flush()

        detalle_caja_huerfana = Detalle_Caja_Cambio(
            id_activo=id_caja_huerfana,
            transmision_tipo="Automática",
        )
        db.add(detalle_caja_huerfana)

        db.commit()

        token = create_access_token(
            data={"sub": str(user.id_usuario), "id_rol": 1, "id_sucursal": 1}
        )
        headers = {"Authorization": f"Bearer {token}"}

        yield {
            "headers": headers,
            "id_motor": str(id_motor),
            "id_caja": str(id_caja),
            "id_caja_huerfana": str(id_caja_huerfana),
            "id_vehiculo": str(vehiculo.id_vehiculo),
        }
    finally:
        db.close()


def test_detalle_caja_hereda_cilindrada_y_combustible_y_traccion(client, setup_herencia_test):
    """
    SPEC-HU-TAREA-17 (Tarea 1):
    Al consultar GET /api/v1/inventario/{id_caja}, la Caja de Cambios debe heredar
    cilindrada y combustible del motor donante, tracción del vehículo origen,
    y numero_motor debe ser None (exclusivo para Motor).
    """
    headers = setup_herencia_test["headers"]
    id_caja = setup_herencia_test["id_caja"]

    response = client.get(f"/api/v1/inventario/{id_caja}", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert data["id_activo"] == id_caja
    assert data["id_categoria"] == 2
    assert data["nombre_categoria"] == "Caja de Cambios"

    # Herencia de especificaciones del motor donante
    assert data["cilindrada"] == "2.8L"
    assert data["combustible"] == "Diesel"

    # Atributo del vehículo de origen
    assert data["traccion"] == "4x4"

    # Atributo propio de la caja
    assert data["transmision_tipo"] == "Manual 6V"

    # Exclusividad: numero_motor NO debe poblarse para caja de cambios
    assert data["numero_motor"] is None


def test_detalle_motor_conserva_numero_motor_exclusivo(client, setup_herencia_test):
    """
    SPEC-HU-TAREA-17:
    El activo Motor debe conservar su numero_motor propio, además de cilindrada,
    combustible y tracción.
    """
    headers = setup_herencia_test["headers"]
    id_motor = setup_herencia_test["id_motor"]

    response = client.get(f"/api/v1/inventario/{id_motor}", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert data["id_activo"] == id_motor
    assert data["id_categoria"] == 1
    assert data["numero_motor"] == "1GD-998877"
    assert data["cilindrada"] == "2.8L"
    assert data["combustible"] == "Diesel"
    assert data["traccion"] == "4x4"


def test_buscar_inventario_herencia_caja(client, setup_herencia_test):
    """
    SPEC-HU-TAREA-17 (Tarea 2):
    Al consultar GET /api/v1/inventario/buscar, las Cajas de Cambios deben reflejar
    la cilindrada, combustible y tracción heredadas en el listado.
    """
    headers = setup_herencia_test["headers"]
    id_caja = setup_herencia_test["id_caja"]

    response = client.get("/api/v1/inventario/buscar?q=Hilux", headers=headers)
    assert response.status_code == 200

    data = response.json()
    caja_encontrada = next((item for item in data if item["id_activo"] == id_caja), None)
    assert caja_encontrada is not None

    # Verificación de herencia en búsqueda
    assert caja_encontrada["cilindrada"] == "2.8L"
    assert caja_encontrada["combustible"] == "Diesel"
    assert caja_encontrada["traccion"] == "4x4"
    assert caja_encontrada["transmision"] == "Manual 6V"
    assert caja_encontrada["numero_motor"] is None


def test_caja_huerfana_sin_vehiculo_no_rompe(client, setup_herencia_test):
    """
    Caso de borde: Una caja de cambios sin id_vehiculo debe devolver N/A o None
    de forma segura sin generar excepciones 500.
    """
    headers = setup_herencia_test["headers"]
    id_caja_huerfana = setup_herencia_test["id_caja_huerfana"]

    response = client.get(f"/api/v1/inventario/{id_caja_huerfana}", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert data["id_activo"] == id_caja_huerfana
    assert data["cilindrada"] is None
    assert data["combustible"] is None
    assert data["numero_motor"] is None


def test_tareas_pendientes_bodega_hereda_atributos_caja(client, setup_herencia_test):
    """
    Verifica que en GET /api/v1/bodega/tareas-pendientes, la etiqueta_data de una
    Caja de Cambios herede cilindrada, combustible y tracción del motor hermano,
    manteniendo numero_motor en None.
    """
    headers = setup_herencia_test["headers"]
    id_caja = setup_herencia_test["id_caja"]

    response = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=headers)
    assert response.status_code == 200

    tareas = response.json()
    tarea_caja = next((t for t in tareas if t.get("id_activo") == id_caja), None)
    assert tarea_caja is not None, "La tarea de impresión para la caja debe estar presente"

    etiqueta = tarea_caja.get("etiqueta_data")
    assert etiqueta is not None, "La tarea debe incluir etiqueta_data"
    assert etiqueta["cilindrada"] == "2.8L"
    assert etiqueta["combustible"] == "Diesel"
    assert etiqueta["traccion"] == "4x4"
    assert etiqueta["transmision"] == "Manual 6V"
    assert etiqueta["numero_motor"] is None

