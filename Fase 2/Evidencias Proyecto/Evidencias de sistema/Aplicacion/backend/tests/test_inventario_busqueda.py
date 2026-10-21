# test_inventario_busqueda.py
# Suite de pruebas automatizadas para SPEC-HU-TAREA-14: Búsqueda directa por N° de Ingreso

import uuid
import pytest
from datetime import datetime, timezone
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor, Detalle_Caja_Cambio
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def setup_inventario_test(setup_database):
    db = TestingSessionLocal()
    try:
        # 1. Región y Comuna
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
            suc = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Camino Internacional 4105", id_comuna=1)
            db.add(suc)
            db.flush()

        # 3. Roles
        rol_bodega = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_bodega:
            rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol_bodega)
            db.flush()

        # 4. Estados Activo
        estados_data = [
            (1, "Disponible"),
            (5, "Pendiente de Paletizado"),
            (7, "Paletizado"),
        ]
        for e_id, e_nom in estados_data:
            e = db.query(Estado_Activo).filter_by(id_estado=e_id).first()
            if not e:
                db.add(Estado_Activo(id_estado=e_id, nombre_estado=e_nom))
        db.flush()

        # 5. Categorías
        cat_motor = db.query(Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_motor)
            db.flush()

        cat_caja = db.query(Categoria_Activo).filter_by(id_categoria=2).first()
        if not cat_caja:
            cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambios")
            db.add(cat_caja)
            db.flush()

        # 6. Usuario Bodeguero
        user_bodega = db.query(Usuario).filter_by(rut_usuario="18888888-8").first()
        if not user_bodega:
            user_bodega = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="18888888-8",
                nombres="Pedro",
                apellidos="Bodeguero",
                email="pedro.bodega@cresal.cl",
                password_hash="mock_hash",
                id_rol=1,
                id_sucursal=1,
                pin_acceso="1234",
                estado="Activo",
            )
            db.add(user_bodega)
            db.flush()

        # 7. Vehículo 1: Pendiente de Paletizado (Folio 7001)
        veh_pendiente = db.query(Vehiculo_Origen).filter_by(numero_ingreso="7001").first()
        if not veh_pendiente:
            veh_pendiente = Vehiculo_Origen(
                id_vehiculo=uuid.uuid4(),
                numero_ingreso="7001",
                marca="Toyota",
                modelo="Corolla",
                anio=2021,
                patente="ABCD12",
                estado="Recepcionado",
            )
            db.add(veh_pendiente)
            db.flush()

            # Activo Motor pendiente de paletizado (id_estado=5, sin pasillo ni pallet)
            activo_motor = Activo_Inventariado(
                id_activo=uuid.uuid4(),
                sku_qr_fisico="QR-MOTO-7001",
                id_categoria=1,
                id_estado=5,
                id_sucursal_actual=1,
                id_vehiculo=veh_pendiente.id_vehiculo,
                ubicacion_pasillo=None,
                ubicacion_pallet=None,
                estado="Activo",
            )
            db.add(activo_motor)
            db.flush()

            det_motor = Detalle_Motor(
                id_activo=activo_motor.id_activo,
                numero_motor="1ZR-FE-9988",
                cilindrada="1.8L",
                combustible="Bencina",
                transmision_tipo="Manual",
            )
            db.add(det_motor)

        # 8. Vehículo 2: Ya Paletizado / Procesado (Folio 7002)
        veh_paletizado = db.query(Vehiculo_Origen).filter_by(numero_ingreso="7002").first()
        if not veh_paletizado:
            veh_paletizado = Vehiculo_Origen(
                id_vehiculo=uuid.uuid4(),
                numero_ingreso="7002",
                marca="Nissan",
                modelo="Sentra",
                anio=2020,
                patente="XYZW99",
                estado="Completado",
            )
            db.add(veh_paletizado)
            db.flush()

            # Activo Motor ya paletizado (id_estado=1, con pasillo y pallet asignados)
            activo_motor_listo = Activo_Inventariado(
                id_activo=uuid.uuid4(),
                sku_qr_fisico="QR-MOTO-7002",
                id_categoria=1,
                id_estado=1,
                id_sucursal_actual=1,
                id_vehiculo=veh_paletizado.id_vehiculo,
                ubicacion_pasillo="P-02",
                ubicacion_pallet="PAL-05",
                ubicacion_galpon="G-1",
                estado="Activo",
            )
            db.add(activo_motor_listo)
            db.flush()

        db.commit()

        token = create_access_token(data={"sub": str(user_bodega.id_usuario), "id_rol": 1, "id_sucursal": 1})
        headers = {"Authorization": f"Bearer {token}"}
        yield headers

    finally:
        db.close()


def test_busqueda_ingreso_exitoso_pendiente(client, setup_inventario_test):
    """
    Debe retornar 200 con los datos del vehículo y repuestos cuando
    el número de ingreso existe y tiene activos pendientes de paletizar.
    """
    headers = setup_inventario_test
    response = client.get("/api/v1/inventario/ingreso/7001", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["numero_ingreso"] == "7001"
    assert data["pendiente_paletizado"] is True
    assert data["vehiculo"]["marca"] == "Toyota"
    assert data["vehiculo"]["modelo"] == "Corolla"
    assert data["motor"]["numero_motor"] == "1ZR-FE-9988"
    assert data["motor"]["pendiente"] is True
    assert data["total_pendientes"] == 1


def test_busqueda_ingreso_no_encontrado_404(client, setup_inventario_test):
    """
    Debe retornar 404 con el mensaje exacto cuando el folio no existe en BD.
    """
    headers = setup_inventario_test
    response = client.get("/api/v1/inventario/ingreso/999999", headers=headers)
    assert response.status_code == 404
    data = response.json()
    assert data["detail"] == "Número de ingreso no encontrado en la base de datos."


def test_busqueda_ingreso_ya_paletizado_400(client, setup_inventario_test):
    """
    Debe retornar 400 con el mensaje exacto cuando el vehículo ya fue paletizado.
    """
    headers = setup_inventario_test
    response = client.get("/api/v1/inventario/ingreso/7002", headers=headers)
    assert response.status_code == 400
    data = response.json()
    assert data["detail"] == "El activo asociado a este número ya fue paletizado previamente o no requiere este flujo."
