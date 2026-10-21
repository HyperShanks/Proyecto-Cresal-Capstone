from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from jose import jwt, JWTError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from uuid import UUID

from core.config import settings
from database import get_db
from models import Usuario


def hash_password(password: str) -> str:
    """Genera el hash seguro de la contraseña usando bcrypt."""
    pwd_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(pwd_bytes, salt).decode('utf-8')


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verifica si la contraseña en texto plano coincide con el hash guardado."""
    try:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'),
            hashed_password.encode('utf-8')
        )
    except Exception:
        return False


def verify_pin(plain_pin: str, stored_pin: str) -> bool:
    """
    Compara el PIN ingresado por el operario contra el PIN almacenado en BD.
    Los PINs se guardan en texto plano (asignados por administrador),
    por lo que la validación es una comparación directa de cadenas.
    """
    return plain_pin == stored_pin


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Genera un Token JWT firmado con la clave secreta y el algoritmo configurados.
    
    Args:
        data: Payload base del token (debe incluir 'sub' con el id_usuario).
        expires_delta: Tiempo de vida personalizado. Si no se proporciona,
                       usa TOKEN_EXPIRE_MINUTES de la configuración.

    Returns:
        Token JWT como string codificado.
    """
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.TOKEN_EXPIRE_MINUTES)

    to_encode.update({"exp": expire})

    encoded_jwt = jwt.encode(
        to_encode,
        settings.JWT_SECRET_KEY,
        algorithm=settings.ALGORITHM
    )

    return encoded_jwt


# ─────────────────────────────────────────────────────────────────────────────
# Esquema de seguridad HTTP Bearer (extrae el token del header Authorization)
# ─────────────────────────────────────────────────────────────────────────────
_bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> Usuario:
    """
    Dependencia reutilizable de FastAPI que:
    1. Extrae el token del header 'Authorization: Bearer <token>'.
    2. Lo decodifica y valida contra la clave secreta del proyecto.
    3. Recupera el usuario de la BD usando el 'sub' del payload.
    4. Lanza 401 si el token es inválido, expirado o el usuario no existe.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    usuario = db.query(Usuario).filter(
        Usuario.id_usuario == UUID(user_id)
    ).first()

    if usuario is None or usuario.estado != "Activo":
        raise credentials_exception

    return usuario


_bearer_scheme_optional = HTTPBearer(auto_error=False)


def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme_optional),
    db: Session = Depends(get_db),
) -> Optional[Usuario]:
    """
    Dependencia de FastAPI que valida opcionalmente el token JWT:
    - Si el token es válido y el usuario activo, retorna el modelo Usuario.
    - Si no se envía token o está expirado, retorna None sin lanzar 401.
    """
    if not credentials or not credentials.credentials:
        return None
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        user_id = payload.get("sub")
        if user_id:
            usuario = db.query(Usuario).filter(Usuario.id_usuario == UUID(user_id)).first()
            if usuario and usuario.estado == "Activo":
                return usuario
    except Exception:
        return None
    return None



def verificar_rol_jefe_ventas(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea el rol de Jefe de Ventas (id_rol == 6).
    Lanza 403 Forbidden si el rol no coincide.
    """
    if current_user.id_rol != 6:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requiere rol de Jefe de Ventas para esta operación."
        )
    return current_user


def verificar_rol_tasacion(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea rol de Gerencia (id_rol == 4),
    Administrador (id_rol == 5) o Jefe de Ventas (id_rol == 6) para fijar o
    actualizar precios de referencia comercial (HU-3.8 y HU-5.3).
    """
    if current_user.id_rol not in [4, 5, 6]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren privilegios de Gerencia, Administración o Jefatura de Ventas para fijar precios."
        )
    return current_user


def require_inventario_maestro_read(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea rol de Gerencia (id_rol == 4),
    Administrador (id_rol == 5), Jefe de Ventas (id_rol == 6) o Auditor (id_rol == 8)
    para consultar el catálogo maestro de inventario multi-sucursal (HU-5.3).
    """
    if current_user.id_rol not in [4, 5, 6, 8]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren privilegios de Gerencia, Administración, Jefatura de Ventas o Auditoría."
        )
    return current_user


