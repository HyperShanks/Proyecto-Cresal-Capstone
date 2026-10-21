import sys
import os
from sqlalchemy import text

# Asegurar que backend esté en el sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from database import engine

DDL_SCRIPT = """
-- 1. AUDITORÍA DE ANULACIONES EN ORDEN DE VENTA
ALTER TABLE "Orden_Venta"
  ADD COLUMN IF NOT EXISTS motivo_anulacion VARCHAR(100) NULL,
  ADD COLUMN IF NOT EXISTS observacion_anulacion TEXT NULL,
  ADD COLUMN IF NOT EXISTS id_usuario_anulacion UUID NULL REFERENCES "Usuario"("id_usuario") ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS fecha_anulacion TIMESTAMP WITH TIME ZONE NULL;

CREATE INDEX IF NOT EXISTS idx_orden_venta_fecha_anulacion 
  ON "Orden_Venta"(fecha_anulacion DESC) 
  WHERE estado_orden = 'Anulada';

-- 2. BITÁCORA FORENSE DE MOVIMIENTOS DE INVENTARIO
CREATE TABLE IF NOT EXISTS "Bitacora_Movimiento_Inventario" (
  id_bitacora SERIAL PRIMARY KEY,
  id_activo UUID NOT NULL REFERENCES "Activo_Inventariado"("id_activo") ON DELETE CASCADE,
  id_usuario UUID NOT NULL REFERENCES "Usuario"("id_usuario") ON DELETE RESTRICT,
  tipo_evento VARCHAR(50) NOT NULL,
  ubicacion_anterior VARCHAR(100) NULL,
  ubicacion_nueva VARCHAR(100) NULL,
  motivo VARCHAR(100) NOT NULL,
  observacion TEXT NOT NULL,
  fecha_registro TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bitacora_activo 
  ON "Bitacora_Movimiento_Inventario"(id_activo);

CREATE INDEX IF NOT EXISTS idx_bitacora_fecha 
  ON "Bitacora_Movimiento_Inventario"(fecha_registro DESC);

CREATE INDEX IF NOT EXISTS idx_bitacora_tipo 
  ON "Bitacora_Movimiento_Inventario"(tipo_evento);

-- 3. COLA Y BITÁCORA RESILIENTE DE NOTIFICACIONES DEL SISTEMA
CREATE TABLE IF NOT EXISTS "Notificacion_Sistema" (
  id_notificacion SERIAL PRIMARY KEY,
  canal VARCHAR(20) NOT NULL DEFAULT 'TELEGRAM',
  destinatario VARCHAR(100) NOT NULL,
  tipo_evento VARCHAR(50) NOT NULL,
  referencia_id VARCHAR(100) NOT NULL,
  mensaje TEXT NOT NULL,
  estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  intentos INTEGER NOT NULL DEFAULT 0,
  ultimo_error TEXT NULL,
  fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  fecha_envio TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_notif_estado_fecha 
  ON "Notificacion_Sistema"(estado, fecha_creacion DESC);

-- 4. AJUSTE PREVENTIVO ANTI-OVERFLOW EN OBSERVACIÓN DE ESTADO
ALTER TABLE "Activo_Inventariado" 
  ALTER COLUMN observacion_estado TYPE TEXT;
"""

def ejecutar_migracion():
    print("[MIGRACION] Iniciando migracion de Base de Datos para Tarea 23...")
    with engine.begin() as conn:
        for statement in DDL_SCRIPT.strip().split(";"):
            stmt_clean = statement.strip()
            if stmt_clean:
                print(f"  [SQL] Ejecutando: {stmt_clean[:60]}...")
                conn.execute(text(stmt_clean))
    print("[MIGRACION] Migracion completada exitosamente en la base de datos.")

if __name__ == "__main__":
    ejecutar_migracion()
