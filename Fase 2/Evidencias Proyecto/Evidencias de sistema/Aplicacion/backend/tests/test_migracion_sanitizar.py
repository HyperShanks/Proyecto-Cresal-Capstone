import pandas as pd
import pytest
from migracion_vehiculos import sanitizar_secuencia_ingresos

def test_sanitizar_concon_y_hueco_x():
    """Prueba el caso del usuario: con con eliminados y 1, 2, 3, x, 5 reparado a 4."""
    data = {
        "N_Ingreso": [1, 2, 3, "con con", "con con", 4, 5, "x", 7, 8],
        "Patente": ["A1", "A2", "A3", "C1", "C2", "A4", "A5", "A6", "A7", "A8"],
        "Marca": ["TOYOTA"] * 10,
        "Modelo": ["YARIS"] * 10,
    }
    df = pd.DataFrame(data)
    df_limpio, reporte = sanitizar_secuencia_ingresos(df, "N_Ingreso")

    # con con no tiene hueco correlativo (viene el 4 inmediatamente), por lo que se descartan
    # x entre 5 y 7 se repara a 6
    assert df_limpio["_numero_ingreso_limpio"].tolist() == ["1", "2", "3", "4", "5", "6", "7", "8"]
    assert reporte["reparados"] == 1
    assert reporte["descartados"] == 2

def test_sanitizar_duplicado_inmediato_834():
    """Prueba duplicado numérico inmediato sin espacio correlativo (834 repetido)."""
    data = {
        "N_Ingreso": [833, 834, 834, 835],
        "Patente": ["P1", "P2", "P3", "P4"],
        "Marca": ["HYUNDAI"] * 4,
        "Modelo": ["SANTA FE"] * 4,
    }
    df = pd.DataFrame(data)
    df_limpio, reporte = sanitizar_secuencia_ingresos(df, "N_Ingreso")

    assert df_limpio["_numero_ingreso_limpio"].tolist() == ["833", "834", "835"]
    assert reporte["descartados"] == 1

def test_sanitizar_duplicado_lejano_typo():
    """Prueba número 1085 repetido en fila lejana pero ubicado en un hueco secuencial."""
    data = {
        "N_Ingreso": [1084, 1085, 1086, 1809, 1085, 1811],
        "Patente": ["P1", "P2", "P3", "P4", "P5", "P6"],
        "Marca": ["CHEVROLET"] * 6,
        "Modelo": ["LUV"] * 6,
    }
    df = pd.DataFrame(data)
    df_limpio, reporte = sanitizar_secuencia_ingresos(df, "N_Ingreso")

    # La fila lejana 1810 con 1085 se repara al número correlativo 1810
    assert df_limpio["_numero_ingreso_limpio"].tolist() == ["1084", "1085", "1086", "1809", "1810", "1811"]
    assert reporte["reparados"] == 1
