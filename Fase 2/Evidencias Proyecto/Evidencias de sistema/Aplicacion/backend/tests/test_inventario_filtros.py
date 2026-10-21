# test_inventario_filtros.py
# Pruebas automatizadas para SPEC-HU-TAREA-16: Filtros de Estado y Ubicación en Inventario

import uuid
import pytest
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Detalle_Motor
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def setup_filtros_inventario_test(setup_database):
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
            suc = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Camino Internacional 4105", id_comuna=1)
            db.add(suc)
            db.flush()

        # 2. Rol Bodeguero
        rol_bodega = db.query(Rol).filter_by(id_rol=1).first()
        if not rol_bodega:
            rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol_bodega)
            db.flush()

        # 3. Estados Activo Operativos Clave
        estados_requeridos = [
            (1, "Disponible"),
            (2, "Reservado"),
            (3, "Vendido"),
            (7, "Paletizado"),
        ]
        for e_id, e_nom in estados_requeridos:
            e = db.query(Estado_Activo).filter_by(nombre_estado=e_nom).first()
            if not e:
                e = db.query(Estado_Activo).filter_by(id_estado=e_id).first()
                if not e:
                    db.add(Estado_Activo(id_estado=e_id, nombre_estado=e_nom))
                else:
                    e.nombre_estado = e_nom
        db.flush()

        # 4. Categoría
        cat_motor = db.query(Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_motor)
            db.flush()

        # 5. Usuario Bodeguero
        user_bodega = db.query(Usuario).filter_by(rut_usuario="18999999-9").first()
        if not user_bodega:
            user_bodega = Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="18999999-9",
                nombres="Carlos",
                apellidos="Operador",
                email="carlos.operador@cresal.cl",
                password_hash="mock_hash",
                id_rol=1,
                id_sucursal=1,
                pin_acceso="1234",
                estado="Activo",
            )
            db.add(user_bodega)
            db.flush()

        # 6. Vehículo Base de prueba
        veh_base = db.query(Vehiculo_Origen).filter_by(numero_ingreso="9901").first()
        if not veh_base:
            veh_base = Vehiculo_Origen(
                id_vehiculo=uuid.uuid4(),
                numero_ingreso="9901",
                marca="Nissan",
                modelo="Qashqai",
                anio=2022,
                patente="FILT99",
                estado="Recepcionado",
            )
            db.add(veh_base)
            db.flush()

        # Obtener IDs reales de los estados
        est_disp = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Disponible").first()
        est_res = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Reservado").first()
        est_ven = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Vendido").first()
        est_pal = db.query(Estado_Activo).filter(Estado_Activo.nombre_estado == "Paletizado").first()

        # 7. Crear Activos en cada uno de los 4 estados
        activos_data = [
            ("SKU-FILT-DISP-01", est_disp.id_estado, "Galpón A", "P-01", "PL-01"),
            ("SKU-FILT-RES-02", est_res.id_estado, "Galpón B", "P-02", "PL-02"),
            ("SKU-FILT-VEND-03", est_ven.id_estado, "Galpón C", "P-03", "PL-03"),
            ("SKU-FILT-PAL-04", est_pal.id_estado, "Galpón D", "P-04", "PL-04"),
            ("SKU-FILT-HUERF-05", est_disp.id_estado, None, None, None),  # Huérfano de ubicación
        ]

        for sku, id_est, galp, pas, pall in activos_data:
            act = db.query(Activo_Inventariado).filter_by(sku_qr_fisico=sku).first()
            if not act:
                act = Activo_Inventariado(
                    id_activo=uuid.uuid4(),
                    sku_qr_fisico=sku,
                    id_categoria=1,
                    id_estado=id_est,
                    id_sucursal_actual=1,
                    id_vehiculo=veh_base.id_vehiculo,
                    ubicacion_galpon=galp,
                    ubicacion_pasillo=pas,
                    ubicacion_pallet=pall,
                    estado="Activo",
                )
                db.add(act)
        db.commit()

        token = create_access_token(data={"sub": str(user_bodega.id_usuario), "rol": "Bodeguero", "id_rol": 1})
        return {"headers": {"Authorization": f"Bearer {token}"}}
    finally:
        db.close()


