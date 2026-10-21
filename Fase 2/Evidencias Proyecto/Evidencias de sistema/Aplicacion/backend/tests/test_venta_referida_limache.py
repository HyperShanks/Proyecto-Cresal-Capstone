# backend/tests/test_venta_referida_limache.py
"""
Suite de pruebas automatizadas para la Tarea 24:
Venta Referida a Sucursal Limache con Persistencia y Distintivo en 'Mis Órdenes'.
"""

import uuid
from datetime import datetime, timezone
import pytest
from conftest import TestingSessionLocal
from models import (
    Usuario,
    Rol,
    Sucursal,
    Region,
    Comuna,
    Cliente,
    Categoria_Activo,
    Estado_Activo,
    Activo_Inventariado,
    Orden_Venta,
    Detalle_Orden,
)
from core.security import create_access_token, hash_password


@pytest.fixture(scope="module")
def db_session_limache(setup_database):
    db = TestingSessionLocal()
    try:
        # 1. Región y Comunas
        reg = db.query(Region).filter_by(id_region=1).first()
        if not reg:
            reg = Region(id_region=1, nombre_region="Valparaíso")
            db.add(reg)
            db.flush()

        com1 = db.query(Comuna).filter_by(id_comuna=1).first()
        if not com1:
            com1 = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(com1)
        com2 = db.query(Comuna).filter_by(id_comuna=2).first()
        if not com2:
            com2 = Comuna(id_comuna=2, nombre_comuna="Limache", id_region=1)
            db.add(com2)
        db.flush()

        # 2. Sucursales
        suc1 = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc1:
            suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Viña del Mar", direccion="Av. Libertad 100", id_comuna=1)
            db.add(suc1)
        suc2 = db.query(Sucursal).filter_by(id_sucursal=2).first()
        if not suc2:
            suc2 = Sucursal(id_sucursal=2, nombre_sucursal="Limache", direccion="Palmira Romano 200", id_comuna=2)
            db.add(suc2)
        db.flush()

        # 3. Roles
        rol_vendedor = db.query(Rol).filter_by(id_rol=2).first()
        if not rol_vendedor:
            rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
            db.add(rol_vendedor)
        db.flush()

        # 4. Usuarios Vendedores
        vendedor_vina = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=1,
            rut_usuario="11.222.333-4",
            nombres="Carlos",
            apellidos="Vendedor Viña",
            email="carlos.vina@cresal.cl",
            password_hash=hash_password("Password123!"),
            pin_acceso="2101",
            estado="Activo",
        )

        vendedor_pedro = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=1,
            rut_usuario="12.333.444-5",
            nombres="Pedro",
            apellidos="Vendedor Colega",
            email="pedro.colega@cresal.cl",
            password_hash=hash_password("Password123!"),
            pin_acceso="2102",
            estado="Activo",
        )

        vendedor_limache = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=2,
            rut_usuario="77.888.999-4",
            nombres="Ventas",
            apellidos="Limache",
            email="limache@cresal.cl",
            password_hash=hash_password("Password123!"),
            pin_acceso="2020",
            estado="Activo",
        )
        db.add_all([vendedor_vina, vendedor_pedro, vendedor_limache])
        db.flush()

        # 5. Cliente
        cliente = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="15.666.777-8",
            nombres="Cliente",
            apellidos="Particular",
            estado="Activo",
        )
        db.add(cliente)
        db.commit()

        yield {
            "vendedor_vina": vendedor_vina,
            "vendedor_pedro": vendedor_pedro,
            "vendedor_limache": vendedor_limache,
            "cliente": cliente,
        }
    finally:
        db.close()


def test_vendedor_limache_disponible_en_selector_sucursal_vina(client, db_session_limache):
    """
    Criterio 1: Disponibilidad de Usuario.
    Verifica que al consultar /vendedores para la sucursal 1 (Viña del Mar),
    el usuario comercial Limache figure siempre disponible como opción.
    """
    vina = db_session_limache["vendedor_vina"]
    token = create_access_token(data={"sub": str(vina.id_usuario), "rol": vina.id_rol})
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/api/v1/ordenes/vendedores?sucursal_id=1", headers=headers)
    assert response.status_code == 200
    vendedores = response.json()

    emails = [v["correo"] for v in vendedores]
    assert "limache@cresal.cl" in emails, "Limache debe estar disponible en el selector de Viña del Mar"

    item_limache = next(v for v in vendedores if v["correo"] == "limache@cresal.cl")
    assert item_limache["rol_nombre"] == "Vendedor Limache"


