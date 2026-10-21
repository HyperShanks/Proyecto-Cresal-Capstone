# Variables de entorno (URLs, credenciales de BD)
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

# Localizar archivo .env en la raíz de backend de forma robusta
_BACKEND_DIR = Path(__file__).resolve().parent.parent
_ENV_FILE = _BACKEND_DIR / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_ENV_FILE) if _ENV_FILE.exists() else ".env",
        extra="ignore"
    )

    # Variables obligatorias que deben estar en tu archivo .env
    DATABASE_URL: str
    JWT_SECRET_KEY: str
    TOKEN_EXPIRE_MINUTES: int = 1440  # 24 horas para cubrir jornadas y turnos continuos
    ALGORITHM: str = "HS256"
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # Integración y Notificaciones Telegram (Gerencia)
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_GERENCIA_CHAT_ID: str = ""
    TELEGRAM_ENABLED: bool = True



# Instanciamos la clase para poder importarla en otros archivos
settings = Settings()