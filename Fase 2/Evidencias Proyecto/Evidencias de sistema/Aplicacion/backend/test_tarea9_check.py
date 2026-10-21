import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_cors():
    print("--- Pruebas de CORS ---")
    response = client.options(
        "/",
        headers={
            "Origin": "http://origen-malicioso.com",
            "Access-Control-Request-Method": "GET"
        }
    )
    allowed_origin = response.headers.get("access-control-allow-origin")
    print(f"Origin permitido reportado: {allowed_origin}")
    if allowed_origin == "http://origen-malicioso.com" or allowed_origin == "*":
        print("FALLO: CORS está permitiendo orígenes no autorizados.")
    else:
        print("ÉXITO: CORS está restringido.")

def test_rate_limiting():
    print("\n--- Pruebas de Rate Limiting (PIN de Acceso) ---")
    import uuid
    dummy_uuid = str(uuid.uuid4())
    
    intentos = 0
    bloqueado = False
    
    for i in range(6):
        response = client.post(
            "/api/auth/login-pin",
            json={"id_usuario": dummy_uuid, "pin_acceso": "0000"}
        )
        intentos += 1
        if response.status_code == 429:
            print(f"Intento {intentos}: Bloqueado (429 Too Many Requests)")
            bloqueado = True
            break
        elif response.status_code == 401:
            print(f"Intento {intentos}: Rechazado por PIN inválido (401 Unauthorized)")
        else:
            print(f"Intento {intentos}: Status inesperado {response.status_code}")
            
    if not bloqueado:
        print("FALLO: No se implementó rate limiting tras 5 intentos fallidos.")
    else:
        print("ÉXITO: Rate limiting funcionando.")

if __name__ == "__main__":
    test_cors()
    test_rate_limiting()
