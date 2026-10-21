"""
backend/migracion_vehiculos.py
==============================================================================
SCRIPT UNIFICADO DE INGESTA, ENRIQUECIMIENTO Y SECUENCIACIÓN VEHICULAR (SPEC-22)
==============================================================================
Combina y unifica la ingesta histórica con el enriquecimiento de columnas:
1. Sanitización de secuencia (descarta entradas no numéricas como 'concon', duplicados).
2. Si el vehículo YA EXISTE en BD:
   - Realiza UPDATE (enriquece) de las columnas faltantes: factura, fecha_ingreso,
     origen, color, numero_motor, destino, grua, observaciones, traccion.
   - Asegura la existencia y actualización de sus repuestos (Motor y Caja).
3. Si el vehículo NO EXISTE en BD:
   - Realiza INSERT completo de Vehiculo_Origen (13 columnas).
   - Crea sus activos inventariados (Motor SKU: MOT-{num}, Caja SKU: CAJ-{num}).
   - Registra Detalle_Motor y Detalle_Caja_Cambio con inferencia técnica avanzada.
4. Soporte para simulación (--dry-run) y limpieza previa opcional (--limpiar).
"""

import os
import re
import sys
import uuid
from datetime import datetime
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import text

# Importamos SQLAlchemy Session y los Modelos
from database import SessionLocal
from models import (
    Vehiculo_Origen, Activo_Inventariado, Detalle_Motor, Detalle_Caja_Cambio
)

load_dotenv()

PATENTES_GENERICAS = {
    "SPATENTE", "SINPATENTE", "SINPPU", "SPPU", "ERROR", 
    "MOTOR", "SN", "NAN", "NONE", "S/PATENTE", "S/PPU", 
    "SP", "SPP", ""
}

# ==============================================================================
# LOCALIZACIÓN AUTOMÁTICA DEL ARCHIVO EXCEL
# ==============================================================================

def buscar_archivo_excel():
    """
    Localiza automáticamente la matriz Excel 'Matriz Los Pinos.xlsx' o 'MatrizLosPinos.xlsx'.
    Prioridad:
    1. Argumento de línea de comandos (ej: python migracion_vehiculos.py "ruta/archivo.xlsx")
    2. Directorio actual o carpeta backend/
    3. Carpeta Descargas del usuario
    """
    # 1. Argumentos CLI
    for arg in sys.argv[1:]:
        if not arg.startswith("--") and arg.lower().endswith(".xlsx") and os.path.exists(arg):
            return os.path.abspath(arg)

    # 2. Rutas candidatas
    posibles_nombres = [
        "Matriz Los Pinos.xlsx",
        "MatrizLosPinos.xlsx",
        "Matriz_Los_Pinos.xlsx",
        "matriz.xlsx"
    ]
    carpetas = [
        os.path.dirname(os.path.abspath(__file__)),
        os.getcwd(),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."),
        r"C:\Users\gasto\Downloads"
    ]

    for carp in carpetas:
        for nom in posibles_nombres:
            ruta = os.path.join(carp, nom)
            if os.path.exists(ruta):
                return os.path.abspath(ruta)

    return None


# ==============================================================================
# FUNCIONES DE EXTRACCIÓN INTELIGENTE (ESTANDARIZADAS CON EL FRONTEND)
# ==============================================================================

def limpiar_patente(valor_raw, patentes_registradas, patente_existente=None):
    if pd.isna(valor_raw):
        return None

    limpio = re.sub(r'[^A-Z0-9]', '', str(valor_raw).upper().strip())

    if limpio in PATENTES_GENERICAS or any(tag in limpio for tag in ["SPATENTE", "SINPPU", "ERROR"]):
        return None

    # Si coincide exactamente con la patente que ya tenía el vehículo en BD, mantenerla
    if patente_existente and limpio == re.sub(r'[^A-Z0-9]', '', str(patente_existente).upper().strip()):
        return patente_existente[:10]

    if limpio in patentes_registradas:
        conteo = patentes_registradas[limpio]
        patentes_registradas[limpio] += 1
        patente_ajustada = f"{limpio}-D{conteo}"
        return patente_ajustada[:10]
    else:
        patentes_registradas[limpio] = 1
        return limpio[:10]


def procesar_anio(valor_raw):
    try:
        if pd.isna(valor_raw):
            return 2000
        val = int(float(valor_raw))
        return val if 1950 <= val <= 2030 else 2000
    except (ValueError, TypeError):
        return 2000


def procesar_fecha_ingreso(valor_raw):
    """Parsea la fecha de ingreso físico en patio (Columna D). Defecto: hoy."""
    if pd.isna(valor_raw):
        return datetime.now().date()
    if isinstance(valor_raw, (datetime, pd.Timestamp)):
        return valor_raw.date()
    try:
        dt = pd.to_datetime(valor_raw, errors='coerce')
        if pd.notnull(dt):
            return dt.date()
    except Exception:
        pass
    return datetime.now().date()


