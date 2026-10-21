import asyncio
import httpx
import time
import statistics

BASE_URL = "http://testserver"

from main import app

async def login(client, email, password="Password123!"):
    response = await client.post(f"{BASE_URL}/api/auth/login", json={"email": email, "password": password})
    response.raise_for_status()
    return response.json()["access_token"]

async def make_request(client, token, idx):
    headers = {"Authorization": f"Bearer {token}"}
    start_time = time.perf_counter()
    # Peticion de lectura (catalogo)
    response = await client.get(f"{BASE_URL}/api/v1/inventario/buscar?estado=1&limit=50", headers=headers)
    end_time = time.perf_counter()
    duration_ms = (end_time - start_time) * 1000
    return response.status_code, duration_ms

async def main():
    print("--- Prueba de Carga y Estrés (20 Usuarios) ---")
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url=BASE_URL) as client:
        # Get one token to use for all requests in this synthetic test
        try:
            token = await login(client, "admin@cresal.cl")
        except Exception as e:
            print(f"Error al loguear: {e}")
            return
            
        print("Lanzando 20 peticiones de lectura al catálogo concurrentemente...")
        tasks = [make_request(client, token, i) for i in range(20)]
        results = await asyncio.gather(*tasks)
        
        status_codes = [r[0] for r in results]
        durations = [r[1] for r in results]
        
        errors = len([s for s in status_codes if s >= 400])
        error_rate = errors / len(status_codes) * 100
        
        durations.sort()
        # p95 index
        idx_p95 = int(len(durations) * 0.95)
        p95_time = durations[idx_p95]
        
        print(f"Resultados de Carga:")
        print(f"  Total peticiones: {len(status_codes)}")
        print(f"  Tasa de error: {error_rate:.2f}%")
        print(f"  Tiempo Promedio: {statistics.mean(durations):.2f} ms")
        print(f"  Tiempo Mediano (p50): {statistics.median(durations):.2f} ms")
        print(f"  Tiempo p95: {p95_time:.2f} ms")
        
        if error_rate < 1.0 and p95_time < 500:
            print("ÉXITO: La prueba de carga cumple con los criterios de aceptación (<1% error, p95 < 500ms).")
        else:
            print("FALLO: La prueba de carga no cumple con los criterios.")

if __name__ == "__main__":
    asyncio.run(main())
