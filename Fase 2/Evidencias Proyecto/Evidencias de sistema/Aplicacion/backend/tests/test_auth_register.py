# test_auth_register.py
# Suite de pruebas automatizadas para el endpoint de registro de usuarios y hashing de contraseñas.

import uuid
import pytest

from models import Region, Comuna, Sucursal, Rol, Usuario
from core.security import verify_password, create_access_token
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    db = TestingSessionLocal()
    try:
        # Seed Geografía y Sucursal
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        db.add(c)
        suc1 = Sucursal(id_sucursal=1, nombre_sucursal="Casa Matriz - Viña", direccion="Av. Libertad 123", id_comuna=1)
        db.add(suc1)

        # Seed Roles
        rol_bodeguero = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        rol_jefe = Rol(id_rol=6, nombre_rol="Jefe de Ventas")
        db.add_all([rol_bodeguero, rol_vendedor, rol_admin, rol_jefe])

        # Usuario existente para pruebas de colisión
        user_existente = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=1,
            rut_usuario="99.888.777-6",
            nombres="Operario",
            apellidos="Existente",
            email="existente@cresal.cl",
            password_hash="fake_hash",
            pin_acceso="5555",
            estado="Activo"
        )

        # Usuario administrador para autorizar el registro
        user_admin = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=5,
            id_sucursal=1,
            rut_usuario="55.555.555-5",
            nombres="Admin",
            apellidos="Principal",
            email="admin@cresal.cl",
            password_hash="fake_hash",
            pin_acceso="0000",
            estado="Activo"
        )
        db.add_all([user_existente, user_admin])
        db.commit()

        yield {
            "sucursal": suc1,
            "rol_vendedor": rol_vendedor,
            "rol_jefe": rol_jefe,
            "user_existente": user_existente,
            "user_admin": user_admin,
        }
    finally:
        db.close()


@pytest.fixture(scope="module")
def auth_headers_admin(db_session):
    token = create_access_token(data={"sub": str(db_session["user_admin"].id_usuario)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def auth_headers_vendedor(db_session):
    token = create_access_token(data={"sub": str(db_session["user_existente"].id_usuario)})
    return {"Authorization": f"Bearer {token}"}


def test_registro_usuario_acceso_denegado_para_no_admin(client, db_session, auth_headers_vendedor):
    payload = {
        "rut_usuario": "17.123.456-7",
        "nombres": "Intento",
        "apellidos": "NoAdmin",
        "email": "intento@cresal.cl",
        "password": "Password123!",
        "id_rol": 2,
    }
    response = client.post("/api/auth/register", json=payload, headers=auth_headers_vendedor)
    assert response.status_code == 403
    assert "Se requiere rol de Administrador" in response.json()["detail"]


def test_registro_usuario_exitoso_encripta_password(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "18.765.432-1",
        "nombres": "Carlos",
        "apellidos": "Vargas",
        "email": "carlos.vargas@cresal.cl",
        "password": "PasswordSegura2026!",
        "id_rol": 2,
        "id_sucursal": 1,
        "pin_acceso": "4321"
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 201

    data = response.json()
    assert data["rut_usuario"] == "18.765.432-1"
    assert data["email"] == "carlos.vargas@cresal.cl"
    assert data["id_rol"] == 2
    assert data["nombre_rol"] == "Vendedor"
    assert data["pin_acceso"] == "4321"
    assert data["estado"] == "Activo"
    assert "registrado exitosamente" in data["mensaje"]

    # Verificar en Base de Datos que la contraseña esté hasheada con bcrypt
    db = TestingSessionLocal()
    try:
        user_db = db.query(Usuario).filter(Usuario.email == "carlos.vargas@cresal.cl").first()
        assert user_db is not None
        assert user_db.password_hash != "PasswordSegura2026!"
        assert user_db.password_hash.startswith("$2b$") or user_db.password_hash.startswith("$2a$")
        assert verify_password("PasswordSegura2026!", user_db.password_hash) is True
        assert verify_password("PasswordIncorrecta", user_db.password_hash) is False
    finally:
        db.close()


def test_registro_usuario_sin_pin_ni_sucursal_auto_genera_pin_y_default_sucursal(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "19.999.888-7",
        "nombres": "Daniela",
        "apellidos": "Muñoz",
        "email": "daniela.munoz@cresal.cl",
        "password": "MiPasswordPrueba123",
        "id_rol": 6,
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 201

    data = response.json()
    assert data["email"] == "daniela.munoz@cresal.cl"
    assert len(data["pin_acceso"]) == 4
    assert data["id_sucursal"] == 1
    assert data["nombre_rol"] == "Jefe de Ventas"


def test_registro_usuario_correo_duplicado_retorna_400(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "20.111.222-3",
        "nombres": "Otro",
        "apellidos": "Usuario",
        "email": "existente@cresal.cl",  # Email duplicado
        "password": "password123",
        "id_rol": 1
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 400
    assert "correo electrónico 'existente@cresal.cl' ya se encuentra registrado" in response.json()["detail"]


def test_registro_usuario_rut_duplicado_retorna_400(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "99.888.777-6",  # RUT duplicado
        "nombres": "Nombre",
        "apellidos": "Apellido",
        "email": "nuevo.email@cresal.cl",
        "password": "password123",
        "id_rol": 1
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 400
    assert "El RUT '99.888.777-6' ya se encuentra registrado" in response.json()["detail"]


def test_registro_usuario_rol_no_existente_retorna_404(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "22.333.444-5",
        "nombres": "Rol",
        "apellidos": "Fantasma",
        "email": "fantasma@cresal.cl",
        "password": "password123",
        "id_rol": 9999  # Rol inexistente
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 404
    assert "El rol con ID '9999' no existe" in response.json()["detail"]


def test_registro_usuario_pin_duplicado_retorna_400(client, db_session, auth_headers_admin):
    payload = {
        "rut_usuario": "23.444.555-6",
        "nombres": "Pin",
        "apellidos": "Duplicado",
        "email": "pin.duplicado@cresal.cl",
        "password": "password123",
        "id_rol": 1,
        "pin_acceso": "5555"  # PIN existente
    }

    response = client.post("/api/auth/register", json=payload, headers=auth_headers_admin)
    assert response.status_code == 400
    assert "El PIN '5555' ya se encuentra asignado" in response.json()["detail"]

