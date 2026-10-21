# test_bandeja_precios_multimedia.py
# Suite de pruebas automatizadas para SPEC-HU-TAREA-15:
# Visualización de imágenes en bandeja de precios / tasación de Jefe de Ventas

import uuid
import pytest
from datetime import datetime, timezone
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Multimedia_Activo
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def setup_bandeja_precios_test(setup_database):
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
        rol_jefe = db.query(Rol).filter_by(id_rol=6).first()
        if not rol_jefe:
            rol_jefe = Rol(id_rol=6, nombre_rol="Jefe de Ventas")
            db.add(rol_jefe)
            db.flush()

        rol_bodega = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_bodega:
            rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol_bodega)
            db.flush()

        # 4. Estados Activo
        estados_data = [
            (1, "Disponible"),
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

        # 6. Usuario Jefe de Ventas (rol 6)
        user_jefe = db.query(Usuario).filter_by(rut_usuario="19999999-9").first()
        if not user_jefe:
            user_jefe = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="19999999-9",
                nombres="Rodrigo",
                apellidos="Jefe Ventas",
                email="rodrigo.jefe@cresal.cl",
                password_hash="mock_hash",
                id_rol=6,
                id_sucursal=1,
                pin_acceso="6666",
                estado="Activo",
            )
            db.add(user_jefe)
            db.flush()

        # 7. Usuario Bodeguero (rol 1) no autorizado para fijar precios
        user_bodega = db.query(Usuario).filter_by(rut_usuario="14444444-4").first()
        if not user_bodega:
            user_bodega = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="14444444-4",
                nombres="Bodeguero",
                apellidos="Sin Permiso",
                email="bodega.noperm@cresal.cl",
                password_hash="mock_hash",
                id_rol=1,
                id_sucursal=1,
                pin_acceso="1111",
                estado="Activo",
            )
            db.add(user_bodega)
            db.flush()

        # 8. Vehículo y Activos para Bandeja
        vehiculo = db.query(Vehiculo_Origen).filter_by(numero_ingreso="8001").first()
        if not vehiculo:
            vehiculo = Vehiculo_Origen(
                id_vehiculo=uuid.uuid4(),
                numero_ingreso="8001",
                marca="Honda",
                modelo="Civic",
                anio=2022,
                patente="HOND22",
                estado="Procesado",
            )
            db.add(vehiculo)
            db.flush()

        # Activo con Fotografías (id_estado=7 Paletizado, precio=0 o None, ubicacion asignada)
        activo_con_fotos = db.query(Activo_Inventariado).filter_by(sku_qr_fisico="QR-MOTO-8001-FOTOS").first()
        if not activo_con_fotos:
            activo_con_fotos = Activo_Inventariado(
                id_activo=uuid.uuid4(),
                sku_qr_fisico="QR-MOTO-8001-FOTOS",
                id_categoria=1,
                id_estado=7,
                id_sucursal_actual=1,
                id_vehiculo=vehiculo.id_vehiculo,
                ubicacion_pasillo="P-01",
                ubicacion_pallet="PAL-01",
                precio_referencia=0,
                estado="Activo",
            )
            db.add(activo_con_fotos)
            db.flush()

            # Añadir 2 fotografías
            foto1 = Multimedia_Activo(
                id_multimedia=uuid.uuid4(),
                id_activo=activo_con_fotos.id_activo,
                url_storage="https://supabase.co/storage/v1/object/public/multimedia-activos/8001/moto_1.jpg",
                tipo_archivo="imagen",
            )
            foto2 = Multimedia_Activo(
                id_multimedia=uuid.uuid4(),
                id_activo=activo_con_fotos.id_activo,
                url_storage="https://supabase.co/storage/v1/object/public/multimedia-activos/8001/moto_2.jpg",
                tipo_archivo="imagen",
            )
            db.add(foto1)
            db.add(foto2)

        # Activo sin Fotografías
        activo_sin_fotos = db.query(Activo_Inventariado).filter_by(sku_qr_fisico="QR-MOTO-8001-SINFOTOS").first()
        if not activo_sin_fotos:
            activo_sin_fotos = Activo_Inventariado(
                id_activo=uuid.uuid4(),
                sku_qr_fisico="QR-MOTO-8001-SINFOTOS",
                id_categoria=1,
                id_estado=7,
                id_sucursal_actual=1,
                id_vehiculo=vehiculo.id_vehiculo,
                ubicacion_pasillo="P-01",
                ubicacion_pallet="PAL-02",
                precio_referencia=None,
                estado="Activo",
            )
            db.add(activo_sin_fotos)

        db.commit()

        token_jefe = create_access_token(data={"sub": str(user_jefe.id_usuario), "id_rol": 6, "id_sucursal": 1})
        token_bodega = create_access_token(data={"sub": str(user_bodega.id_usuario), "id_rol": 1, "id_sucursal": 1})

        yield {
            "headers_jefe": {"Authorization": f"Bearer {token_jefe}"},
            "headers_bodega": {"Authorization": f"Bearer {token_bodega}"},
        }
    finally:
        db.close()


def test_bandeja_precios_retorna_fotografias_multimedia(client, setup_bandeja_precios_test):
    """
    Verifica que la bandeja de precios retorne el arreglo 'fotografias'
    con las URLs registradas en Multimedia_Activo para activos que las posean.
    """
    headers = setup_bandeja_precios_test["headers_jefe"]
    response = client.get("/api/v1/ventas/bandeja-precios", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 2

    item_con_fotos = next((x for x in data if x["sku_qr_fisico"] == "QR-MOTO-8001-FOTOS"), None)
    assert item_con_fotos is not None
    assert "fotografias" in item_con_fotos
    assert len(item_con_fotos["fotografias"]) == 2
    assert "moto_1.jpg" in item_con_fotos["fotografias"][0]
    assert "moto_2.jpg" in item_con_fotos["fotografias"][1]


def test_bandeja_precios_activo_sin_fotos_retorna_lista_vacia(client, setup_bandeja_precios_test):
    """
    Verifica que un activo sin registros en Multimedia_Activo retorne 'fotografias': [].
    """
    headers = setup_bandeja_precios_test["headers_jefe"]
    response = client.get("/api/v1/inventario/pendientes-precio", headers=headers)
    assert response.status_code == 200
    data = response.json()

    item_sin_fotos = next((x for x in data if x["sku_qr_fisico"] == "QR-MOTO-8001-SINFOTOS"), None)
    assert item_sin_fotos is not None
    assert "fotografias" in item_sin_fotos
    assert item_sin_fotos["fotografias"] == []


def test_bandeja_precios_requiere_rol_jefe_ventas_403(client, setup_bandeja_precios_test):
    """
    Verifica que un rol no autorizado (ej: Bodeguero rol 1) sea rechazado con 403 Forbidden.
    """
    headers = setup_bandeja_precios_test["headers_bodega"]
    response = client.get("/api/v1/ventas/bandeja-precios", headers=headers)
    assert response.status_code == 403