def extraer_cilindrada(modelo_raw, obs_raw=""):
    """
    Extrae la cilindrada del vehículo analizando modelo y observaciones con regex.
    Ejemplos: 'SORENTO 2,4' -> '2.4', 'RIO 4 EX 1.4 AUT' -> '1.4', '1600cc' -> '1.6'
    """
    texto = f"{modelo_raw or ''} {obs_raw or ''}".strip()
    if not texto:
        return "S/A"

    # 1. Patrón decimal estándar con punto o coma (ej: 1.4, 2,4, 1.6L, 1.6I, 2.0i, 3.8 AUT)
    m_dec = re.search(r'\b([0-9][.,][0-9])(?:[a-zA-Z\s])?\b', texto)
    if m_dec:
        return m_dec.group(1).replace(',', '.')

    # 2. Formato centímetros cúbicos (ej: 1600cc, 2000 cc, 2400)
    m_cc = re.search(r'\b(1[0-9]{3}|2[0-9]{3}|3[0-9]{3})\s*(?:cc)?\b', texto, re.IGNORECASE)
    if m_cc:
        cc_val = int(m_cc.group(1))
        return str(round(cc_val / 1000, 1))

    return "S/A"


def extraer_transmision(modelo_raw, obs_raw=""):
    """Determina si la transmisión es 'Automática' o 'Mecánica'."""
    texto = f"{modelo_raw or ''} {obs_raw or ''}".upper()
    if re.search(r'\b(AUT|AUTOMATICA|AUTOMATICO|AT|A/T|CVT|TIPTRONIC|DSG)\b', texto):
        return "Automática"
    return "Mecánica"


def extraer_combustible(modelo_raw, obs_raw=""):
    """Determina el combustible: 'Gasolina', 'Diésel' o 'Híbrido'."""
    texto = f"{modelo_raw or ''} {obs_raw or ''}".upper()
    
    # 1. Híbridos
    if re.search(r'\b(HIBRIDO|HYBRID|PRIUS|HEV|PHEV)\b', texto):
        return "Híbrido"

    # 2. Nomenclaturas técnicas directas de motores Diésel
    if re.search(r'\b(DIESEL|PETROLEO|PETROLERO|HDI|CRDI|TDI|D-4D|TD|TURBO DIESEL|CDI|DCI|TDCI|D4HA|4D56|YD25)\b', texto):
        return "Diésel"
    
    # 3. Camionetas / Utilitarios en Chile históricamente diésel
    if any(k in texto for k in [
        'DMAX', 'D-MAX', 'HILUX', 'ACTYON', 'L200', 'L-200', 'NAVARA', 
        'NP300', 'AMAROK', 'RANGER', 'BT-50', 'BT50', 'TERRANO', 
        'BOXER', 'DUCATO', 'PORTER', 'CANTER'
    ]):
        return "Diésel"

    # 4. Automóviles convencionales
    return "Gasolina"


def extraer_traccion(marca_raw, modelo_raw, obs_raw=""):
    """Determina la tracción estandarizada según OpcionesTraccion del frontend."""
    m_up = str(marca_raw or '').upper()
    texto = f"{modelo_raw or ''} {obs_raw or ''}".upper()

    # 1. 4x4 Permanente (AWD)
    if 'SUBARU' in m_up or re.search(r'\b(AWD|4MOTION|ALL GRIP|QUATTRO|4MATIC|PERMANENTE)\b', texto):
        return "4x4 Permanente (AWD)"

    # 2. 4x4 Conectable (4WD)
    if re.search(r'\b(4X4|4WD|CONECTABLE)\b', texto):
        return "4x4 Conectable (4WD)"

    # 3. 4x2 Trasera
    if any(k in texto for k in [
        'DMAX', 'D-MAX', 'HILUX', 'L200', 'L-200', 'NAVARA', 'NP300', 'AMAROK', 
        'RANGER', 'BT-50', 'TERRANO', 'PORTER', 'H-1', 'H1', 'CANTER', 'NPR', 
        'NKR', 'D100', 'C-10', 'SILVERADO', 'F150', 'F-150'
    ]):
        return "4x2 Trasera"
    if any(k in m_up for k in ['BMW', 'MERCEDES']) and not any(k in texto for k in ['A-CLASS', 'CLASE A', 'B-CLASS', 'CLASE B']):
        return "4x2 Trasera"

    # 4. 4x2 Delantera (defecto para vehículos ligeros)
    return "4x2 Delantera"


