import uuid
from datetime import datetime
import pytest
from conftest import TestingSessionLocal
import models
from core.security import create_access_token


@pytest.fixture
def auth_headers():
    db = TestingSessionLocal()
    try:
        # 1. Region y Comuna
        reg = db.query(models.Region).filter(models.Region.id_region == 1).first()
        if not reg:
            reg = models.Region(id_region=1, nombre_region="Valparaíso")
            db.add(reg)
            db.commit()

        com = db.query(models.Comuna).filter(models.Comuna.id_comuna == 1).first()
        if not com:
            com = models.Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(com)
            db.commit()

        # 2. Sucursal y Rol
        sucursal = db.query(models.Sucursal).filter(models.Sucursal.id_sucursal == 1).first()
        if not sucursal:
            sucursal = models.Sucursal(
                id_sucursal=1,
                nombre_sucursal="Casa Matriz - Viña",
                direccion="Calle 1",
                id_comuna=1,
            )
            db.add(sucursal)

        rol = db.query(models.Rol).filter(models.Rol.id_rol == 1).first()
        if not rol:
            rol = models.Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol)
        db.commit()

        # 3. Categorías y Estados
        for cat_id, cat_nom in [(1, "Motor"), (2, "Caja de Cambios")]:
            c = db.query(models.Categoria_Activo).filter_by(id_categoria=cat_id).first()
            if not c:
                db.add(models.Categoria_Activo(id_categoria=cat_id, nombre_categoria=cat_nom))

        for est_id, est_nom in [(1, "Disponible"), (2, "Reservado"), (3, "Vendido"), (5, "En Desarme"), (6, "Entregado"), (7, "Paletizado")]:
            e = db.query(models.Estado_Activo).filter_by(id_estado=est_id).first()
            if not e:
                db.add(models.Estado_Activo(id_estado=est_id, nombre_estado=est_nom))
        db.commit()

        # 4. Usuario
        usuario = db.query(models.Usuario).filter(models.Usuario.rut_usuario == "11.111.111-1").first()
        if not usuario:
            usuario = models.Usuario(
                id_usuario=uuid.uuid4(),
                rut_usuario="11.111.111-1",
                nombres="Test",
                apellidos="Bodeguero",
                email="bodeguero@cresal.cl",
                password_hash="fakehash",
                pin_acceso="1234",
                id_rol=1,
                id_sucursal=1,
                estado="Activo",
            )
            db.add(usuario)
            db.commit()
            db.refresh(usuario)

        token = create_access_token(data={"sub": str(usuario.id_usuario), "id_rol": usuario.id_rol, "id_sucursal": usuario.id_sucursal})
        return {"Authorization": f"Bearer {token}"}
    finally:
        db.close()


def test_obtener_vehiculo_existente(client, auth_headers):
    """
    Verifica que al consultar una patente existente en BD, el sistema
    responda con HTTP 200 y los datos correctos.
    """
    db = TestingSessionLocal()
    patente_prueba = "BBCL12"
    try:
        vehiculo = db.query(models.Vehiculo_Origen).filter(models.Vehiculo_Origen.patente == patente_prueba).first()
        if not vehiculo:
            vehiculo = models.Vehiculo_Origen(
                numero_ingreso="ING-2026-TEST",
                patente=patente_prueba,
                marca="Toyota",
                modelo="Yaris",
                anio=2015,
                estado="Activo",
            )
            db.add(vehiculo)
            db.commit()
    finally:
        db.close()

    response = client.get(f"/api/v1/vehiculos/{patente_prueba}", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["patente"] == patente_prueba
    assert data["marca"] == "Toyota"
    assert data["modelo"] == "Yaris"
    assert data["anio"] == 2015


def test_obtener_vehiculo_no_existente_retorna_404(client, auth_headers):
    """
    Verifica que al consultar una patente no registrada, retorne 404 para que la PDA
    haga scraping nativo.
    """
    response = client.get("/api/v1/vehiculos/ZZZZ99", headers=auth_headers)
    assert response.status_code == 404


def test_registro_ingreso_vehiculo_manual_fallback(client, auth_headers):
    """
    Verifica el flujo de contingencia manual (POST /api/v1/vehiculos/registro-manual)
    cuando Google Cloud Vision u OCR falla.
    """
    patente_test = f"FB{uuid.uuid4().hex[:4].upper()}"
    payload = {
        "correlativo_ingreso": "9999",
        "patente": patente_test,
        "marca": "Chevrolet",
        "modelo": "Sail",
        "anio": 2017,
        "traccion": "Delantera",
        "transmision": "Manual",
        "combustible": "Bencina",
        "numero_motor": "CHEV-9999",
        "cilindrada": "1.5L",
    }

    res = client.post("/api/v1/vehiculos/registro-manual", json=payload, headers=auth_headers)
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["patente"] == patente_test
    assert data["marca"] == "Chevrolet"
    assert data["numero_ingreso"] == "9999"

    db = TestingSessionLocal()
    try:
        activos = db.query(models.Activo_Inventariado).filter(
            models.Activo_Inventariado.id_vehiculo == uuid.UUID(data["id_vehiculo"])
        ).all()
        skus = {a.sku_qr_fisico for a in activos}
        assert skus == {"MOT-9999", "CAJ-9999"}
    finally:
        db.close()


def test_obtener_pendientes_paletizado_solo_desarme(client, auth_headers):
    """
    Verifica que GET /api/v1/vehiculos/pendientes-paletizado retorne únicamente activos
    de la sucursal activa con id_estado == 5 (En Desarme) y no incluya activos
    en estado Disponible (1) o Entregado (6) aunque su ubicación sea nula o 'S/P'.
    """
    db = TestingSessionLocal()
    try:
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=f"ING-PEND-{uuid.uuid4().hex[:4].upper()}",
            patente=f"PD{uuid.uuid4().hex[:4].upper()}",
            marca="Hyundai",
            modelo="Tucson",
            anio=2019,
        )
        db.add(veh)
        db.flush()

        act_desarme = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-PD1-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=1,
            id_estado=5,  # En Desarme
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo=None,
            ubicacion_pallet=None,
            fecha_creacion=datetime.now(),
        )

        act_disponible_sp = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"CAJ-PD2-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=2,
            id_estado=1,  # Estado 1 (Disponible) con ubicación "S/P"
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo="S/P",
            ubicacion_pallet="S/P",
            fecha_creacion=datetime.now(),
        )

        act_entregado_null = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-PD3-{uuid.uuid4().hex[:4].upper()}",
            id_categoria=1,
            id_estado=6,  # Estado 6 (Entregado) con ubicación liberada (None)
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo=None,
            ubicacion_pallet=None,
            fecha_creacion=datetime.now(),
        )

        db.add_all([act_desarme, act_disponible_sp, act_entregado_null])
        db.commit()

        # Consultar endpoint en vehiculos
        res_veh = client.get("/api/v1/vehiculos/pendientes-paletizado?sucursal_id=1", headers=auth_headers)
        assert res_veh.status_code == 200
        items_veh = res_veh.json()
        ids_veh = [item["id_activo"] for item in items_veh]
        assert str(act_desarme.id_activo) in ids_veh
        assert str(act_disponible_sp.id_activo) not in ids_veh
        assert str(act_entregado_null.id_activo) not in ids_veh

        # Consultar endpoint en bodega
        res_bod = client.get("/api/v1/bodega/pendientes-paletizado?sucursal_id=1", headers=auth_headers)
        assert res_bod.status_code == 200
        items_bod = res_bod.json()
        ids_bod = [item["id_activo"] for item in items_bod]
        assert str(act_desarme.id_activo) in ids_bod
        assert str(act_disponible_sp.id_activo) not in ids_bod
        assert str(act_entregado_null.id_activo) not in ids_bod
    finally:
        db.close()


