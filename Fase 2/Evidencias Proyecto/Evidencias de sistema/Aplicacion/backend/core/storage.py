import os
from typing import Optional
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

supabase: Optional[Client] = None

try:
    if SUPABASE_URL and SUPABASE_KEY:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        print(f"[STORAGE] Conexión exitosa a Supabase en {SUPABASE_URL}.")
    else:
        print("⚠️ [STORAGE] SUPABASE_URL o SUPABASE_KEY no definidas.")
except Exception as e:
    print(f"❌ [STORAGE] Error al conectar con Supabase: {str(e)}")
    supabase = None

def get_supabase_client() -> Optional[Client]:
    return supabase
