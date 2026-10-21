import uuid
import pytest
from models import Region, Comuna, Sucursal, Rol, Usuario
from core.security import create_access_token, hash_password
from conftest import TestingSessionLocal


@pytest.fixture(scope="module")
def db_session(setup_database):
    """
    Inicializa datos de prueba de roles, sucursales y usuarios para las pruebas de autenticación y RBAC de caja.
    """
    db = TestingSessionLocal()
    try:
        # Seed Geografía y Sucursal
        r = Region(id_region=1, nombre_region="Valparaíso")
        db.add(r)
        c = Comuna(id_comuna=1, nombre_comuna="Viña del Mar", id_region=1)
        db.add(c)
        suc1 = Sucursal(
            id_sucursal=1,
            nombre_sucursal="Casa Matriz - Viña",
            direccion="Av. Libertad 123",
            id_comuna=1
        )
        db.add(suc1)

        # Seed Roles
        rol_bodeguero = Rol(id_rol=1, nombre_rol="Bodeguero")
        rol_vendedor = Rol(id_rol=2, nombre_rol="Vendedor")
        rol_caja = Rol(id_rol=3, nombre_rol="Caja")
        rol_gerente = Rol(id_rol=4, nombre_rol="Gerente")
        rol_admin = Rol(id_rol=5, nombre_rol="Administrador")
        rol_jefe = Rol(id_rol=6, nombre_rol="Jefe de Ventas")
        db.add_all([rol_bodeguero, rol_vendedor, rol_caja, rol_gerente, rol_admin, rol_jefe])

        # Usuarios
        user_caja = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=3,
            id_sucursal=1,
            rut_usuario="12.345.678-9",
            nombres="María Jesús",
            apellidos="López Vega",
            email="maria.caja@cresal.cl",
            password_hash=hash_password("caja1234"),
            pin_acceso="3333",
            estado="Activo"
        )
        user_admin = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=5,
            id_sucursal=1,
            rut_usuario="11.222.333-4",
            nombres="Carlos",
            apellidos="Administrador",
            email="admin@cresal.cl",
            password_hash=hash_password("admin1234"),
            pin_acceso="5555",
            estado="Activo"
        )
        user_bodeguero = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=1,
            rut_usuario="10.111.222-3",
            nombres="Juan",
            apellidos="Bodeguero",
            email="bodega@cresal.cl",
            password_hash=hash_password("bodega1234"),
            pin_acceso="1111",
            estado="Activo"
        )
        user_vendedor = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=1,
            rut_usuario="14.555.666-7",
            nombres="Pedro",
            apellidos="Vendedor",
            email="vendedor@cresal.cl",
            password_hash=hash_password("ventas1234"),
            pin_acceso="2222",
            estado="Activo"
        )
        user_inactivo = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=3,
            id_sucursal=1,
            rut_usuario="19.999.888-7",
            nombres="Inactivo",
            apellidos="Caja",
            email="inactivo@cresal.cl",
            password_hash=hash_password("inactivo1234"),
            pin_acceso="9999",
            estado="Inactivo"
        )

        db.add_all([user_caja, user_admin, user_bodeguero, user_vendedor, user_inactivo])
        db.commit()
        yield db
    finally:
        db.close()


def test_login_pin_cajera_exitoso(client, db_session):
    """Verifica autenticación por PIN para rol de Caja (id_rol == 3) y claims devueltos."""
    user_caja = db_session.query(Usuario).filter(Usuario.pin_acceso == "3333").first()
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "3333",
            "id_usuario": str(user_caja.id_usuario)
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    usuario = data["usuario"]
    assert usuario["rut_usuario"] == "12.345.678-9"
    assert usuario["nombres"] == "María Jesús"
    assert usuario["apellidos"] == "López Vega"
    assert usuario["id_rol"] == 3
    assert usuario["nombre_rol"] == "Caja"
    assert usuario["id_sucursal"] == 1


