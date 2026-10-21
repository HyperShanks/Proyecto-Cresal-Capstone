# test_geografia_bodega_prep.py
"""
Pruebas automatizadas para:
1. Endpoint GET /api/v1/ordenes/comunas (Regiones y Comunas desde la BD).
2. Despacho a comunas dinámicas en el Checkout Wizard.
3. Generación de tareas de pre-entrega en Bodega para órdenes de preparación (ítems manuales e inventariados).
"""

import uuid
import pytest
from models import (
    Region, Comuna, Sucursal, Rol, Usuario,
    Categoria_Activo, Estado_Activo, Vehiculo_Origen,
    Activo_Inventariado, Cliente
)
from core.security import create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def setup_geografia_test(setup_database):
    db = TestingSessionLocal()
    try:
        # 1. Regiones y Comunas
        r1 = db.query(Region).filter_by(id_region=1).first()
        if not r1:
            r1 = Region(id_region=1, nombre_region="Valparaíso")
            db.add(r1)
            db.flush()

        r2 = db.query(Region).filter_by(id_region=7).first()
        if not r2:
            r2 = Region(id_region=7, nombre_region="Metropolitana de Santiago")
            db.add(r2)
            db.flush()

        c1 = db.query(Comuna).filter_by(id_comuna=1).first()
        if not c1:
            c1 = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(c1)
            db.flush()

        c2 = db.query(Comuna).filter_by(id_comuna=381).first()
        if not c2:
            c2 = Comuna(id_comuna=381, nombre_comuna="Villa Alemana", id_region=1)
            db.add(c2)
            db.flush()

        # 2. Sucursal
        suc = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc:
            suc = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 100", id_comuna=1)
            db.add(suc)
            db.flush()

        # 3. Roles
        roles_data = [(1, "Bodeguero"), (2, "Vendedor"), (3, "Cajero"), (4, "Supervisor"), (5, "Administrador")]
        for r_id, r_nom in roles_data:
            r = db.query(Rol).filter_by(id_rol=r_id).first()
            if not r:
                db.add(Rol(id_rol=r_id, nombre_rol=r_nom))
        db.flush()

        # 4. Usuarios
        vendedor = db.query(Usuario).filter_by(email="vendedor_geo@cresal.cl").first()
        if not vendedor:
            vendedor = Usuario(
                id_usuario=uuid.uuid4(),
                email="vendedor_geo@cresal.cl",
                rut_usuario="11111111-1",
                nombres="Vendedor",
                apellidos="Geo",
                password_hash="hash",
                pin_acceso="9981",
                id_rol=2,
                id_sucursal=1,
                estado="Activo",
            )
            db.add(vendedor)
            db.flush()

        bodeguero = db.query(Usuario).filter_by(email="bodeguero_geo@cresal.cl").first()
        if not bodeguero:
            bodeguero = Usuario(
                id_usuario=uuid.uuid4(),
                email="bodeguero_geo@cresal.cl",
                rut_usuario="22222222-2",
                nombres="Bodeguero",
                apellidos="Geo",
                password_hash="hash",
                pin_acceso="9982",
                id_rol=1,
                id_sucursal=1,
                estado="Activo",
            )
            db.add(bodeguero)
            db.flush()

        # 5. Cliente
        cliente = db.query(Cliente).filter_by(rut_cliente="12345678-5").first()
        if not cliente:
            cliente = Cliente(
                id_cliente=uuid.uuid4(),
                rut_cliente="12345678-5",
                nombres="Juan",
                apellidos="Pérez",
                correo="juan.perez@test.cl",
                telefono="+56912345678",
                id_comuna=1,
                consentimiento_legal=True,
                estado="Activo"
            )
            db.add(cliente)
            db.flush()

        db.commit()

        token_vendedor = create_access_token({"sub": str(vendedor.id_usuario), "rol": 2, "sucursal": 1})
        token_bodeguero = create_access_token({"sub": str(bodeguero.id_usuario), "rol": 1, "sucursal": 1})

        return {
            "vendedor_headers": {"Authorization": f"Bearer {token_vendedor}"},
            "bodeguero_headers": {"Authorization": f"Bearer {token_bodeguero}"},
            "id_cliente": str(cliente.id_cliente),
        }
    finally:
        db.close()


def test_endpoint_comunas_geografia(client, setup_geografia_test):
    """GET /api/v1/ordenes/comunas retorna el árbol de regiones y comunas."""
    headers = setup_geografia_test["vendedor_headers"]
    response = client.get("/api/v1/ordenes/comunas", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "regiones" in data
    assert len(data["regiones"]) >= 1
    valpo = next((r for r in data["regiones"] if r["nombre_region"] == "Valparaíso"), None)
    assert valpo is not None
    comunas_valpo = [c["nombre_comuna"] for c in valpo["comunas"]]
    assert "Viña del Mar" in comunas_valpo
    assert "Villa Alemana" in comunas_valpo


def test_checkout_wizard_con_comuna_dinamica_y_preparacion(client, setup_geografia_test):
    """
    Checkout Wizard con despacho a Villa Alemana (ID 381) e ítem manual con notas de preparación.
    Verifica que la orden se emite con éxito y que la tarea de pre-entrega aparece para el bodeguero.
    """
    v_headers = setup_geografia_test["vendedor_headers"]
    b_headers = setup_geografia_test["bodeguero_headers"]
    id_cli = setup_geografia_test["id_cliente"]

    payload = {
        "id_cliente": id_cli,
        "tipo_entrega": "Despacho Domicilio",
        "total_venta": 45000,
        "monto_pendiente": 45000,
        "monto_abono": 0,
        "instrucciones_bodega": "Embalar cuidadosamente en caja sellada con burbujas.",
        "items_inventariados": [],
        "items_manuales": [
            {
                "descripcion": "Pastillas de freno universales",
                "cantidad": 1,
                "precio_unitario": 45000,
                "precio_final": 45000,
                "notas_preparacion": "Verificar espesor de 15mm antes de entregar."
            }
        ],
        "reservas": [],
        "datos_despacho": {
            "id_comuna_destino": 381,
            "direccion_envio": "Calle Ligustro 450",
            "receptor_nombres": "Carlos Santana",
            "receptor_rut": "11.111.111-1",
            "receptor_telefono": "+56987654321",
            "empresa_transporte": "Chilexpress"
        }
    }

    # 1. Emitir la orden con la comuna de la BD
    res_orden = client.post("/api/v1/ordenes/checkout-wizard", json=payload, headers=v_headers)
    assert res_orden.status_code == 201, f"Error: {res_orden.text}"
    orden_data = res_orden.json()
    assert orden_data["estado"] == "Reservada"
    assert orden_data["despacho_generado"] is True

    # 2. Consultar como bodeguero las tareas pendientes
    res_tareas = client.get("/api/v1/bodega/tareas-pendientes?sucursal_id=1", headers=b_headers)
    assert res_tareas.status_code == 200
    tareas = res_tareas.json()

    # NO debe existir tarea de bodega para ítems manuales / venta libre (misceláneos)
    tarea_prep = next((t for t in tareas if "Pastillas de freno" in t["titulo_pieza"]), None)
    assert tarea_prep is None, f"Los misceláneos no deben generar tareas para bodega. Tarea encontrada: {tarea_prep}"