def limpiar_numero_motor(motor_raw, obs_raw=""):
    """Sanitiza el número de motor extrayendo datos válidos."""
    if pd.notnull(motor_raw):
        s = str(motor_raw).strip()
        if s and s.upper() not in ["NAN", "NONE", "SN", "S/N", "S/A", "SIN NUMERO", "SIN DATO", "0"]:
            return s[:100]

    # Buscar en observaciones si dice "MOTOR: XXX"
    if pd.notnull(obs_raw):
        m = re.search(r'MOTOR\s*[:#]?\s*([A-Z0-9\-]+)', str(obs_raw).upper())
        if m:
            candidato = m.group(1).strip()
            if candidato not in ["SN", "S/N", "S/A"]:
                return candidato[:100]

    return "S/A"


def limpiar_marca(marca_raw):
    """Corrige errores ortográficos y normaliza marcas comunes."""
    if not marca_raw or pd.isna(marca_raw):
        return "DESCONOCIDA"
    
    m = str(marca_raw).strip().upper()
    correcciones = {
        "VOLSKWAGEN": "VOLKSWAGEN",
        "SSANYONG": "SSANGYONG",
        "SSANG YONG": "SSANGYONG",
        "CHEVROLET ": "CHEVROLET",
        "MERCEDEZ": "MERCEDES-BENZ",
        "MERCEDES BENZ": "MERCEDES-BENZ",
        "GREATWALL": "GREAT WALL",
    }
    return correcciones.get(m, m[:100])


# ==============================================================================
# AUDITORÍA Y SECUENCIACIÓN DE NÚMEROS DE INGRESO
# ==============================================================================

def sanitizar_secuencia_ingresos(df, col_indice):
    """
    Audita la Columna A del Excel.
    Descarta textos no numéricos ('concon', etc.) y duplicados sin correlatividad libre.
    Repara huecos aislados interpolables.
    """
    total_filas = len(df)
    
    def parse_int_seguro(v):
        if pd.isna(v):
            return None
        s = str(v).strip()
        if not s:
            return None
        try:
            n = int(float(s))
            return n if n > 0 else None
        except (ValueError, TypeError):
            return None

    raw_vals = [df.iloc[i][col_indice] for i in range(total_filas)]
    parsed_vals = [parse_int_seguro(v) for v in raw_vals]

    conteo_numeros = {}
    for v in parsed_vals:
        if v is not None:
            conteo_numeros[v] = conteo_numeros.get(v, 0) + 1

    candidatos = [None] * total_filas
    vistos = set()
    ultimo_valido = 0

    for i in range(total_filas):
        v = parsed_vals[i]
        if v is None:
            candidatos[i] = None
        else:
            if v in vistos:
                candidatos[i] = None
            elif v <= ultimo_valido and conteo_numeros[v] > 1:
                candidatos[i] = None
            elif v <= ultimo_valido:
                candidatos[i] = None
            else:
                candidatos[i] = v
                vistos.add(v)
                ultimo_valido = v

    resolucion = [None] * total_filas
    acciones = {}

    i = 0
    while i < total_filas:
        if candidatos[i] is not None:
            resolucion[i] = candidatos[i]
            acciones[i] = ("CONSERVADO", f"Valor original {candidatos[i]}")
            i += 1
        else:
            i_start = i
            while i < total_filas and candidatos[i] is None:
                i += 1
            i_end = i - 1
            k = i_end - i_start + 1

            i_prev = i_start - 1
            i_next = i_end + 1

            A = resolucion[i_prev] if i_prev >= 0 else None
            B = candidatos[i_next] if i_next < total_filas else None

            interpolable = False
            if A is not None and B is not None and B > A and (B - A == k + 1):
                interpolable = True
                for j in range(i_start, i_end + 1):
                    val_interp = A + (j - i_start + 1)
                    resolucion[j] = val_interp
                    raw_str = str(raw_vals[j])
                    acciones[j] = ("REPARADO", f"Original '{raw_str}' interpolado a {val_interp}")
            elif A is None and B is not None and (B - k >= 1):
                interpolable = True
                for j in range(i_start, i_end + 1):
                    val_interp = B - (i_end - j + 1)
                    resolucion[j] = val_interp
                    raw_str = str(raw_vals[j])
                    acciones[j] = ("REPARADO", f"Original '{raw_str}' interpolado a {val_interp}")
            
            if not interpolable:
                for j in range(i_start, i_end + 1):
                    raw_str = str(raw_vals[j])
                    resolucion[j] = None
                    if parsed_vals[j] is None:
                        acciones[j] = ("IGNORADO", f"No numérico '{raw_str}' descartado (ej. concon).")
                    else:
                        acciones[j] = ("IGNORADO", f"Número '{raw_str}' descartado sin correlatividad libre.")

    filas_validas = []
    reporte = {
        "total_original": total_filas,
        "conservados": 0,
        "reparados": 0,
        "descartados": 0,
        "detalles_reparados": [],
        "detalles_descartados": [],
    }

    ingresos_asignados = set()

    for idx in range(total_filas):
        val_res = resolucion[idx]
        tipo_acc, detalle = acciones[idx]
        fila_excel = idx + 2
        
        if val_res is not None and val_res not in ingresos_asignados:
            ingresos_asignados.add(val_res)
            row_dict = df.iloc[idx].to_dict()
            row_dict["_numero_ingreso_limpio"] = str(val_res)
            row_dict["_fila_original_excel"] = fila_excel
            filas_validas.append(row_dict)
            
            if tipo_acc == "REPARADO":
                reporte["reparados"] += 1
                reporte["detalles_reparados"].append((fila_excel, detalle))
            else:
                reporte["conservados"] += 1
        else:
            reporte["descartados"] += 1
            reporte["detalles_descartados"].append((fila_excel, detalle))

    df_limpio = pd.DataFrame(filas_validas)
    return df_limpio, reporte


