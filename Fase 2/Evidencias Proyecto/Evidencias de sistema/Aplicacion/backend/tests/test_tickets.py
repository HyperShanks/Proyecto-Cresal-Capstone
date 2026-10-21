import uuid
import pytest
from models import Region, Comuna, Sucursal, Rol, Usuario
from core.security import create_access_token, hash_password
from conftest import TestingSessionLocal


# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES Y TOKENS DE AUTENTICACIÓN
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def setup_ticket_users(setup_database):
    """Crea sucursales, roles y usuarios de prueba para tickets."""
    db = TestingSessionLocal()
    try:
        # Verificar o crear región/comuna/sucursal
        r = db.query(Region).filter_by(id_region=1).first()
        if not r:
            r = Region(id_region=1, nombre_region="Valparaíso")
            db.add(r)
            db.commit()

        c1 = db.query(Comuna).filter_by(id_comuna=1).first()
        if not c1:
            c1 = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
            db.add(c1)
            db.commit()

        suc1 = db.query(Sucursal).filter_by(id_sucursal=1).first()
        if not suc1:
            suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 123", id_comuna=1)
            db.add(suc1)
            db.commit()

        # Roles
        for id_r, nom in [(1, "Bodeguero"), (2, "Vendedor"), (3, "Caja"), (5, "Administrador")]:
            if not db.query(Rol).filter_by(id_rol=id_r).first():
                db.add(Rol(id_rol=id_r, nombre_rol=nom))
        db.commit()

        # Usuarios
        caja_uuid = uuid.uuid4()
        vendedor_uuid = uuid.uuid4()

        user_caja = Usuario(
            id_usuario=caja_uuid,
            id_rol=3,
            id_sucursal=1,
            rut_usuario="18.999.888-7",
            nombres="Lorena",
            apellidos="Valenzuela",
            email="lorena.caja@cresal.cl",
            password_hash=hash_password("caja1234"),
            pin_acceso="4444",
            estado="Activo",
        )
        user_vendedor = Usuario(
            id_usuario=vendedor_uuid,
            id_rol=2,
            id_sucursal=1,
            rut_usuario="17.888.777-6",
            nombres="Pedro",
            apellidos="Ventas",
            email="pedro.ventas@cresal.cl",
            password_hash=hash_password("ventas1234"),
            pin_acceso="5555",
            estado="Activo",
        )
        db.add_all([user_caja, user_vendedor])
        db.commit()

        return {
            "caja_id": str(caja_uuid),
            "vendedor_id": str(vendedor_uuid),
        }
    finally:
        db.close()


@pytest.fixture
def auth_headers_cajera(setup_ticket_users):
    """Genera headers con Bearer token para la cajera."""
    token = create_access_token({"sub": setup_ticket_users["caja_id"]})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_vendedor(setup_ticket_users):
    """Genera headers con Bearer token para el vendedor."""
    token = create_access_token({"sub": setup_ticket_users["vendedor_id"]})
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# TESTS DE INTEGRACIÓN (HU-06)
# ─────────────────────────────────────────────────────────────────────────────

def test_crear_ticket_exitoso(client, auth_headers_cajera):
    """CA-01 & CA-02: Valida creación de ticket con código 201 y estado 'Abierto'."""
    payload = {
        "tipo_ticket": "Error de App",
        "prioridad": "Alta",
        "asunto": "Error al conectar con lector POS en cobro",
        "descripcion": "El lector de tarjetas no responde al enviar la transacción desde Caja 01.",
    }

    response = client.post("/api/v1/tickets/", json=payload, headers=auth_headers_cajera)
    assert response.status_code == 201

    data = response.json()
    assert data["asunto"] == payload["asunto"]
    assert data["tipo_ticket"] == payload["tipo_ticket"]
    assert data["prioridad"] == payload["prioridad"]
    assert data["estado_ticket"] == "Abierto"
    assert data["id_usuario_creador"] is not None
    assert data["id_ticket"] is not None


def test_crear_ticket_validacion_limites_422(client, auth_headers_cajera):
    """Valida que campos vacíos o con longitud fuera de rango retornen 422 Unprocessable Entity."""
    # Asunto demasiado corto (< 5 caracteres)
    res1 = client.post(
        "/api/v1/tickets/",
        json={
            "tipo_ticket": "Error de App",
            "prioridad": "Alta",
            "asunto": "POS",
            "descripcion": "Descripción válida con más de diez caracteres.",
        },
        headers=auth_headers_cajera,
    )
    assert res1.status_code == 422

    # Descripción demasiado corta (< 10 caracteres)
    res2 = client.post(
        "/api/v1/tickets/",
        json={
            "tipo_ticket": "Error de App",
            "prioridad": "Alta",
            "asunto": "Asunto válido con más de cinco caracteres",
            "descripcion": "Corta",
        },
        headers=auth_headers_cajera,
    )
    assert res2.status_code == 422


def test_crear_ticket_sin_autenticacion_401(client):
    """Valida rechazo 401 si no se envía header Authorization."""
    payload = {
        "tipo_ticket": "Error de App",
        "prioridad": "Alta",
        "asunto": "Ticket sin autenticación",
        "descripcion": "Descripción detallada del incidente.",
    }
    response = client.post("/api/v1/tickets/", json=payload)
    assert response.status_code in (401, 403)


def test_obtener_mis_tickets_aislamiento(client, auth_headers_cajera, auth_headers_vendedor):
    """CA-03: Valida que GET /mis-tickets retorne solo los tickets del usuario autenticado."""
    # Cajera crea un ticket
    client.post(
        "/api/v1/tickets/",
        json={
            "tipo_ticket": "Error de App",
            "prioridad": "Urgente",
            "asunto": "Ticket exclusivo de la cajera",
            "descripcion": "Solo la cajera debería ver este ticket en su bandeja.",
        },
        headers=auth_headers_cajera,
    )

    # Vendedor crea otro ticket
    client.post(
        "/api/v1/tickets/",
        json={
            "tipo_ticket": "Sugerencia",
            "prioridad": "Baja",
            "asunto": "Ticket exclusivo del vendedor",
            "descripcion": "Solo el vendedor debería ver este ticket en su bandeja.",
        },
        headers=auth_headers_vendedor,
    )

    # Cajera consulta sus tickets
    res_caja = client.get("/api/v1/tickets/mis-tickets", headers=auth_headers_cajera)
    assert res_caja.status_code == 200
    asuntos_caja = [t["asunto"] for t in res_caja.json()]
    assert "Ticket exclusivo de la cajera" in asuntos_caja
    assert "Ticket exclusivo del vendedor" not in asuntos_caja
