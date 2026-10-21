import uuid
import pytest
from models import Region, Comuna, Sucursal, Rol, Usuario
from core.security import hash_password
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def auth_test_data(setup_database):
    """
    Inicializa datos de prueba de roles, sucursales y usuarios para verificar
    el flujo completo de Enrolamiento (Email/Password) y Login por PIN Vinculado.
    """
    db = TestingSessionLocal()
    try:
        # Geografía y Sucursal
        r = Region(id_region=10, nombre_region="Metropolitana")
        db.add(r)
        c = Comuna(id_comuna=10, nombre_comuna="Santiago Centro", id_region=10)
        db.add(c)
        suc = Sucursal(
            id_sucursal=10,
            nombre_sucursal="Sucursal Central",
            direccion="Av. Matta 500",
            id_comuna=10
        )
        db.add(suc)

        # Roles
        rol_bodega = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_ventas = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        db.add_all([rol_bodega, rol_ventas, rol_caja, rol_admin])

        # Usuarios de prueba
        user_bodega = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=10,
            rut_usuario="15.111.222-3",
            nombres="Pedro",
            apellidos="Bodega",
            email="pedro.bodega@cresal.cl",
            password_hash=hash_password("claveBodega123"),
            pin_acceso="1234",
            estado="Activo"
        )
        user_ventas = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=10,
            rut_usuario="16.222.333-4",
            nombres="Lucía",
            apellidos="Ventas",
            email="lucia.ventas@cresal.cl",
            password_hash=hash_password("claveVentas123"),
            pin_acceso="5678",
            estado="Activo"
        )
        user_bloqueado = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=10,
            rut_usuario="17.333.444-5",
            nombres="Mario",
            apellidos="Inactivo",
            email="mario.inactivo@cresal.cl",
            password_hash=hash_password("claveInactivo123"),
            pin_acceso="4321",
            estado="Inactivo"
        )

        db.add_all([user_bodega, user_ventas, user_bloqueado])
        db.commit()

        yield {
            "bodega": user_bodega,
            "ventas": user_ventas,
            "inactivo": user_bloqueado,
        }
    finally:
        db.close()


def test_enrolamiento_login_email_password_exitoso(client, auth_test_data):
    """Verifica que el enrolamiento inicial con email y password retorna JWT y datos completos."""
    response = client.post(
        "/api/auth/login",
        json={
            "email": "pedro.bodega@cresal.cl",
            "password": "claveBodega123"
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    usuario = data["usuario"]
    assert usuario["id_usuario"] == str(auth_test_data["bodega"].id_usuario)
    assert usuario["email"] == "pedro.bodega@cresal.cl"
    assert usuario["id_rol"] == 1
    assert usuario["nombre_rol"] == "Bodeguero"
    assert usuario["id_sucursal"] == 10


def test_enrolamiento_login_email_password_credenciales_invalidas(client, auth_test_data):
    """Verifica rechazo con 401 si la contraseña o correo son incorrectos."""
    response = client.post(
        "/api/auth/login",
        json={
            "email": "pedro.bodega@cresal.cl",
            "password": "passwordIncorrecta"
        }
    )
    assert response.status_code == 401
    assert "Credenciales inválidas o usuario inactivo" in response.json()["detail"]

    response_no_user = client.post(
        "/api/auth/login",
        json={
            "email": "noexiste@cresal.cl",
            "password": "cualquiercosa"
        }
    )
    assert response_no_user.status_code == 401


def test_enrolamiento_login_email_password_usuario_inactivo(client, auth_test_data):
    """Verifica rechazo con 401 si el usuario está inactivo."""
    response = client.post(
        "/api/auth/login",
        json={
            "email": "mario.inactivo@cresal.cl",
            "password": "claveInactivo123"
        }
    )
    assert response.status_code == 401
    assert "Credenciales inválidas o usuario inactivo" in response.json()["detail"]


def test_login_pin_vinculado_exitoso(client, auth_test_data):
    """Verifica que el login por PIN vinculado al usuario enrolado retorne 200 y nuevo token."""
    user = auth_test_data["bodega"]
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "1234",
            "id_usuario": str(user.id_usuario)
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["usuario"]["id_usuario"] == str(user.id_usuario)
    assert data["usuario"]["nombres"] == "Pedro"


def test_login_pin_vinculado_pin_incorrecto_para_usuario(client, auth_test_data):
    """Verifica rechazo 401 cuando el PIN no coincide con el usuario enrolado."""
    user = auth_test_data["bodega"]
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "9999",  # PIN incorrecto
            "id_usuario": str(user.id_usuario)
        }
    )
    assert response.status_code == 401
    assert "PIN inválido o usuario inactivo" in response.json()["detail"]


def test_login_pin_vinculado_usuario_no_coincide_con_pin_ajeno(client, auth_test_data):
    """Verifica rechazo 401 cuando se envía el PIN de otro usuario (Zero Trust)."""
    user_bodega = auth_test_data["bodega"]
    # Intentar usar el PIN del usuario de ventas (5678) contra el UUID del usuario de bodega
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "5678",
            "id_usuario": str(user_bodega.id_usuario)
        }
    )
    assert response.status_code == 401
    assert "PIN inválido o usuario inactivo" in response.json()["detail"]


def test_login_pin_vinculado_uuid_invalido_o_inexistente(client, auth_test_data):
    """Verifica rechazo 401 con UUID malformado o inexistente."""
    response_malformed = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "1234",
            "id_usuario": "not-a-valid-uuid"
        }
    )
    assert response_malformed.status_code == 401

    random_uuid = str(uuid.uuid4())
    response_random = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "1234",
            "id_usuario": random_uuid
        }
    )
    assert response_random.status_code == 401


def test_login_pin_vinculado_usuario_inactivo(client, auth_test_data):
    """Verifica rechazo 401 para usuario inactivo aunque su PIN coincida."""
    user_inactivo = auth_test_data["inactivo"]
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "4321",
            "id_usuario": str(user_inactivo.id_usuario)
        }
    )
    assert response.status_code == 401
    assert "PIN inválido o usuario inactivo" in response.json()["detail"]


def test_login_pin_vinculado_falta_campos_requeridos_422(client):
    """Verifica rechazo 422 si falta el id_usuario o el pin_acceso en el payload."""
    response_sin_user = client.post(
        "/api/auth/login-pin",
        json={"pin_acceso": "1234"}
    )
    assert response_sin_user.status_code == 422

    response_sin_pin = client.post(
        "/api/auth/login-pin",
        json={"id_usuario": str(uuid.uuid4())}
    )
    assert response_sin_pin.status_code == 422