def test_inventario_filtro_disponibles(client, setup_filtros_inventario_test):
    """Verifica que ?estado=Disponibles filtre solo activos en estado Disponible."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT&estado=Disponibles", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 1
    for item in data:
        assert item["estado"].upper() == "DISPONIBLE"
        assert item["sku"] in ["SKU-FILT-DISP-01", "SKU-FILT-HUERF-05"]


def test_inventario_filtro_reservados(client, setup_filtros_inventario_test):
    """Verifica que ?estado=Reservados filtre solo activos en estado Reservado."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT&estado=Reservados", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 1
    for item in data:
        assert item["estado"].upper() == "RESERVADO"
        assert item["sku"] == "SKU-FILT-RES-02"


def test_inventario_filtro_vendidos_excluido_de_bodega(client, setup_filtros_inventario_test):
    """Verifica que el estado Vendidos esté excluido del inventario operativo de bodega."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT&estado=Vendidos", headers=headers)

    assert response.status_code == 200
    data = response.json()
    # Las piezas vendidas no forman parte del stock operativo de bodega
    assert len(data) == 0


def test_inventario_filtro_paletizados(client, setup_filtros_inventario_test):
    """Verifica que ?estado=Paletizados filtre solo activos en estado Paletizado."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT&estado=Paletizados", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 1
    for item in data:
        assert item["estado"].upper() == "PALETIZADO"
        assert item["sku"] == "SKU-FILT-PAL-04"


def test_inventario_filtro_todos(client, setup_filtros_inventario_test):
    """Verifica que ?estado=Todos incluya repuestos físicos en bodega (Disponibles, Reservados, Paletizados) y excluya Vendidos."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT&estado=Todos", headers=headers)

    assert response.status_code == 200
    data = response.json()
    skus_encontrados = {item["sku"] for item in data}
    assert "SKU-FILT-DISP-01" in skus_encontrados
    assert "SKU-FILT-RES-02" in skus_encontrados
    assert "SKU-FILT-PAL-04" in skus_encontrados
    assert "SKU-FILT-VEND-03" not in skus_encontrados


def test_inventario_campos_galpon_y_ubicacion(client, setup_filtros_inventario_test):
    """Verifica que galpon, pasillo, pallet y ubicacion viajen en los DTOs de respuesta."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT-DISP-01&estado=Disponibles", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    item = data[0]
    assert item["galpon"] == "Galpón A"
    assert item["ubicacion_galpon"] == "Galpón A"
    assert item["pasillo"] == "P-01"
    assert item["pallet"] == "PL-01"


def test_inventario_activo_sin_ubicacion(client, setup_filtros_inventario_test):
    """Verifica que un activo huérfano de ubicación retorne strings vacíos o legibles."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT-HUERF-05&estado=Disponibles", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    item = data[0]
    assert item["galpon"] == ""
    assert item["pasillo"] == ""
    assert item["pallet"] == ""


def test_inventario_busqueda_default_sin_parametro_estado_incluye_paletizados(client, setup_filtros_inventario_test):
    """Verifica que la consulta sin parámetro 'estado' (default) incluya activos en estado Paletizado."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/buscar?q=SKU-FILT", headers=headers)

    assert response.status_code == 200
    data = response.json()
    skus_encontrados = {item["sku"] for item in data}
    assert "SKU-FILT-PAL-04" in skus_encontrados
    assert "SKU-FILT-DISP-01" in skus_encontrados


def test_opciones_filtros_incluye_paletizados(client, setup_filtros_inventario_test):
    """Verifica que /opciones-filtros incluya pasillos y pallets de activos paletizados."""
    headers = setup_filtros_inventario_test["headers"]
    response = client.get("/api/v1/inventario/opciones-filtros", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert "P-04" in data["pasillos"]
    assert "PL-04" in data["pallets"]

