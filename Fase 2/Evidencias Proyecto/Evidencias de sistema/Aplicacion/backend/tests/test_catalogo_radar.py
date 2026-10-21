import uuid
import pytest
from datetime import datetime, timezone, timedelta
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
        # Seed Base
        r = Region(id_region=1, nombre_region="Metropolitana")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Santiago", id_region=1)
        db.add(c)
        
        suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Santiago", direccion="Av 1", id_comuna=1)
        suc2 = Sucursal(id_sucursal=2, nombre_sucursal="Sucursal Norte - Antofagasta", direccion="Av 2", id_comuna=1)
        db.add_all([suc1, suc2])
        
        rol = Rol(id_rol=1, nombre_rol="Vendedor")
        db.add(rol)
        
        u1_id = uuid.uuid4()
        u2_id = uuid.uuid4()
        user_suc1 = Usuario(
            id_usuario=u1_id,
            id_rol=1,
            id_sucursal=1,
            rut_usuario="11.111.111-1",
            nombres="Vendedor",
            apellidos="Santiago",
            email="vendedor1@cresal.cl",
            password_hash="hash",
            pin_acceso="1234",
            estado="Activo"
        )
        user_suc2 = Usuario(
            id_usuario=u2_id,
            id_rol=1,
            id_sucursal=2,
            rut_usuario="22.222.222-2",
            nombres="Vendedor",
            apellidos="Norte",
            email="vendedor2@cresal.cl",
            password_hash="hash",
            pin_acceso="5678",
            estado="Activo"
        )
        db.add_all([user_suc1, user_suc2])
        
        cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
        cat_caja = Categoria_Activo(id_categoria=2, nombre_categoria="Caja de Cambio")
        cat_acc = Categoria_Activo(id_categoria=3, nombre_categoria="Accesorio")
        db.add_all([cat_motor, cat_caja, cat_acc])
        
        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_res = Estado_Activo(id_estado=2, nombre_estado="Reservado")
        est_vend = Estado_Activo(id_estado=3, nombre_estado="Vendido")
        db.add_all([est_disp, est_res, est_vend])
        
        v1 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-001",
            patente="AA1111",
            vin="11111111111111111",
            marca="Toyota",
            modelo="Yaris",
            anio=2018,
            traccion="4x2"
        )
        v2 = Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso="ING-002",
            patente="BB2222",
            vin="22222222222222222",
            marca="Chevrolet",
            modelo="Sail",
            anio=2016,
            traccion="4x2"
        )
        db.add_all([v1, v2])
        
        # Activo 1: Sucursal 2 (Antofagasta), Toyota Yaris Motor, Creado hace 2 días
        a1_id = uuid.uuid4()
        act1 = Activo_Inventariado(
            id_activo=a1_id,
            sku_qr_fisico="SKU-YARIS-SUC2",
            id_categoria=1,
            id_estado=1, # Disponible
            id_sucursal_actual=2,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=500000,
            estado="Activo",
            fecha_creacion=datetime.now(timezone.utc) - timedelta(days=2)
        )
        dm1 = Detalle_Motor(
            id_activo=a1_id,
            cilindrada="1.5L",
            combustible="Gasolina",
            transmision_tipo="Manual",
            numero_motor="1NZ-FE-SUC2",
        )
        
        # Activo 2: Sucursal 1 (Santiago), Toyota Yaris Motor, Creado hace 1 día
        a2_id = uuid.uuid4()
        act2 = Activo_Inventariado(
            id_activo=a2_id,
            sku_qr_fisico="SKU-YARIS-SUC1",
            id_categoria=1,
            id_estado=1, # Disponible
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=550000,
            estado="Activo",
            fecha_creacion=datetime.now(timezone.utc) - timedelta(days=1)
        )
        dm2 = Detalle_Motor(
            id_activo=a2_id,
            cilindrada="1.5L",
            combustible="Gasolina",
            transmision_tipo="Manual",
            numero_motor="1NZ-FE-SUC1",
        )

        # Activo 3: Sucursal 1 (Santiago), Caja Chevrolet Sail
        a3_id = uuid.uuid4()
        act3 = Activo_Inventariado(
            id_activo=a3_id,
            sku_qr_fisico="SKU-SAIL-CAJA-SUC1",
            id_categoria=2,
            id_estado=1, # Disponible
            id_sucursal_actual=1,
            id_vehiculo=v2.id_vehiculo,
            precio_referencia=300000,
            estado="Activo",
            fecha_creacion=datetime.now(timezone.utc)
        )
        dc3 = Detalle_Caja_Cambio(
            id_activo=a3_id,
            transmision_tipo="Mecánica 5V"
        )

        # Activo 4: Sucursal 1 - Reservado (NO debe aparecer)
        a4_id = uuid.uuid4()
        act4 = Activo_Inventariado(
            id_activo=a4_id,
            sku_qr_fisico="SKU-RESERVADO-SUC1",
            id_categoria=1,
            id_estado=2, # Reservado
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=400000,
            estado="Activo"
        )

        # Activo 5: Sucursal 1 - Borrado lógico (estado != 'Activo', NO debe aparecer)
        a5_id = uuid.uuid4()
        act5 = Activo_Inventariado(
            id_activo=a5_id,
            sku_qr_fisico="SKU-INACTIVO-SUC1",
            id_categoria=1,
            id_estado=1,
            id_sucursal_actual=1,
            id_vehiculo=v1.id_vehiculo,
            precio_referencia=400000,
            estado="Inactivo"
        )

        db.add_all([act1, dm1, act2, dm2, act3, dc3, act4, act5])
        db.commit()

        yield {
            "user_suc1_id": u1_id,
            "user_suc2_id": u2_id,
            "token_suc1": create_access_token({"sub": str(u1_id)}),
            "token_suc2": create_access_token({"sub": str(u2_id)}),
        }
    finally:
        db.close()


