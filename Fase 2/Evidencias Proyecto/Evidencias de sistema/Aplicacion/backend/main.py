from fastapi import FastAPI
from database import engine, Base
from routers import vehiculos, auth, tickets, bodega, inventario, ordenes, clientes, despachos, caja, carrito, gerencia, app_update
from fastapi.middleware.cors import CORSMiddleware
from core.exceptions import register_exception_handlers
import models
import os

# Le dice a SQLAlchemy que lea models.py y cree las tablas en pgAdmin
Base.metadata.create_all(bind=engine)

# Inicializamos la API de Cresal-SaaS
app = FastAPI(
    title="API Cresal-SaaS",
    description="Backend transaccional para gestión de inventario y barrera digital",
    version="1.0.10"
)

# Registrar Manejadores de Excepciones Globales y Sanitización (SPEC-HU-07)
register_exception_handlers(app)

# Configuración de CORS para permitir peticiones desde Flutter Web u otros orígenes
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Permite que cualquier frontend se conecte (ideal para desarrollo local)
    allow_credentials=True,
    allow_methods=["*"], # Permite GET, POST, PUT, DELETE, OPTIONS, etc.
    allow_headers=["*"],
)

# ==========================================
# CONFIGURACIÓN DE IA (Google Cloud Vision)
# ==========================================
# Prioridad de credenciales:
# 1. Variable de entorno ya definida (ej. en Render: GOOGLE_APPLICATION_CREDENTIALS)
# 2. Secret File de Render montado en /etc/secrets/vision-key.json
# 3. Archivo local en backend/vision-key.json o vision-key.json en cwd
if not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    key_in_script_dir = os.path.join(script_dir, "vision-key.json")
    if os.path.exists("/etc/secrets/vision-key.json"):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "/etc/secrets/vision-key.json"
    elif os.path.exists(key_in_script_dir):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = key_in_script_dir
    elif os.path.exists("vision-key.json"):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "vision-key.json"


# Un endpoint de prueba para saber que el servidor funciona
@app.get("/")
def read_root():
    return {"mensaje": "¡API de Cresal-SaaS en línea y Base de Datos conectada!"}

# Registrar las rutas de la aplicación
app.include_router(vehiculos.router)
app.include_router(auth.router)
app.include_router(tickets.router, prefix="/api/v1/tickets", tags=["Tickets de Soporte"])
app.include_router(bodega.router)
app.include_router(inventario.router)
app.include_router(inventario.ventas_router)
app.include_router(ordenes.router)
app.include_router(clientes.router)
app.include_router(despachos.router)
app.include_router(caja.router)
app.include_router(carrito.router, prefix="/api/v1/carrito", tags=["Carrito y Reserva Temporal"])
app.include_router(gerencia.router)
app.include_router(app_update.router)