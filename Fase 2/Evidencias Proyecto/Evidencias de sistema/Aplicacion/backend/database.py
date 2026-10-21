# Usamos este archivo por un principio fundamental de la ingeniería de software llamado Separación de Responsabilidades (Separation of Concerns)
# No queremos mezclar las contraseñas y la lógica de conexión con las tablas o con las rutas de la API.

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from core.config import settings  # Importamos nuestra nueva configuración tipada

# Obtiene la URL de conexión segura directamente desde el objeto settings
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL
if SQLALCHEMY_DATABASE_URL.startswith("postgres://"):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace("postgres://", "postgresql://", 1)

# Crea el motor de base de datos
engine = create_engine(SQLALCHEMY_DATABASE_URL)

# Fábrica de sesiones para las consultas a la BD
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Clase base de la que heredarán todas tus tablas
Base = declarative_base()

# Dependencia para obtener la sesión de la base de datos
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()