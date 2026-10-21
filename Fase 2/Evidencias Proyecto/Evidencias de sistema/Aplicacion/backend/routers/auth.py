import random
import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload

from database import get_db
from models import Usuario, Rol, Sucursal
from schemas import (
    LoginPINRequest,
    LoginEmailRequest,
    TokenResponse,
    UsuarioData,
    RegisterUserRequest,
    RegisterUserResponse,
)
from core.security import (
    verify_pin,
    verify_password,
    create_access_token,
    hash_password,
    get_current_user,
)

router = APIRouter(
    prefix="/api/auth",
    tags=["Autenticación"]
)



@router.post(
    "/register",
    response_model=RegisterUserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registro de Nuevos Usuarios",
    description="Crea un nuevo usuario en la base de datos con contraseña cifrada en bcrypt. Requiere permisos de Administrador (id_rol == 5)."
)
def registrar_usuario(
    request: RegisterUserRequest,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Registra un usuario en la tabla Usuario:
    1. Valida permisos de Administrador (id_rol == 5).
    2. Valida unicidad de correo y RUT.
    3. Valida la existencia del rol asignado.
    4. Hashea la contraseña en texto plano usando bcrypt.
    5. Genera o valida el PIN numérico de acceso de 4 dígitos.
    6. Guarda el nuevo registro con estado 'Activo'.
    """
    # 0. Validar permisos de Administrador (Zero Trust RBAC)
    if current_user.id_rol != 5:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: Se requiere rol de Administrador para registrar nuevos usuarios."
        )

    # 1. Validar si el email ya existe
    email_limpio = request.email.strip().lower()
    if db.query(Usuario).filter(Usuario.email == email_limpio).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El correo electrónico '{request.email}' ya se encuentra registrado."
        )

    # 2. Validar si el RUT ya existe
    rut_limpio = request.rut_usuario.strip()
    if db.query(Usuario).filter(Usuario.rut_usuario == rut_limpio).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El RUT '{request.rut_usuario}' ya se encuentra registrado en el sistema."
        )

    # 3. Validar si el Rol existe
    rol = db.query(Rol).filter(Rol.id_rol == request.id_rol).first()
    if not rol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"El rol con ID '{request.id_rol}' no existe."
        )

    # 4. Validar sucursal asignada
    id_sucursal_final = request.id_sucursal or 1
    sucursal = db.query(Sucursal).filter(Sucursal.id_sucursal == id_sucursal_final).first()
    if not sucursal:
        primera_sucursal = db.query(Sucursal).first()
        if primera_sucursal:
            id_sucursal_final = primera_sucursal.id_sucursal
        else:
            id_sucursal_final = 1

    # 5. Generar o validar PIN de acceso único de 4 dígitos
    pin_final = request.pin_acceso
    if pin_final:
        if db.query(Usuario).filter(Usuario.pin_acceso == pin_final).first():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"El PIN '{pin_final}' ya se encuentra asignado a otro usuario."
            )
    else:
        for _ in range(50):
            candidato = f"{random.randint(1000, 9999)}"
            if not db.query(Usuario).filter(Usuario.pin_acceso == candidato).first():
                pin_final = candidato
                break
        if not pin_final:
            pin_final = "9999"

    # 6. Hashear la contraseña con bcrypt
    password_cifrada = hash_password(request.password)

    # 7. Crear el usuario en la BD
    nuevo_usuario = Usuario(
        id_rol=request.id_rol,
        id_sucursal=id_sucursal_final,
        rut_usuario=rut_limpio,
        nombres=request.nombres.strip(),
        apellidos=request.apellidos.strip(),
        email=email_limpio,
        password_hash=password_cifrada,
        pin_acceso=pin_final,
        estado="Activo"
    )

    try:
        db.add(nuevo_usuario)
        db.commit()
        db.refresh(nuevo_usuario)
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error transaccional al registrar usuario: {str(e)}"
        )

    return RegisterUserResponse(
        id_usuario=nuevo_usuario.id_usuario,
        rut_usuario=nuevo_usuario.rut_usuario,
        nombres=nuevo_usuario.nombres,
        apellidos=nuevo_usuario.apellidos,
        email=nuevo_usuario.email,
        id_rol=nuevo_usuario.id_rol,
        nombre_rol=rol.nombre_rol,
        id_sucursal=nuevo_usuario.id_sucursal,
        nombre_sucursal=nuevo_usuario.nombre_sucursal,
        pin_acceso=nuevo_usuario.pin_acceso,
        estado=nuevo_usuario.estado,
        mensaje="Usuario registrado exitosamente con contraseña encriptada.",
    )


@router.post(
    "/login-pin",
    response_model=TokenResponse,
    summary="Login por PIN de Operario Vinculado",
    description="Autentica a un operario usando su PIN de 4 dígitos y su ID de usuario vinculado. "
                "Retorna un JWT Bearer Token y los datos públicos del usuario."
)
def login_por_pin(request: LoginPINRequest, db: Session = Depends(get_db)):
    """
    Flujo de autenticación por PIN vinculado al usuario:

    1. Valida el UUID de id_usuario.
    2. Busca en la tabla Usuario el registro con (id_usuario == request.id_usuario) AND (pin_acceso == request.pin_acceso).
    3. Si no existe, no coincide o está inactivo → 401 Unauthorized.
    4. Si es válido y activo → Genera JWT y retorna TokenResponse.
    """
    try:
        user_uuid = uuid.UUID(str(request.id_usuario))
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="PIN inválido o usuario inactivo"
        )

    # Consulta: buscar usuario por ID y PIN (cargando relación con Rol y Sucursal)
    usuario = db.query(Usuario).options(
        joinedload(Usuario.rol),
        joinedload(Usuario.sucursal)
    ).filter(
        Usuario.id_usuario == user_uuid,
        Usuario.pin_acceso == request.pin_acceso
    ).first()

    # Camino Triste: PIN no coincide o usuario no encontrado
    if not usuario:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="PIN inválido o usuario inactivo"
        )

    # Camino Triste: Usuario encontrado pero inactivo
    if usuario.estado != "Activo":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="PIN inválido o usuario inactivo"
        )

    # Verificación adicional de PIN
    if not verify_pin(request.pin_acceso, usuario.pin_acceso):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="PIN inválido o usuario inactivo"
        )

    # Camino Feliz: Generar JWT con sub = id_usuario como string
    access_token = create_access_token(
        data={"sub": str(usuario.id_usuario)}
    )

    usuario_data = UsuarioData.model_validate(usuario)
    if usuario.rol and not usuario_data.nombre_rol:
        usuario_data.nombre_rol = usuario.rol.nombre_rol
    if usuario.sucursal and not usuario_data.nombre_sucursal:
        usuario_data.nombre_sucursal = usuario.sucursal.nombre_sucursal

    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        usuario=usuario_data
    )


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Login por Email y Contraseña",
    description="Autentica a un usuario corporativo usando su correo y contraseña. "
                "Retorna un JWT Bearer Token y los datos públicos del usuario."
)
def login_por_email(request: LoginEmailRequest, db: Session = Depends(get_db)):
    """
    Autenticación tradicional por correo y contraseña.
    """
    usuario = db.query(Usuario).options(
        joinedload(Usuario.rol),
        joinedload(Usuario.sucursal)
    ).filter(
        Usuario.email == request.email.strip().lower()
    ).first()

    if not usuario or usuario.estado != "Activo" or not verify_password(request.password, usuario.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales inválidas o usuario inactivo"
        )

    access_token = create_access_token(
        data={"sub": str(usuario.id_usuario)}
    )

    usuario_data = UsuarioData.model_validate(usuario)
    if usuario.rol and not usuario_data.nombre_rol:
        usuario_data.nombre_rol = usuario.rol.nombre_rol
    if usuario.sucursal and not usuario_data.nombre_sucursal:
        usuario_data.nombre_sucursal = usuario.sucursal.nombre_sucursal

    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        usuario=usuario_data
    )

