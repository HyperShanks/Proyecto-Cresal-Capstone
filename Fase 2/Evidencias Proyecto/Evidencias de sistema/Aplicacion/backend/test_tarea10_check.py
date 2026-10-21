import asyncio
import httpx
import uuid

from main import app

BASE_URL = "http://testserver"

async def login(client, email, password="Password123!"):
    response = await client.post(f"{BASE_URL}/api/auth/login", json={"email": email, "password": password})
    response.raise_for_status()
    return response.json()["access_token"]

from database import SessionLocal
from models import Activo_Inventariado

def get_activo_disponible_db():
    db = SessionLocal()
    try:
        activo = db.query(Activo_Inventariado).filter(Activo_Inventariado.id_estado == 1, Activo_Inventariado.estado == 'Activo').first()
        if activo:
            return {"id_activo": str(activo.id_activo), "version_lock": activo.version_lock}
        return None
    finally:
        db.close()

async def intentar_reserva(client, token, id_activo, version_lock, id_vendedor):
    headers = {"Authorization": f"Bearer {token}"}
    payload = {
        "id_activo": id_activo,
        "version_lock_esperado": version_lock
    }
    response = await client.post(f"{BASE_URL}/api/v1/carrito/reservar", json=payload, headers=headers)
    return id_vendedor, response.status_code, response.json()

async def main():
    print("--- Prueba de Concurrencia (Stock Unitario) ---")
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url=BASE_URL) as client:
        try:
            token_admin = await login(client, "admin@cresal.cl")
            token_vendedor1 = await login(client, "carlos.mendoza@cresal.cl")
            token_vendedor2 = await login(client, "gastonzamoracc@gmail.com")
            
            activo = get_activo_disponible_db()
            if not activo:
                print("No hay activos disponibles para la prueba.")
                return
            
            id_activo = activo["id_activo"]
            version_lock = activo["version_lock"]
            print(f"Activo seleccionado: {id_activo} | Version Lock: {version_lock}")
            
            print("Lanzando 3 peticiones de reserva simultáneas...")
            resultados = await asyncio.gather(
                intentar_reserva(client, token_admin, id_activo, version_lock, "Admin"),
                intentar_reserva(client, token_vendedor1, id_activo, version_lock, "Vendedor 1"),
                intentar_reserva(client, token_vendedor2, id_activo, version_lock, "Vendedor 2"),
            )
            
            exitos = 0
            conflictos = 0
            for vendedor, status, data in resultados:
                print(f"{vendedor}: Status {status} | Respuesta: {data}")
                if status == 200:
                    exitos += 1
                elif status == 409:
                    conflictos += 1
                    
            if exitos == 1 and conflictos == 2:
                print("ÉXITO: Control de concurrencia funciona. Solo una reserva exitosa, el resto denegadas.")
            else:
                print(f"FALLO: Comportamiento anómalo. Exitos: {exitos}, Conflictos: {conflictos}")
                
            # Liberar la reserva al final para no afectar la DB
            if exitos == 1:
                # buscar quien gano y liberarlo
                for vendedor, status, data in resultados:
                    if status == 200:
                        # el endpoint liberar/{id}
                        # iteramos con el token admin, como admin puede hacerlo?
                        # mejor iterar y liberar con el respectivo token
                        if vendedor == "Admin": t = token_admin
                        elif vendedor == "Vendedor 1": t = token_vendedor1
                        else: t = token_vendedor2
                        await client.post(f"{BASE_URL}/api/v1/carrito/liberar/{id_activo}", headers={"Authorization": f"Bearer {t}"})
                        print("Reserva liberada para limpiar la BD.")
                        
        except Exception as e:
            print(f"Error en la prueba: {e}")

if __name__ == "__main__":
    asyncio.run(main())