def test_catalogo_radar_prioriza_sucursal_del_vendedor(client, db_session):
    """
    Verifica que para el vendedor de Sucursal 1 (Santiago), los activos de Sucursal 1
    aparecen ANTES que los activos de Sucursal 2 (Radar de Stock).
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    response = client.get("/api/v1/inventario/catalogo", headers=headers)
    assert response.status_code == 200
    
    data = response.json()
    assert "items" in data
    assert "total_count" in data
    assert data["total_count"] == 3  # act1, act2, act3 (excluye reservado e inactivo)

    items = data["items"]
    # Los primeros items deben pertenecer a la sucursal 1
    assert items[0]["id_sucursal_actual"] == 1
    assert items[1]["id_sucursal_actual"] == 1
    # El último debe ser el de sucursal 2
    assert items[2]["id_sucursal_actual"] == 2


def test_catalogo_radar_para_vendedor_sucursal_2(client, db_session):
    """
    Verifica que para el vendedor de Sucursal 2 (Norte), los activos de Sucursal 2
    aparecen PRIMEROS en la lista.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc2']}"}
    response = client.get("/api/v1/inventario/catalogo", headers=headers)
    assert response.status_code == 200
    
    data = response.json()
    items = data["items"]
    # El primer item debe ser el de sucursal 2
    assert items[0]["id_sucursal_actual"] == 2


