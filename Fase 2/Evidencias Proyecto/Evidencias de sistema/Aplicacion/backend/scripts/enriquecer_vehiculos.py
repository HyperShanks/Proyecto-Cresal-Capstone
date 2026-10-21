"""
backend/scripts/enriquecer_vehiculos.py
Redirección al script unificado oficial: backend/migracion_vehiculos.py
Permite compatibilidad directa si se ejecuta este archivo.
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from migracion_vehiculos import ejecutar_migracion

if __name__ == "__main__":
    print("\n[*] Ejecutando motor unificado de ingesta y enriquecimiento (migracion_vehiculos.py)...")
    ejecutar_migracion()