def test_login_pin_admin_exitoso(client, db_session):
    """Verifica autenticación por PIN para Administrador (id_rol == 5)."""
    user_admin = db_session.query(Usuario).filter(Usuario.pin_acceso == "5555").first()
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "5555",
            "id_usuario": str(user_admin.id_usuario)
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert data["usuario"]["id_rol"] == 5
    assert data["usuario"]["nombre_rol"] == "Administrador"


def test_verificar_acceso_caja_autorizado(client, db_session):
    """Verifica que un usuario con rol Caja (3) tiene acceso 200 a /api/v1/caja/verificar-acceso."""
    user_caja = db_session.query(Usuario).filter(Usuario.pin_acceso == "3333").first()
    token = create_access_token(data={"sub": str(user_caja.id_usuario)})

    response = client.get(
        "/api/v1/caja/verificar-acceso",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["autorizado"] is True
    assert data["rol"] == "Caja"
    assert data["id_sucursal"] == 1


def test_verificar_acceso_admin_autorizado(client, db_session):
    """Verifica que un Administrador (5) tiene acceso 200 a /api/v1/caja/verificar-acceso."""
    user_admin = db_session.query(Usuario).filter(Usuario.pin_acceso == "5555").first()
    token = create_access_token(data={"sub": str(user_admin.id_usuario)})

    response = client.get(
        "/api/v1/caja/verificar-acceso",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["autorizado"] is True
    assert data["rol"] == "Administrador"


def test_verificar_acceso_bodeguero_rechazado_403(client, db_session):
    """Verifica que un Bodeguero (id_rol == 1) recibe 403 Forbidden al intentar acceder a caja."""
    user_bodega = db_session.query(Usuario).filter(Usuario.pin_acceso == "1111").first()
    token = create_access_token(data={"sub": str(user_bodega.id_usuario)})

    response = client.get(
        "/api/v1/caja/verificar-acceso",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403
    data = response.json()
    assert "Acceso restringido: Se requieren permisos de Operario de Caja o Administrador." in data["detail"]


def test_verificar_acceso_vendedor_rechazado_403(client, db_session):
    """Verifica que un Vendedor (id_rol == 2) recibe 403 Forbidden al intentar acceder a caja."""
    user_vendedor = db_session.query(Usuario).filter(Usuario.pin_acceso == "2222").first()
    token = create_access_token(data={"sub": str(user_vendedor.id_usuario)})

    response = client.get(
        "/api/v1/caja/verificar-acceso",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403
    data = response.json()
    assert "Acceso restringido: Se requieren permisos de Operario de Caja o Administrador." in data["detail"]


def test_verificar_acceso_sin_token_401_o_403(client, db_session):
    """Verifica que sin cabecera Authorization se rechaza la petición."""
    response = client.get("/api/v1/caja/verificar-acceso")
    assert response.status_code in [401, 403]


def test_verificar_acceso_token_invalido_401(client, db_session):
    """Verifica que un token inválido o corrupto retorna 401 Unauthorized."""
    response = client.get(
        "/api/v1/caja/verificar-acceso",
        headers={"Authorization": "Bearer token.invalido.123"}
    )
    assert response.status_code == 401


def test_login_pin_invalido_401(client, db_session):
    """Verifica que un PIN inexistente o que no coincide retorna 401 Unauthorized."""
    user_caja = db_session.query(Usuario).filter(Usuario.pin_acceso == "3333").first()
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "0000",
            "id_usuario": str(user_caja.id_usuario)
        }
    )
    assert response.status_code == 401
    assert "PIN inválido o usuario inactivo" in response.json()["detail"]


def test_login_pin_usuario_inactivo_401(client, db_session):
    """Verifica que un usuario inactivo no pueda iniciar sesión por PIN."""
    user_inactivo = db_session.query(Usuario).filter(Usuario.pin_acceso == "9999").first()
    response = client.post(
        "/api/auth/login-pin",
        json={
            "pin_acceso": "9999",
            "id_usuario": str(user_inactivo.id_usuario)
        }
    )
    assert response.status_code == 401
    assert "PIN inválido o usuario inactivo" in response.json()["detail"]