def require_caja_role(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea permisos de Caja (id_rol == 3) o Administrador (id_rol == 5).
    Lanza 403 Forbidden si el rol no está autorizado.
    """
    if current_user.id_rol not in [3, 5]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren permisos de Operario de Caja o Administrador."
        )
    return current_user


def require_bodeguero_or_admin(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea permisos de Bodeguero (id_rol == 1) o Administrador (id_rol == 5).
    Lanza 403 Forbidden si el rol no está autorizado.
    """
    if current_user.id_rol not in [1, 5]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren permisos de Bodeguero o Administrador."
        )
    return current_user


def require_gerencia_role(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valido que el usuario autenticado posea rol de Gerencia (id_rol == 4), Administrador (id_rol == 5)
    o Auditor / Gerente Auditor (id_rol == 8).
    Lanzo 403 Forbidden si el rol no está autorizado para acceder al panel gerencial (HU-5.1).
    Permite consultas generales como listar sucursales activas.
    """
    if current_user.id_rol not in [4, 5, 8]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren privilegios gerenciales o de Auditoría."
        )
    return current_user


def es_usuario_auditor_central(usuario: Usuario) -> bool:
    """
    Determina si un usuario con rol Auditor (8) pertenece a Casa Matriz / Central.
    En producción id_sucursal == 1, o sucursal con 'matriz' o 'central' en el nombre.
    """
    if usuario.id_rol != 8:
        return False
    if usuario.id_sucursal == 1:
        return True
    if usuario.sucursal and usuario.sucursal.nombre_sucursal:
        nombre = usuario.sucursal.nombre_sucursal.lower()
        if "matriz" in nombre or "central" in nombre:
            return True
    return False


def require_gerencia_o_auditor_central(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario tenga acceso a las métricas ejecutivas financieras, operativas y backorders.
    Permitido para:
    - Gerencia General (id_rol == 4)
    - Administrador (id_rol == 5)
    - Auditor Central / Casa Matriz (id_rol == 8 con id_sucursal == 1 o Casa Matriz)
    
    Bloquea a auditores de sucursales satélites (id_rol == 8 con id_sucursal != 1).
    """
    if current_user.id_rol not in [4, 5, 8]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren privilegios gerenciales o de Auditoría Central."
        )
    if current_user.id_rol == 8 and not es_usuario_auditor_central(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Los auditores de sucursal satélite solo tienen acceso al visor de inventario y catálogo."
        )
    return current_user


def require_auditoria_or_caja_role(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valido que el usuario autenticado posea rol de Caja (id_rol == 3),
    Gerencia General (id_rol == 4), Administrador (id_rol == 5) o Auditor Central (id_rol == 8 con id_sucursal == 1) para
    acceder al historial y visor de auditoría de órdenes (HU-5.2).
    Lanzo 403 Forbidden si el rol no está autorizado o si es un auditor satélite.
    """
    if current_user.id_rol not in [3, 4, 5, 8]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Acceso restringido: Se requieren permisos de "
                "Auditoría, Gerencia o Caja."
            )
        )
    if current_user.id_rol == 8 and not es_usuario_auditor_central(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Los auditores de sucursal satélite no tienen acceso al historial de órdenes de clientes."
        )
    return current_user


def require_recepcion_or_admin(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Valida que el usuario autenticado posea rol de Recepción (id_rol == 9),
    Bodeguero (id_rol == 1), Gerencia (id_rol == 4) o Administrador (id_rol == 5).
    SPEC-22: Recepción Vehicular Patio.
    """
    if current_user.id_rol not in [9, 1, 4, 5]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: Se requieren permisos de Recepción, Bodega o Administración."
        )
    return current_user


def require_bodega_access(
    current_user: Usuario = Depends(get_current_user)
) -> Usuario:
    """
    Seguridad RBAC (SPEC-22): El rol Recepción (id_rol == 9) tiene estrictamente
    denegado el acceso a las funciones logísticas internas de bodega (cubicaje,
    pallets, picking y despacho). Lanza 403 Forbidden.
    """
    if current_user.id_rol == 9:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso restringido: El rol Recepción no tiene permisos para acceder a las operaciones de bodega/WMS."
        )
    return current_user


