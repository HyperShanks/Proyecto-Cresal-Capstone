import os
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient
import models
from sqlalchemy.pool import StaticPool
from sqlalchemy import event
import datetime

# Ajusta estas importaciones según la estructura real de tus módulos
from main import app
from database import Base, get_db

# 1. Configuración del motor de base de datos SQLite en memoria
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)

@event.listens_for(engine, "connect")
def add_sqlite_now(dbapi_connection, connection_record):
    # Le enseñamos a SQLite qué significa now() para que no colapse al simular PostgreSQL
    dbapi_connection.create_function("now", 0, lambda: datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 2. Fixture (scope="module") para levantar y destruir la estructura de la DB por módulo
@pytest.fixture(scope="module", autouse=True)
def setup_database():
    """
    Crea las tablas en la BD en memoria al iniciar cada módulo de pruebas
    y las destruye al finalizar.
    """
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

# 3. Fixture (scope="module") para proveer el TestClient con dependencias sobreescritas
@pytest.fixture(scope="module")
def client(setup_database):
    """
    Inyecta la dependencia de base de datos de pruebas (SQLite en memoria)
    sobreescribiendo get_db y provee el TestClient para las peticiones.
    """
    def override_get_db():
        try:
            db = TestingSessionLocal()
            yield db
        finally:
            db.close()
            
    app.dependency_overrides[get_db] = override_get_db
    
    with TestClient(app) as test_client:
        yield test_client
        
    # Buena práctica de QA: Limpiar overrides para evitar efectos colaterales en otras pruebas
    app.dependency_overrides.clear()