def limpiar_base_datos(db):
    """Elimina la ingesta previa si se pasa el flag explícito --limpiar."""
    print("\n" + "=" * 76)
    print(" [!] ADVERTENCIA: LIMPIEZA TOTAL DE INGESTA PREVIA EN BASE DE DATOS")
    print("=" * 76)
    try:
        res_mot = db.execute(text('DELETE FROM "Detalle_Motor";'))
        res_caj = db.execute(text('DELETE FROM "Detalle_Caja_Cambio";'))
        print(f"[*] Registros eliminados de Detalle_Motor: {res_mot.rowcount}")
        print(f"[*] Registros eliminados de Detalle_Caja_Cambio: {res_caj.rowcount}")

        res_act = db.execute(text('DELETE FROM "Activo_Inventariado" WHERE id_vehiculo IS NOT NULL;'))
        print(f"[*] Registros eliminados de Activo_Inventariado (Motores y Cajas): {res_act.rowcount}")

        res_veh = db.execute(text('DELETE FROM "Vehiculo_Origen";'))
        print(f"[*] Registros eliminados de Vehiculo_Origen: {res_veh.rowcount}")

        db.commit()
        print("✅ Limpieza completada. Base de datos vacía para reingesta.\n")
    except Exception as e:
        db.rollback()
        print(f"❌ Error al limpiar base de datos: {e}")
        raise e


# ==============================================================================
# EJECUCIÓN PRINCIPAL DE LA INGESTA / ENRIQUECIMIENTO (UPSERT)
# ==============================================================================

