# backend/seed_usuarios_roles.py
"""
Script para sincronizar y crear los usuarios para cada rol en la BD Supabase.
Garantiza que existan usuarios para los 7 roles con contraseñas conocidas (Password123!)
y PINs de acceso directo asignados.
"""

import uuid
from datetime import datetime, timezone
from database import SessionLocal
from models import Usuario, Rol, Sucursal
from core.security import hash_password

USUARIOS_A_SEMBRAR = [
    {
        "id_rol": 1,
        "email": "bodega@cresal.cl",
        "rut_usuario": "16.234.567-8",
        "nombres": "Juan Pablo",
        "apellidos": "Bodega Pérez",
        "password_plano": "Password123!",
        "pin_acceso": "1001",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 2,
        "email": "carlos.mendoza@cresal.cl",
        "rut_usuario": "19.876.543-2",
        "nombres": "Carlos",
        "apellidos": "Mendoza Silva",
        "password_plano": "Password123!",
        "pin_acceso": "2002",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 3,
        "email": "lorena.valenzuela@cresal.cl",
        "rut_usuario": "15.789.123-4",
        "nombres": "Lorena",
        "apellidos": "Valenzuela Castro",
        "password_plano": "Password123!",
        "pin_acceso": "3003",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 4,
        "email": "gerente@cresal.cl",
        "rut_usuario": "14.567.890-1",
        "nombres": "Roberto",
        "apellidos": "Gerente Silva",
        "password_plano": "Password123!",
        "pin_acceso": "4004",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 5,
        "email": "admin@cresal.cl",
        "rut_usuario": "11.111.111-1",
        "nombres": "Admin",
        "apellidos": "Sistema Cresal",
        "password_plano": "Password123!",
        "pin_acceso": "5005",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 6,
        "email": "gastonzamoracc@gmail.com",
        "rut_usuario": "21.337.385-4",
        "nombres": "Gastón Marcelo",
        "apellidos": "Zamora Herrera",
        "password_plano": "Password123!",
        "pin_acceso": "6006",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 7,
        "email": "marcela.online@cresal.cl",
        "rut_usuario": "12.345.678-9",
        "nombres": "Marcela",
        "apellidos": "Online Soto",
        "password_plano": "Password123!",
        "pin_acceso": "7007",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 8,
        "email": "gerenteauditor@cresal.cl",
        "rut_usuario": "11.222.222-1",
        "nombres": "Carlos",
        "apellidos": "Gerente Auditor",
        "password_plano": "Password123!",
        "pin_acceso": "8008",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 9,
        "email": "gloria@cresal.cl",
        "rut_usuario": "20.999.888-7",
        "nombres": "Gloria",
        "apellidos": "Recepción Patio",
        "password_plano": "RecepcionApp2026-16",
        "pin_acceso": "4598",
        "id_sucursal": 1,
        "estado": "Activo"
    },
    {
        "id_rol": 2,
        "email": "limache@cresal.cl",
        "rut_usuario": "77.888.999-4",
        "nombres": "Ventas",
        "apellidos": "Limache",
        "password_plano": "Password123!",
        "pin_acceso": "2020",
        "id_sucursal": 2,
        "estado": "Activo"
    }
]

def sembrar_usuarios():
    db = SessionLocal()
    try:
        print("=== INICIANDO SINCRONIZACIÓN DE USUARIOS POR ROL EN SUPABASE ===")
        
        # Verificar roles en BD
        roles = {r.id_rol: r.nombre_rol for r in db.query(Rol).all()}
        print(f"Roles encontrados en BD: {roles}")

        # Verificar sucursales en BD
        sucursales = {s.id_sucursal: s.nombre_sucursal for s in db.query(Sucursal).all()}
        print(f"Sucursales encontradas en BD: {sucursales}")

        for data in USUARIOS_A_SEMBRAR:
            email = data["email"]
            # Buscar si ya existe por email o por RUT
            usuario = db.query(Usuario).filter(
                (Usuario.email == email) | (Usuario.rut_usuario == data["rut_usuario"])
            ).first()

            pwd_hash = hash_password(data["password_plano"])

            if usuario:
                print(f"-> Actualizando usuario existente: {email} (Rol {data['id_rol']} - {roles.get(data['id_rol'])})")
                usuario.id_rol = data["id_rol"]
                usuario.id_sucursal = data["id_sucursal"]
                usuario.rut_usuario = data["rut_usuario"]
                usuario.nombres = data["nombres"]
                usuario.apellidos = data["apellidos"]
                usuario.email = email
                usuario.password_hash = pwd_hash
                usuario.pin_acceso = data["pin_acceso"]
                usuario.estado = data["estado"]
                usuario.fecha_actualizacion = datetime.now(timezone.utc)
            else:
                print(f"-> Creando nuevo usuario: {email} (Rol {data['id_rol']} - {roles.get(data['id_rol'])})")
                nuevo_usuario = Usuario(
                    id_usuario=uuid.uuid4(),
                    id_rol=data["id_rol"],
                    id_sucursal=data["id_sucursal"],
                    rut_usuario=data["rut_usuario"],
                    nombres=data["nombres"],
                    apellidos=data["apellidos"],
                    email=email,
                    password_hash=pwd_hash,
                    pin_acceso=data["pin_acceso"],
                    estado=data["estado"],
                    fecha_creacion=datetime.now(timezone.utc),
                    fecha_actualizacion=datetime.now(timezone.utc)
                )
                db.add(nuevo_usuario)

        db.commit()
        print("\n=== SINCRONIZACIÓN COMPLETADA CON ÉXITO ===")

        # Verificar usuarios finales
        print("\n=== LISTA FINAL DE USUARIOS EN SUPABASE ===")
        todos = db.query(Usuario).order_by(Usuario.id_rol).all()
        for u in todos:
            rol_name = u.rol.nombre_rol if u.rol else "Sin Rol"
            suc_name = u.sucursal.nombre_sucursal if u.sucursal else "Sin Sucursal"
            print(f"Rol {u.id_rol} ({rol_name:<15}) | Email: {u.email:<30} | PIN: {u.pin_acceso} | RUT: {u.rut_usuario:<13} | Nombre: {u.nombres} {u.apellidos} | Sucursal: {suc_name}")

    except Exception as e:
        db.rollback()
        print(f"Error al sembrar usuarios: {e}")
        raise e
    finally:
        db.close()

if __name__ == "__main__":
    sembrar_usuarios()
