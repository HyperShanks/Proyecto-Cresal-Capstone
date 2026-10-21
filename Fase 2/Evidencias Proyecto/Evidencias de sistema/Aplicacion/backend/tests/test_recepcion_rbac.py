import uuid
from datetime import datetime, date
import pytest
from conftest import TestingSessionLocal
import models
from core.security import create_access_token, hash_password


@pytest.fixture
def recepcion_setup(client):
    db = TestingSessionLocal()
    try:
        # 1. Rol 9: Recepción, Rol 1: Bodeguero
        rol_recepcion = db.query(models.Rol).filter(models.Rol.id_rol == 9).first()
        if not rol_recepcion:
            rol_recepcion = models.Rol(id_rol=9, nombre_rol="Recepción")
            db.add(rol_recepcion)

        rol_bodega = db.query(models.Rol).filter(models.Rol.id_rol == 1).first()
        if not rol_bodega:
            rol_bodega = models.Rol(id_rol=1, nombre_rol="Bodeguero")
            db.add(rol_bodega)

        # Región, Comuna, Sucursal
        reg = db.query(models.Region).filter_by(id_region=1).first()
        if not reg:
            reg = models.Region(id_region=1, nombre_region="Valparaíso")
            db.add(reg)

        com = db.query(models.Comuna).filter_by(id_comuna=1).first()
        if not com:
            com = models.Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(com)

        suc = db.query(models.Sucursal).filter_by(id_sucursal=1).first()
        if not suc:
            suc = models.Sucursal(id_sucursal=1, nombre_sucursal="Viña del Mar", direccion="Av. Principal 123", id_comuna=1)
            db.add(suc)

        # Estados de activo necesarios
        est_desarme = db.query(models.Estado_Activo).filter_by(nombre_estado="Desarme").first()
        if not est_desarme:
            est_desarme = models.Estado_Activo(id_estado=5, nombre_estado="Desarme")
            db.add(est_desarme)

        cat_mot = db.query(models.Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat_mot:
            cat_mot = models.Categoria_Activo(id_categoria=1, nombre_categoria="Motor")
            db.add(cat_mot)

        cat_caj = db.query(models.Categoria_Activo).filter_by(id_categoria=2).first()
        if not cat_caj:
            cat_caj = models.Categoria_Activo(id_categoria=2, nombre_categoria="Caja")
            db.add(cat_caj)

        db.commit()

        # Usuario Gloria (Rol 9 - Recepción)
        user_gloria = db.query(models.Usuario).filter_by(email="gloria@cresal.cl").first()
        if not user_gloria:
            user_gloria = models.Usuario(
                id_usuario=uuid.uuid4(),
                id_rol=9,
                id_sucursal=1,
                rut_usuario="20.999.888-7",
                nombres="Gloria",
                apellidos="Recepción",
                email="gloria@cresal.cl",
                password_hash=hash_password("RecepcionApp2026-16"),
                pin_acceso="4598",
                estado="Activo"
            )
            db.add(user_gloria)

        # Usuario Bodeguero (Rol 1)
        user_bodega = db.query(models.Usuario).filter_by(email="bodega@cresal.cl").first()
        if not user_bodega:
            user_bodega = models.Usuario(
                id_usuario=uuid.uuid4(),
                id_rol=1,
                id_sucursal=1,
                rut_usuario="16.234.567-8",
                nombres="Juan Pablo",
                apellidos="Bodega",
                email="bodega@cresal.cl",
                password_hash=hash_password("Password123!"),
                pin_acceso="1001",
                estado="Activo"
            )
            db.add(user_bodega)

        db.commit()

        token_gloria = create_access_token(data={"sub": str(user_gloria.id_usuario), "id_rol": 9, "id_sucursal": 1})
        token_bodega = create_access_token(data={"sub": str(user_bodega.id_usuario), "id_rol": 1, "id_sucursal": 1})

        return {
            "gloria_headers": {"Authorization": f"Bearer {token_gloria}"},
            "bodega_headers": {"Authorization": f"Bearer {token_bodega}"},
            "gloria": user_gloria,
            "bodega": user_bodega,
        }
    finally:
        db.close()


def test_recepcion_siguiente_ingreso(client, recepcion_setup):
    headers = recepcion_setup["gloria_headers"]
    response = client.get("/api/v1/vehiculos/recepcion/siguiente-ingreso", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "siguiente_ingreso" in data
    assert int(data["siguiente_ingreso"]) >= 1


def test_recepcion_registro_con_13_columnas_y_sppu(client, recepcion_setup):
    headers = recepcion_setup["gloria_headers"]

    payload = {
        "marca": "TOYOTA",
        "modelo": "YARIS SPORT 1.5",
        "anio": 2019,
        "es_sppu": True,
        "factura": "FAC-9921",
        "origen": "PARTICULAR",
        "color": "BLANCO",
        "numero_motor": "1NZ-FE-78219",
        "destino": "DESARME",
        "grua": "F. FANO",
        "observaciones": "+ Con Llave + Sin Documentos",
        "traccion": "4x2 Delantera"
    }

    response = client.post("/api/v1/vehiculos/recepcion/registro", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()

    assert data["marca"] == "TOYOTA"
    assert data["modelo"] == "YARIS SPORT 1.5"
    assert data["factura"] == "FAC-9921"
    assert data["origen"] == "PARTICULAR"
    assert data["color"] == "BLANCO"
    assert data["grua"] == "F. FANO"
    assert data["destino"] == "DESARME"
    assert "+ Con Llave" in data["observaciones"]
    # Comprobar que asignó automáticamente SPPU-{numero_ingreso}
    assert data["patente"].startswith("SPPU-")
    assert data["patente"] == f"SPPU-{data['numero_ingreso']}"


def test_recepcion_recientes_y_busqueda(client, recepcion_setup):
    headers = recepcion_setup["gloria_headers"]

    # Registrar un vehículo específico para buscarlo
    payload = {
        "patente": "KKLX88",
        "marca": "CHEVROLET",
        "modelo": "SAIL 1.4",
        "anio": 2018,
        "es_sppu": False,
        "factura": "REM-400",
        "origen": "OVALLE",
        "color": "GRIS",
        "grua": "A. NÚÑEZ",
        "observaciones": "Chocado frontal"
    }
    create_res = client.post("/api/v1/vehiculos/recepcion/registro", json=payload, headers=headers)
    assert create_res.status_code == 201

    # Buscar por patente
    res_busqueda = client.get("/api/v1/vehiculos/recepcion/recientes?busqueda=KKLX88", headers=headers)
    assert res_busqueda.status_code == 200
    data = res_busqueda.json()
    assert data["total"] >= 1
    assert any(item["patente"] == "KKLX88" for item in data["items"])


def test_recepcion_exportar_matriz_tsv(client, recepcion_setup):
    headers = recepcion_setup["gloria_headers"]
    response = client.get("/api/v1/vehiculos/recepcion/exportar-matriz", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "tsv" in data
    assert "N° Ingreso\tPatente\tFactura\tFecha ingreso" in data["tsv"]
    assert "OBSERVACIONES" in data["tsv"]
    assert data["total"] >= 1


def test_aislamiento_rol_recepcion_hacia_bodega_403(client, recepcion_setup):
    """
    Criterio de Aceptación DoD: Intentar invocar rutas del WMS con el token del
    rol Recepción (Gloria) DEBE responder con HTTP 403 Forbidden.
    """
    gloria_headers = recepcion_setup["gloria_headers"]
    bodega_headers = recepcion_setup["bodega_headers"]

    # 1. Gloria intenta acceder a resumen-alertas de bodega -> 403 Forbidden
    res_gloria = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=gloria_headers)
    assert res_gloria.status_code == 403
    assert "El rol Recepción no tiene permisos para acceder a las operaciones de bodega/WMS" in res_gloria.json()["detail"]

    # 2. Bodeguero intenta acceder a resumen-alertas -> 200 OK
    res_bodega = client.get("/api/v1/bodega/resumen-alertas?sucursal_id=1", headers=bodega_headers)
    assert res_bodega.status_code == 200
