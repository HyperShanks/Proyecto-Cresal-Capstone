# services/sku_service.py
# HU-2.4 — Servicio puro de generación de SKU para Activos Inventariados.
#
# Responsabilidad única: dado un nombre de categoría y un UUID de activo,
# produce un código SKU con el formato: [3-LETRAS-CAT]-[4-CHARS-UUID].
# Ejemplo: Motor + uuid "8a2f..."  →  MOT-8A2F
#
# Este módulo NO depende de SQLAlchemy ni de FastAPI, lo que facilita
# sus pruebas unitarias de forma aislada.

import unicodedata


def _normalizar_nombre(nombre: str) -> str:
    """
    Elimina tildes/diacríticos y convierte a mayúsculas.
    Ej: "Caja de Cambio" → "CAJA DE CAMBIO"
    """
    # Descompone caracteres Unicode (ej. á → a + combining accent)
    nfkd = unicodedata.normalize("NFKD", nombre)
    # Filtra los combinadores y recompone
    ascii_str = "".join(c for c in nfkd if not unicodedata.combining(c))
    return ascii_str.upper()


def generar_sku(nombre_categoria: str, id_activo_str: str) -> str:
    """
    Genera el SKU físico/QR del activo con el formato CRESAL:
        [3 primeras letras de la categoría]-[4 primeros chars del UUID sin guiones]

    Parámetros
    ----------
    nombre_categoria : str
        Nombre legible de la categoría (ej. "Motor", "Caja de Cambio").
    id_activo_str : str
        UUID del Activo_Inventariado ya persistido, como string.
        (ej. "8a2f1c0d-...")

    Retorna
    -------
    str
        SKU listo para guardar en la columna sku_qr_fisico.
        Ej: "MOT-8A2F" o "CAJ-F1C0"

    Notas
    -----
    - Se usan los primeros 4 caracteres del UUID (sin guiones) para maximizar
      la entropía sin alargar el código impreso.
    - El UUID es prácticamente único por naturaleza, por lo que no se necesita
      una consulta extra a la base de datos para garantizar unicidad.
    """
    # 1. Prefijo de categoría: primeras 3 letras, sin tildes, en mayúsculas
    categoria_normalizada = _normalizar_nombre(nombre_categoria)
    # Tomamos solo letras para ignorar espacios y caracteres especiales
    solo_letras = "".join(c for c in categoria_normalizada if c.isalpha())
    prefijo = solo_letras[:3] if len(solo_letras) >= 3 else solo_letras.ljust(3, "X")

    # 2. Sufijo: primeros 4 caracteres del UUID sin guiones, en mayúsculas
    uuid_limpio = id_activo_str.replace("-", "").upper()
    sufijo = uuid_limpio[:4]

    return f"{prefijo}-{sufijo}"