def test_guardar_paletizado_rechaza_activo_no_en_desarme(client, auth_headers):
    """
    Verifica que guardar_paletizado rechace con HTTP 400 si el activo está en estado != 5
    (ej: Entregado ID 6 o Disponible ID 1) antes de tocar Supabase Storage.
    """
    db = TestingSessionLocal()
    try:
        folio = f"ING-ENT-{uuid.uuid4().hex[:4].upper()}"
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=folio,
            patente=f"ET{uuid.uuid4().hex[:4].upper()}",
            marca="Nissan",
            modelo="Qashqai",
            anio=2021,
        )
        db.add(veh)
        db.flush()

        act_motor = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-ET-{folio}",
            id_categoria=1,
            id_estado=6,  # Entregado
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo=None,
            ubicacion_pallet=None,
            ubicacion_galpon=None,
            fecha_creacion=datetime.now(),
        )
        db.add(act_motor)
        db.commit()

        foto_dummy = ("test.jpg", b"fake image data", "image/jpeg")
        response = client.post(
            "/api/v1/vehiculos/guardar-paletizado",
            headers=auth_headers,
            data={
                "numero_ingreso": folio,
                "tipo_repuesto": "Motor",
                "galpon": "G1",
                "pasillo": "P1",
                "pallet": "01",
            },
            files=[("fotos_comerciales", foto_dummy)],
        )
        assert response.status_code == 400
        assert "Solo se pueden paletizar repuestos en estado 'Desarme'" in response.json()["detail"]
    finally:
        db.close()


def test_consultar_ingreso_rechaza_activos_no_en_desarme(client, auth_headers):
    """
    Verifica que GET /api/v1/inventario/ingreso/{numero_ingreso} responda 400
    cuando los activos del vehículo ya fueron entregados o no están en Desarme (id_estado != 5).
    """
    db = TestingSessionLocal()
    try:
        folio = f"ING-DISP-{uuid.uuid4().hex[:4].upper()}"
        veh = models.Vehiculo_Origen(
            id_vehiculo=uuid.uuid4(),
            numero_ingreso=folio,
            patente=f"DP{uuid.uuid4().hex[:4].upper()}",
            marca="Mazda",
            modelo="CX-5",
            anio=2020,
        )
        db.add(veh)
        db.flush()

        act_motor = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"MOT-DP-{folio}",
            id_categoria=1,
            id_estado=1,  # Disponible
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo="P1",
            ubicacion_pallet="01",
            ubicacion_galpon="G1",
            fecha_creacion=datetime.now(),
        )
        act_caja = models.Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico=f"CAJ-DP-{folio}",
            id_categoria=2,
            id_estado=6,  # Entregado (ubicacion liberada a None)
            id_sucursal_actual=1,
            id_vehiculo=veh.id_vehiculo,
            estado="Activo",
            ubicacion_pasillo=None,
            ubicacion_pallet=None,
            ubicacion_galpon=None,
            fecha_creacion=datetime.now(),
        )
        db.add_all([act_motor, act_caja])
        db.commit()

        # Consultar endpoint de inventario por ingreso
        res = client.get(f"/api/v1/inventario/ingreso/{folio}", headers=auth_headers)
        assert res.status_code == 400
        assert "El activo asociado a este número ya fue paletizado previamente" in res.json()["detail"]
    finally:
        db.close()