def test_orden_asignada_a_limache_persiste_en_mis_ordenes_del_emisor(client, db_session_limache):
    """
    Criterio 2 y 3: Persistencia en 'Mis Órdenes' e Identificación Visual.
    Al emitir una orden asignada a Limache, el vendedor emisor la sigue visualizando
    con es_asignada_limache = True.
    """
    vina = db_session_limache["vendedor_vina"]
    limache = db_session_limache["vendedor_limache"]
    cli = db_session_limache["cliente"]

    token_vina = create_access_token(data={"sub": str(vina.id_usuario), "rol": vina.id_rol})
    headers_vina = {"Authorization": f"Bearer {token_vina}"}

    db = TestingSessionLocal()
    try:
        orden_limache = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=limache.id_usuario,        # Imputación a Limache
            id_vendedor_asignado=vina.id_usuario,  # Emisor de Viña del Mar
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=250000,
            monto_pendiente=250000,
            fecha_creacion=datetime.now(timezone.utc),
        )
        db.add(orden_limache)
        db.commit()
        id_orden_creada = str(orden_limache.id_orden)
    finally:
        db.close()

    # Consultar /mis-ventas desde el usuario de Viña del Mar
    res = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_vina)
    assert res.status_code == 200
    ordenes_vina = res.json()

    orden_encontrada = next((o for o in ordenes_vina if o["id_orden"] == id_orden_creada), None)
    assert orden_encontrada is not None, "La orden asignada a Limache DEBE persistir en Mis Órdenes del emisor"
    assert orden_encontrada["es_asignada_limache"] is True, "Debe tener la bandera es_asignada_limache = True"


def test_orden_asignada_a_otro_vendedor_se_oculta_del_emisor(client, db_session_limache):
    """
    Criterio 4: Mantenimiento del Flujo Regular.
    Si la venta se asigna a otro vendedor convencional (ej. Pedro),
    la orden SE OCULTA del vendedor emisor (Carlos).
    """
    vina = db_session_limache["vendedor_vina"]
    pedro = db_session_limache["vendedor_pedro"]
    cli = db_session_limache["cliente"]

    token_vina = create_access_token(data={"sub": str(vina.id_usuario), "rol": vina.id_rol})
    headers_vina = {"Authorization": f"Bearer {token_vina}"}

    token_pedro = create_access_token(data={"sub": str(pedro.id_usuario), "rol": pedro.id_rol})
    headers_pedro = {"Authorization": f"Bearer {token_pedro}"}

    db = TestingSessionLocal()
    try:
        orden_pedro = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli.id_cliente,
            id_vendedor=pedro.id_usuario,          # Transferida a Pedro
            id_vendedor_asignado=vina.id_usuario,  # Emisor Carlos
            id_sucursal=1,
            estado_orden="Reservada",
            total_venta=180000,
            monto_pendiente=180000,
            fecha_creacion=datetime.now(timezone.utc),
        )
        db.add(orden_pedro)
        db.commit()
        id_orden_pedro = str(orden_pedro.id_orden)
    finally:
        db.close()

    # 1. Carlos (emisor) NO debe verla
    res_carlos = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_vina)
    assert res_carlos.status_code == 200
    ids_carlos = [o["id_orden"] for o in res_carlos.json()]
    assert id_orden_pedro not in ids_carlos, "La orden transferida a Pedro NO debe figurar en Mis Órdenes de Carlos"

    # 2. Pedro (titular receptor) SÍ debe verla
    res_pedro = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_pedro)
    assert res_pedro.status_code == 200
    ids_pedro = [o["id_orden"] for o in res_pedro.json()]
    assert id_orden_pedro in ids_pedro, "La orden transferida debe figurar en Mis Órdenes de Pedro"


def test_usuario_limache_visualiza_sus_ordenes_titulares(client, db_session_limache):
    """
    Verifica que el usuario comercial Limache visualice en su bandeja todas las órdenes
    donde es titular comercial, sin importar qué vendedor las emitió.
    """
    limache = db_session_limache["vendedor_limache"]
    token_limache = create_access_token(data={"sub": str(limache.id_usuario), "rol": limache.id_rol})
    headers_limache = {"Authorization": f"Bearer {token_limache}"}

    res_limache = client.get("/api/v1/ordenes/mis-ventas?todas=true", headers=headers_limache)
    assert res_limache.status_code == 200
    ordenes = res_limache.json()
    assert len(ordenes) >= 1

    # Para el usuario Limache, es_asignada_limache es False (es titular directo)
    for o in ordenes:
        assert o["es_asignada_limache"] is False
