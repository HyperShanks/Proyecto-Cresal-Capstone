"""
Módulo de validación y formateo de RUT chileno mediante algoritmo Módulo 11.
Provee funciones transversales para garantizar la integridad de identificadores
fiscales y legales en el backend.
"""

from typing import Tuple


def calcular_digito_verificador(cuerpo: str) -> str:
    """
    Calcula el dígito verificador para un cuerpo de RUT dado.

    Aplica la ponderación regresiva cíclica (2 a 7) de derecha a izquierda:
    - resto = sumatoria % 11
    - resultado = 11 - resto
    - 11 -> '0'
    - 10 -> 'K'
    - Otro -> str(resultado)
    """
    cuerpo_limpio = cuerpo.replace(".", "").replace("-", "").strip()
    if not cuerpo_limpio.isdigit():
        raise ValueError("El cuerpo del RUT debe contener únicamente dígitos.")

    multiplicadores = [2, 3, 4, 5, 6, 7]
    suma = 0
    idx_mult = 0

    for char in reversed(cuerpo_limpio):
        suma += int(char) * multiplicadores[idx_mult]
        idx_mult = (idx_mult + 1) % len(multiplicadores)

    resto = suma % 11
    resultado = 11 - resto

    if resultado == 11:
        return "0"
    elif resultado == 10:
        return "K"
    else:
        return str(resultado)


def formatear_rut(rut: str, con_puntos: bool = True) -> str:
    """
    Normaliza y formatea un RUT chileno.
    Ejemplo: '12345678k' -> '12.345.678-K' (o '12345678-K' sin puntos).
    """
    limpio = rut.replace(".", "").replace("-", "").strip().upper()
    if len(limpio) < 2:
        return rut

    cuerpo = limpio[:-1]
    dv = limpio[-1]

    if not cuerpo.isdigit():
        return rut

    if con_puntos:
        cuerpo_num = int(cuerpo)
        cuerpo_fmt = f"{cuerpo_num:,}".replace(",", ".")
        return f"{cuerpo_fmt}-{dv}"
    return f"{cuerpo}-{dv}"


def validar_rut_modulo11(
    rut: str, con_puntos: bool = True
) -> Tuple[bool, str]:
    """
    Valida un RUT chileno usando el algoritmo matemático Módulo 11.

    Retorna:
        Tuple[bool, str]:
            (True, rut_formateado) si es válido legalmente o consumidor final.
            (False, rut_original) si el dígito verificador no coincide.
    """
    if not rut or not isinstance(rut, str):
        return False, str(rut) if rut is not None else ""

    limpio = rut.replace(".", "").replace("-", "").strip().upper()
    if len(limpio) < 2 or len(limpio) > 10:
        return False, rut

    cuerpo = limpio[:-1]
    dv = limpio[-1]

    if not cuerpo.isdigit() or dv not in "0123456789K":
        return False, rut

    # Exención especial: Consumidor Final genérico para boleta rápida
    if cuerpo in ("6666666", "66666666") and dv == "6":
        rut_cf = "6.666.666-6" if con_puntos else f"{cuerpo}-6"
        return True, rut_cf

    try:
        dv_esperado = calcular_digito_verificador(cuerpo)
    except ValueError:
        return False, rut

    if dv == dv_esperado:
        return True, formatear_rut(limpio, con_puntos=con_puntos)

    return False, rut