def test_catalogo_filtro_explicito_sucursal(client, db_session):
    """
    Verifica que al aplicar filtro explícito de sucursal (id_sucursal=2),
    únicamente se retornan los activos de esa sucursal.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    response = client.get("/api/v1/inventario/catalogo?id_sucursal=2", headers=headers)
    assert response.status_code == 200
    
    data = response.json()
    assert data["total_count"] == 1
    assert len(data["items"]) == 1
    assert data["items"][0]["id_sucursal_actual"] == 2
    assert data["items"][0]["sku_qr_fisico"] == "SKU-YARIS-SUC2"


def test_catalogo_filtro_categoria_y_detalles_tecnicos(client, db_session):
    """
    Verifica filtrado por categoría y resolución de detalles técnicos (motor vs caja).
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    
    # Categoría 2: Cajas de cambio
    response = client.get("/api/v1/inventario/catalogo?id_categoria=2", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["total_count"] == 1
    caja = data["items"][0]
    assert caja["nombre_categoria"] == "Caja de Cambio"
    assert caja["transmision_tipo"] == "Mecánica 5V"
    assert caja["cilindrada"] is None
    assert caja["marca"] == "Chevrolet"
    assert caja["numero_motor"] is None

    # Categoría 1: Motores
    response_motores = client.get("/api/v1/inventario/catalogo?id_categoria=1", headers=headers)
    assert response_motores.status_code == 200
    data_motores = response_motores.json()
    assert data_motores["total_count"] == 2
    motor = data_motores["items"][0]
    assert motor["nombre_categoria"] == "Motor"
    assert motor["cilindrada"] == "1.5L"
    assert motor["combustible"] == "Gasolina"
    assert motor["numero_motor"] in ["1NZ-FE-SUC1", "1NZ-FE-SUC2"]


def test_catalogo_busqueda_q(client, db_session):
    """
    Verifica búsqueda por texto libre en marca, modelo o SKU.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    
    # Búsqueda por modelo 'Sail'
    response = client.get("/api/v1/inventario/catalogo?q=sail", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["total_count"] == 1
    assert data["items"][0]["modelo"] == "Sail"

    # Búsqueda por SKU parcial
    response_sku = client.get("/api/v1/inventario/catalogo?q=YARIS-SUC2", headers=headers)
    assert response_sku.status_code == 200
    data_sku = response_sku.json()
    assert data_sku["total_count"] == 1
    assert data_sku["items"][0]["sku_qr_fisico"] == "SKU-YARIS-SUC2"


def test_catalogo_paginacion(client, db_session):
    """
    Verifica funcionamiento de limit y offset.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    
    response_p1 = client.get("/api/v1/inventario/catalogo?limit=2&offset=0", headers=headers)
    assert response_p1.status_code == 200
    data_p1 = response_p1.json()
    assert data_p1["total_count"] == 3
    assert len(data_p1["items"]) == 2
    assert data_p1["limit"] == 2
    assert data_p1["offset"] == 0

    response_p2 = client.get("/api/v1/inventario/catalogo?limit=2&offset=2", headers=headers)
    assert response_p2.status_code == 200
    data_p2 = response_p2.json()
    assert data_p2["total_count"] == 3
    assert len(data_p2["items"]) == 1
    assert data_p2["offset"] == 2


def test_catalogo_filtro_cilindrada_y_transmision(client, db_session):
    """
    Verifica los filtros por cilindrada y tipo de transmisión en el catálogo.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}

    # Filtro Cilindrada 1.5L
    response_cil = client.get("/api/v1/inventario/catalogo?cilindrada=1.5L", headers=headers)
    assert response_cil.status_code == 200
    data_cil = response_cil.json()
    assert data_cil["total_count"] >= 1
    for it in data_cil["items"]:
        assert it["cilindrada"] == "1.5L"

    # Filtro Transmisión Mecánica
    response_trans = client.get("/api/v1/inventario/catalogo?transmision=Mecanica", headers=headers)
    assert response_trans.status_code == 200
    data_trans = response_trans.json()
    assert data_trans["total_count"] >= 1
    for it in data_trans["items"]:
        assert "Mec" in it["transmision_tipo"] or "Man" in it["transmision_tipo"]


def test_buscar_inventario_y_catalogo_por_tipo_pieza(client, db_session):
    """
    Verifica que escribir 'motor' o 'caja' en la búsqueda por texto libre (q)
    devuelva los repuestos correspondientes según su categoría.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}

    # 1. Búsqueda en catálogo por 'motor'
    res_cat_motor = client.get("/api/v1/inventario/catalogo?q=motor", headers=headers)
    assert res_cat_motor.status_code == 200
    data_cat = res_cat_motor.json()
    assert data_cat["total_count"] >= 1
    for item in data_cat["items"]:
        assert "MOTOR" in item["nombre_categoria"].upper() or "MOTOR" in (item.get("modelo") or "").upper()

    # 2. Búsqueda en inventario general por 'caja'
    res_inv_caja = client.get("/api/v1/inventario/buscar?q=caja", headers=headers)
    assert res_inv_caja.status_code == 200
    items_inv = res_inv_caja.json()
    assert len(items_inv) >= 1
    for item in items_inv:
        assert "CAJA" in item["categoria"].upper() or "CAJA" in item["modelo"].upper()


def test_opciones_filtros_catalogo_solo_retorna_disponibles(client, db_session):
    """
    Verifica que /api/v1/inventario/catalogo/opciones-filtros retorne únicamente
    opciones de marcas, años, cilindradas y transmisiones de repuestos en estado 'Disponible',
    excluyendo marcas de repuestos no disponibles o inactivos.
    """
    headers = {"Authorization": f"Bearer {db_session['token_suc1']}"}
    res = client.get("/api/v1/inventario/catalogo/opciones-filtros", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert "marcas" in data
    assert "anios" in data
    assert "cilindradas" in data
    assert "transmisiones" in data

    # En db_session los disponibles son Toyota (Yaris) y Chevrolet (Sail)
    assert "TOYOTA" in data["marcas"]
    assert "CHEVROLET" in data["marcas"]
    # No debe incluir marcas que no están en la BD
    assert "NISSAN" not in data["marcas"]
    assert "HYUNDAI" not in data["marcas"]

    # Años disponibles
    assert 2018 in data["anios"]
    assert 2016 in data["anios"]

    # Cilindradas de motores disponibles
    assert "1.5" in data["cilindradas"]

    # Transmisiones
    assert any("Mecánica" in t or "Manual" in t for t in data["transmisiones"])

    # Filtro por categoría cajas (id_categoria=2): solo debe listar CHEVROLET
    res_cajas = client.get("/api/v1/inventario/catalogo/opciones-filtros?id_categoria=2", headers=headers)
    assert res_cajas.status_code == 200
    data_cajas = res_cajas.json()
    assert "CHEVROLET" in data_cajas["marcas"]
    assert "TOYOTA" not in data_cajas["marcas"]