def ejecutar_migracion():
    archivo_excel = buscar_archivo_excel()

    if not archivo_excel or not os.path.exists(archivo_excel):
        print("\n[!] Error crítico: No se encontró el archivo matriz Excel.")
        print("    Asegúrate de colocar 'Matriz Los Pinos.xlsx' en la carpeta 'backend/'")
        print("    O ejecútalo pasando la ruta como parámetro:")
        print("    python migracion_vehiculos.py \"C:\\ruta\\Matriz Los Pinos.xlsx\"\n")
        return

    es_dry_run = "--dry-run" in sys.argv or "--simulacion" in sys.argv
    es_limpiar = "--limpiar" in sys.argv or "--reset" in sys.argv

    print("\n" + "=" * 76)
    print(" SCRIPT UNIFICADO DE INGESTA Y ENRIQUECIMIENTO VEHICULAR (CRESAL SAAS)")
    print("=" * 76)
    print(f"[*] Archivo Excel origen : {archivo_excel}")
    print(f"[*] Modo de ejecución    : {'SIMULACIÓN (dry-run, no altera BD)' if es_dry_run else 'UPSERT REAL EN BD'}")
    print("=" * 76)

    print("\n[+] Leyendo hoja Excel...")
    df = pd.read_excel(archivo_excel)
    df = df.dropna(how='all').reset_index(drop=True)

    col_indice = df.columns[0]
    col_anio = None
    col_motor = None
    col_obs = None

    for c in df.columns:
        c_str = str(c).lower()
        if "2017" in c_str or "año" in c_str or "anio" in c_str or (isinstance(c, int) and 1990 <= c <= 2030):
            col_anio = c
        if "motor" in c_str:
            col_motor = c
        if "observ" in c_str:
            col_obs = c

    # Fallbacks posicionales
    if col_anio is None and len(df.columns) > 7:
        col_anio = df.columns[7]
    if col_motor is None and len(df.columns) > 9:
        col_motor = df.columns[9]
    if col_obs is None and len(df.columns) > 12:
        col_obs = df.columns[12]

    print(f"[*] Columnas mapeadas: N° Ingreso='{col_indice}', Año='{col_anio}', Motor='{col_motor}', Obs='{col_obs}'")

    print("\n" + "=" * 76)
    print(" 1. AUDITORÍA Y SECUENCIACIÓN DE NÚMEROS DE INGRESO (COLUMNA A)")
    print("=" * 76)
    df_limpio, reporte = sanitizar_secuencia_ingresos(df, col_indice)

    print(f"[*] Total de filas originales en Excel : {reporte['total_original']}")
    print(f"[*] Registros numéricos conservados   : {reporte['conservados']}")
    print(f"[*] Registros reparados (huecos 'x')   : {reporte['reparados']}")
    print(f"[*] Registros descartados / omitidos   : {reporte['descartados']} (ej: 'concon', no numéricos)")
    print("=" * 76 + "\n")

    print("[+] Conectando a la base de datos PostgreSQL...")
    db = SessionLocal()
    
    try:
        if es_limpiar and not es_dry_run:
            limpiar_base_datos(db)

        print("[+] Cargando registros existentes de Vehículos y Repuestos desde BD...")
        vehiculos_db = db.query(Vehiculo_Origen).all()
        vehiculos_map = {str(v.numero_ingreso).strip(): v for v in vehiculos_db}
        
        activos_db = db.query(Activo_Inventariado).all()
        activos_map = {(a.id_vehiculo, a.id_categoria): a for a in activos_db}

        detalles_motor_db = db.query(Detalle_Motor).all()
        detalles_motor_map = {dm.id_activo: dm for dm in detalles_motor_db}

        detalles_caja_db = db.query(Detalle_Caja_Cambio).all()
        detalles_caja_map = {dc.id_activo: dc for dc in detalles_caja_db}
        
        print(f"[+] Estado actual en BD: {len(vehiculos_map)} vehículos y {len(activos_map)} repuestos registrados.")

        # Cargar diccionario de patentes registradas para no duplicar sufijos
        patentes_registradas = {}
        for v in vehiculos_db:
            if v.patente and not v.patente.startswith("SPPU-"):
                base_pat = v.patente.split("-D")[0]
                patentes_registradas[base_pat] = patentes_registradas.get(base_pat, 0) + 1

        total_a_procesar = len(df_limpio)
        print(f"[+] Iniciando procesamiento unificado de {total_a_procesar} registros válidos...\n")

        # Contadores de operaciones
        vehiculos_actualizados = 0
        vehiculos_creados = 0
        vehiculos_sin_cambios = 0
        vehiculos_inactivos = 0
        motores_creados = 0
        cajas_creadas = 0
        detalles_actualizados = 0

        # Contadores de deducción técnica
        conteo_cilindradas = 0
        conteo_motores_reales = 0
        conteo_automaticas = 0
        conteo_mecanicas = 0
        conteo_diesel = 0
        conteo_gasolina = 0
        conteo_hibrido = 0
        conteo_4x2_delantera = 0
        conteo_4x2_trasera = 0
        conteo_4x4_conectable = 0
        conteo_4x4_permanente = 0

        BATCH_SIZE = 250

        for idx, row in df_limpio.iterrows():
            num_ingreso_final = str(row["_numero_ingreso_limpio"]).strip()
            
            # Verificar si ya existe en BD para preservar su patente
            vehiculo_previo = vehiculos_map.get(num_ingreso_final)
            patente_existente_bd = vehiculo_previo.patente if vehiculo_previo else None

            patente_final = limpiar_patente(row.get("Patente"), patentes_registradas, patente_existente_bd)
            if not patente_final:
                patente_final = f"SPPU-{num_ingreso_final}"

            marca_val = str(row.get("Marca")).strip() if pd.notnull(row.get("Marca")) else ""
            modelo_val = str(row.get("Modelo")).strip() if pd.notnull(row.get("Modelo")) else ""
            obs_val = str(row.get(col_obs)).strip() if col_obs and pd.notnull(row.get(col_obs)) else ""
            anio_final = procesar_anio(row.get(col_anio)) if col_anio else 2000

            # ------------------------------------------------------------------
            # COLUMNAS MATRIZ CENTRAL (A a M - SPEC-22)
            # ------------------------------------------------------------------
            factura_raw = row.get("Factura")
            factura_val = str(factura_raw).strip()[:50] if pd.notnull(factura_raw) and str(factura_raw).strip().upper() not in ["NAN", "NONE", ""] else None
            
            fecha_ingreso_val = procesar_fecha_ingreso(row.get("Fecha ingreso"))
            
            origen_raw = row.get("Origen")
            origen_val = str(origen_raw).strip().upper()[:100] if pd.notnull(origen_raw) and str(origen_raw).strip().upper() not in ["NAN", "NONE", ""] else None
            
            color_raw = row.get("Color")
            color_val = str(color_raw).strip().upper()[:50] if pd.notnull(color_raw) and str(color_raw).strip().upper() not in ["NAN", "NONE", ""] else None
            
            destino_raw = row.get("Destino")
            destino_val = str(destino_raw).strip().upper()[:50] if pd.notnull(destino_raw) and str(destino_raw).strip().upper() not in ["NAN", "NONE", ""] else "DESARME"
            
            grua_raw = row.get("GRUA")
            grua_val = str(grua_raw).strip().upper()[:100] if pd.notnull(grua_raw) and str(grua_raw).strip().upper() not in ["NAN", "NONE", ""] else None
            
            obs_final = obs_val if obs_val and obs_val.upper() not in ["NAN", "NONE", ""] else None

            # ------------------------------------------------------------------
            # EXTRACCIÓN AVANZADA ESTANDARIZADA
            # ------------------------------------------------------------------
            cilindrada_final = extraer_cilindrada(modelo_val, obs_val)
            transmision_final = extraer_transmision(modelo_val, obs_val)
            combustible_final = extraer_combustible(modelo_val, obs_val)
            traccion_final = extraer_traccion(marca_val, modelo_val, obs_val)
            numero_motor_final = limpiar_numero_motor(row.get(col_motor) if col_motor else None, obs_val)

            # Estadísticas técnicas
            if cilindrada_final != "S/A":
                conteo_cilindradas += 1
            if numero_motor_final != "S/A":
                conteo_motores_reales += 1
            if transmision_final == "Automática":
                conteo_automaticas += 1
            else:
                conteo_mecanicas += 1

            if combustible_final == "Diésel":
                conteo_diesel += 1
            elif combustible_final == "Híbrido":
                conteo_hibrido += 1
            else:
                conteo_gasolina += 1

            if traccion_final == "4x4 Permanente (AWD)":
                conteo_4x4_permanente += 1
            elif traccion_final == "4x4 Conectable (4WD)":
                conteo_4x4_conectable += 1
            elif traccion_final == "4x2 Trasera":
                conteo_4x2_trasera += 1
            else:
                conteo_4x2_delantera += 1

            # Detección de filas sin datos vehiculares mínimos
            tiene_marca = bool(marca_val) and marca_val.upper() not in ["NAN", "NONE", "DESCONOCIDA", "S/I", "S/A", "SIN DATOS"]
            tiene_modelo = bool(modelo_val) and modelo_val.upper() not in ["NAN", "NONE", "DESCONOCIDO", "S/I", "S/A", "SIN DATOS"]
            tiene_patente = bool(patente_final) and not patente_final.startswith("SPPU-")
            tiene_motor = numero_motor_final != "S/A"

            es_sin_datos = not (tiene_marca or tiene_modelo or tiene_patente or tiene_motor)

            if es_sin_datos:
                estado_vehiculo = "Inactivo"
                marca_final = "SIN INFORMACION (HISTORICO)"
                modelo_final = "S/I"
                estado_activo = "Inactivo"
                id_estado_activo = 4  # De Baja / Inactivo
            else:
                estado_vehiculo = "Activo"
                marca_final = limpiar_marca(marca_val) if tiene_marca else "DESCONOCIDA"
                modelo_final = modelo_val[:100] if tiene_modelo else "DESCONOCIDO"
                estado_activo = "Activo"
                id_estado_activo = 5  # Pendiente de Paletizado / Desarmado

            # ==================================================================
            # CASO A: EL VEHÍCULO YA EXISTE EN BD -> ACTUALIZAR (ENRIQUECER)
            # ==================================================================
            if num_ingreso_final in vehiculos_map:
                vehiculo = vehiculos_map[num_ingreso_final]
                id_vehiculo = vehiculo.id_vehiculo
                cambio_vehiculo = False

                if factura_val and vehiculo.factura != factura_val:
                    vehiculo.factura = factura_val
                    cambio_vehiculo = True

                if fecha_ingreso_val and vehiculo.fecha_ingreso != fecha_ingreso_val:
                    vehiculo.fecha_ingreso = fecha_ingreso_val
                    cambio_vehiculo = True

                if origen_val and vehiculo.origen != origen_val:
                    vehiculo.origen = origen_val
                    cambio_vehiculo = True

                if color_val and vehiculo.color != color_val:
                    vehiculo.color = color_val
                    cambio_vehiculo = True

                if numero_motor_final != "S/A" and vehiculo.numero_motor != numero_motor_final:
                    vehiculo.numero_motor = numero_motor_final
                    cambio_vehiculo = True

                if destino_val and vehiculo.destino != destino_val:
                    vehiculo.destino = destino_val
                    cambio_vehiculo = True

                if grua_val and vehiculo.grua != grua_val:
                    vehiculo.grua = grua_val
                    cambio_vehiculo = True

                if obs_final and vehiculo.observaciones != obs_final:
                    vehiculo.observaciones = obs_final
                    cambio_vehiculo = True

                if traccion_final and vehiculo.traccion != traccion_final:
                    vehiculo.traccion = traccion_final
                    cambio_vehiculo = True

                if patente_final and not patente_final.startswith("SPPU-") and (not vehiculo.patente or vehiculo.patente.startswith("SPPU-")):
                    vehiculo.patente = patente_final
                    cambio_vehiculo = True

                if marca_final != "DESCONOCIDA" and (not vehiculo.marca or vehiculo.marca in ["DESCONOCIDA", "S/I"]):
                    vehiculo.marca = marca_final
                    cambio_vehiculo = True

                if modelo_final != "DESCONOCIDO" and (not vehiculo.modelo or vehiculo.modelo in ["DESCONOCIDO", "S/I"]):
                    vehiculo.modelo = modelo_final
                    cambio_vehiculo = True

                if anio_final and anio_final != 2000 and (not vehiculo.anio or vehiculo.anio == 2000):
                    vehiculo.anio = anio_final
                    cambio_vehiculo = True

                if cambio_vehiculo:
                    vehiculo.fecha_actualizacion = datetime.now()
                    vehiculos_actualizados += 1
                else:
                    vehiculos_sin_cambios += 1

            # ==================================================================
            # CASO B: EL VEHÍCULO NO EXISTE EN BD -> INSERTAR COMPLETO
            # ==================================================================
            else:
                id_vehiculo = uuid.uuid4()
                nuevo_vehiculo = Vehiculo_Origen(
                    id_vehiculo=id_vehiculo,
                    numero_ingreso=num_ingreso_final,
                    patente=patente_final,
                    vin=None,
                    factura=factura_val,
                    fecha_ingreso=fecha_ingreso_val,
                    origen=origen_val,
                    marca=marca_final,
                    modelo=modelo_final,
                    anio=anio_final,
                    color=color_val,
                    numero_motor=numero_motor_final if numero_motor_final != "S/A" else None,
                    destino=destino_val,
                    grua=grua_val,
                    observaciones=obs_final,
                    traccion=traccion_final,
                    estado=estado_vehiculo,
                    fecha_creacion=datetime.now()
                )
                db.add(nuevo_vehiculo)
                db.flush()  # Garantiza que el vehículo exista en PostgreSQL antes de crear sus repuestos
                vehiculos_map[num_ingreso_final] = nuevo_vehiculo
                vehiculos_creados += 1
                if es_sin_datos:
                    vehiculos_inactivos += 1

            # ==================================================================
            # GESTIÓN DE REPUESTOS EN INVENTARIO (MOTOR Y CAJA DE CAMBIO)
            # ==================================================================
            
            # 1. MOTOR (Categoría 1) -> SKU: MOT-{num_ingreso_final}
            if (id_vehiculo, 1) not in activos_map:
                id_motor = uuid.uuid4()
                activo_motor = Activo_Inventariado(
                    id_activo=id_motor,
                    sku_qr_fisico=f"MOT-{num_ingreso_final}",
                    id_categoria=1,
                    id_estado=id_estado_activo,
                    id_sucursal_actual=1,
                    id_vehiculo=id_vehiculo,
                    estado=estado_activo,
                    fecha_creacion=datetime.now(),
                    qr_impreso=False,
                    version_lock=1
                )
                db.add(activo_motor)
                db.flush()  # Garantiza que el Activo_Inventariado exista antes de Detalle_Motor

                detalle_motor = Detalle_Motor(
                    id_activo=id_motor,
                    numero_motor=numero_motor_final,
                    cilindrada=cilindrada_final,
                    combustible=combustible_final,
                    transmision_tipo=transmision_final,
                )
                db.add(detalle_motor)
                activos_map[(id_vehiculo, 1)] = activo_motor
                detalles_motor_map[id_motor] = detalle_motor
                motores_creados += 1
            else:
                # Motor ya existía: enriquecer detalle técnico si tenía datos vacíos o 'S/A'
                act_m = activos_map[(id_vehiculo, 1)]
                det_m = detalles_motor_map.get(act_m.id_activo)
                if det_m:
                    det_cambio = False
                    if cilindrada_final != "S/A" and (not det_m.cilindrada or det_m.cilindrada == "S/A"):
                        det_m.cilindrada = cilindrada_final
                        det_cambio = True
                    if combustible_final and (not det_m.combustible or det_m.combustible == "Gasolina") and combustible_final != "Gasolina":
                        det_m.combustible = combustible_final
                        det_cambio = True
                    if transmision_final and (not det_m.transmision_tipo or det_m.transmision_tipo == "Mecánica") and transmision_final != "Mecánica":
                        det_m.transmision_tipo = transmision_final
                        det_cambio = True
                    if numero_motor_final != "S/A" and (not det_m.numero_motor or det_m.numero_motor == "S/A"):
                        det_m.numero_motor = numero_motor_final
                        det_cambio = True
                    if det_cambio:
                        detalles_actualizados += 1
                else:
                    nuevo_dm = Detalle_Motor(
                        id_activo=act_m.id_activo,
                        numero_motor=numero_motor_final,
                        cilindrada=cilindrada_final,
                        combustible=combustible_final,
                        transmision_tipo=transmision_final,
                    )
                    db.add(nuevo_dm)
                    detalles_motor_map[act_m.id_activo] = nuevo_dm
                    detalles_actualizados += 1

            # 2. CAJA DE CAMBIOS (Categoría 2) -> SKU: CAJ-{num_ingreso_final}
            if (id_vehiculo, 2) not in activos_map:
                id_caja = uuid.uuid4()
                activo_caja = Activo_Inventariado(
                    id_activo=id_caja,
                    sku_qr_fisico=f"CAJ-{num_ingreso_final}",
                    id_categoria=2,
                    id_estado=id_estado_activo,
                    id_sucursal_actual=1,
                    id_vehiculo=id_vehiculo,
                    estado=estado_activo,
                    fecha_creacion=datetime.now(),
                    qr_impreso=False,
                    version_lock=1
                )
                db.add(activo_caja)
                db.flush()  # Garantiza que el Activo_Inventariado exista antes de Detalle_Caja_Cambio

                detalle_caja = Detalle_Caja_Cambio(
                    id_activo=id_caja,
                    transmision_tipo=transmision_final,
                )
                db.add(detalle_caja)
                activos_map[(id_vehiculo, 2)] = activo_caja
                detalles_caja_map[id_caja] = detalle_caja
                cajas_creadas += 1
            else:
                # Caja ya existía: verificar transmisión
                act_c = activos_map[(id_vehiculo, 2)]
                det_c = detalles_caja_map.get(act_c.id_activo)
                if det_c:
                    if transmision_final and (not det_c.transmision_tipo or det_c.transmision_tipo == "Mecánica") and transmision_final != "Mecánica":
                        det_c.transmision_tipo = transmision_final
                        detalles_actualizados += 1
                else:
                    nuevo_dc = Detalle_Caja_Cambio(
                        id_activo=act_c.id_activo,
                        transmision_tipo=transmision_final,
                    )
                    db.add(nuevo_dc)
                    detalles_caja_map[act_c.id_activo] = nuevo_dc
                    detalles_actualizados += 1

            # Commit parcial por lotes (solo si no es simulación)
            if (idx + 1) % BATCH_SIZE == 0:
                if not es_dry_run:
                    db.commit()
                print(f"    -> Progreso: {idx + 1} / {total_a_procesar} registros procesados...")

        # Commit final
        if not es_dry_run:
            db.commit()
            print(f"    -> Progreso: {total_a_procesar} / {total_a_procesar} registros completados.")
            print("\n✅ CAMBIOS PERSISTIDOS EXITOSAMENTE EN BASE DE DATOS.")
        else:
            db.rollback()
            print(f"    -> Progreso: {total_a_procesar} / {total_a_procesar} registros evaluados.")
            print("\n🔍 SIMULACIÓN COMPLETADA (--dry-run): Ningún dato fue alterado en la base de datos.")

        # ======================================================================
        # INFORME CONSOLIDADO DE INGESTA / ENRIQUECIMIENTO
        # ======================================================================
        print("\n" + "=" * 76)
        print(" RESUMEN FINAL DE LA OPERACIÓN")
        print("=" * 76)
        print(f"[*] Filas procesadas desde Excel        : {total_a_procesar}")
        print(f"[*] Filas descartadas / corruptas       : {reporte['descartados']} (ej: 'concon')")
        print("-" * 76)
        print(f"[*] Vehículos ACTUALIZADOS (Enriquecidos): {vehiculos_actualizados}")
        print(f"[*] Vehículos NUEVOS creados de cero    : {vehiculos_creados} (Activos: {vehiculos_creados - vehiculos_inactivos}, Inactivos: {vehiculos_inactivos})")
        print(f"[*] Vehículos sin modificaciones        : {vehiculos_sin_cambios}")
        print("-" * 76)
        print(f"[*] Repuestos MOTOR (MOT-X) creados     : {motores_creados}")
        print(f"[*] Repuestos CAJA (CAJ-X) creados      : {cajas_creadas}")
        print(f"[*] Detalles técnicos enriquecidos      : {detalles_actualizados}")
        print("-" * 76)
        print(f"[*] Cilindradas extraídas               : {conteo_cilindradas}")
        print(f"[*] N° Motores reales extraídos         : {conteo_motores_reales}")
        print(f"[*] Transmisiones: Mecánica: {conteo_mecanicas} | Automática: {conteo_automaticas}")
        print(f"[*] Combustibles: Gasolina: {conteo_gasolina} | Diésel: {conteo_diesel} | Híbrido: {conteo_hibrido}")
        print(f"[*] Tracción: 4x2 Delantera: {conteo_4x2_delantera} | 4x2 Trasera: {conteo_4x2_trasera} | 4x4 Conectable: {conteo_4x4_conectable} | 4x4 AWD: {conteo_4x4_permanente}")
        print("=" * 76 + "\n")

    except Exception as err:
        db.rollback()
        print(f"\n[!] Error crítico durante la operación: {err}")
        print("    Transacción revertida por seguridad para proteger integridad referencial.")
        raise err
    finally:
        db.close()


if __name__ == "__main__":
    ejecutar_migracion()