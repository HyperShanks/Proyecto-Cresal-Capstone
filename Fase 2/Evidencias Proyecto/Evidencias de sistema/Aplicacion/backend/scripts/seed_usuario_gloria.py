"""
Script de creación y sincronización para la cuenta de Gloria (Rol 9 - Recepción Patio).
Datos:
- Email: gloria@cresal.cl
- Contraseña: RecepcionApp2026-16
- PIN: 4598
- Rol: 9 (Recepción)
- RUT: 20.999.888-7 (Temporal / ficticio con formato chileno)
- Sucursal: 1 (Viña del Mar)
"""

import sys
import os
import uuid
from datetime import datetime, timezone

# Añadir el directorio raíz de backend al sys.path para importar módulos
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import SessionLocal
from models import Usuario, Rol, Sucursal
from core.security import hash_password

def seed_gloria():
    db = SessionLocal()
    try:
        print("=== PROCESANDO CREACIÓN / ACTUALIZACIÓN DE USUARIO GLORIA ===")
        
        # 1. Asegurar que Rol 9 existe
        rol_9 = db.query(Rol).filter(Rol.id_rol == 9).first()
        if not rol_9:
            print("-> Creando Rol 9: Recepción...")
            rol_9 = Rol(
                id_rol=9,
                nombre_rol="Recepción",
                estado="Activo",
                fecha_creacion=datetime.now(timezone.utc)
            )
            db.add(rol_9)
            db.commit()
            db.refresh(rol_9)
            print("[OK] Rol 9 creado con exito.")
        else:
            print(f"-> Rol 9 ya existe: '{rol_9.nombre_rol}'")

        # 2. Asegurar que Sucursal 1 existe
        sucursal = db.query(Sucursal).filter(Sucursal.id_sucursal == 1).first()
        if not sucursal:
            print("⚠️ Advertencia: Sucursal 1 no encontrada, buscando primera sucursal disponible...")
            sucursal = db.query(Sucursal).first()

        id_sucursal = sucursal.id_sucursal if sucursal else 1

        email = "gloria@cresal.cl"
        pin = "4598"
        password_plano = "RecepcionApp2026-16"
        rut_dummy = "20.999.888-7"
        nombres = "Gloria"
        apellidos = "Recepción Patio"

        pwd_hash = hash_password(password_plano)

        # 3. Buscar si Gloria ya existe por email o RUT o PIN
        usuario = db.query(Usuario).filter(
            (Usuario.email == email) | (Usuario.rut_usuario == rut_dummy) | (Usuario.pin_acceso == pin)
        ).first()

        if usuario:
            print(f"-> Actualizando usuario existente de Gloria ({usuario.email})...")
            usuario.id_rol = 9
            usuario.id_sucursal = id_sucursal
            usuario.rut_usuario = rut_dummy
            usuario.nombres = nombres
            usuario.apellidos = apellidos
            usuario.email = email
            usuario.password_hash = pwd_hash
            usuario.pin_acceso = pin
            usuario.estado = "Activo"
            usuario.fecha_actualizacion = datetime.now(timezone.utc)
        else:
            print("-> Creando nuevo usuario para Gloria...")
            nuevo_id = uuid.uuid4()
            usuario = Usuario(
                id_usuario=nuevo_id,
                id_rol=9,
                id_sucursal=id_sucursal,
                rut_usuario=rut_dummy,
                nombres=nombres,
                apellidos=apellidos,
                email=email,
                password_hash=pwd_hash,
                pin_acceso=pin,
                estado="Activo",
                fecha_creacion=datetime.now(timezone.utc),
                fecha_actualizacion=datetime.now(timezone.utc)
            )
            db.add(usuario)

        db.commit()
        db.refresh(usuario)
        print("[OK] Usuario de Gloria sincronizado exitosamente en Supabase:")
        print(f"   - UUID: {usuario.id_usuario}")
        print(f"   - Email: {usuario.email}")
        print(f"   - Rol: 9 ({usuario.rol.nombre_rol if usuario.rol else 'Recepcion'})")
        print(f"   - PIN: {usuario.pin_acceso}")
        print(f"   - Contrasena: {password_plano}")
        print(f"   - RUT: {usuario.rut_usuario}")
        print(f"   - Sucursal: {usuario.sucursal.nombre_sucursal if usuario.sucursal else id_sucursal}")

    except Exception as e:
        db.rollback()
        print(f"[ERROR] Error al crear usuario de Gloria: {e}")
        raise e
    finally:
        db.close()

if __name__ == "__main__":
    seed_gloria()
