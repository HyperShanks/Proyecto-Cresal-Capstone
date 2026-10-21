# backend/schemas/__init__.py
from pathlib import Path
import importlib.machinery
import importlib.util

# Cargar dinámicamente el archivo legacy schemas.py del backend si existe
_schemas_file = Path(__file__).resolve().parent.parent / "schemas.py"
if _schemas_file.exists():
    _loader = importlib.machinery.SourceFileLoader("_legacy_schemas", str(_schemas_file))
    _spec = importlib.util.spec_from_loader("_legacy_schemas", _loader)
    if _spec and _spec.loader:
        _mod = importlib.util.module_from_spec(_spec)
        _loader.exec_module(_mod)
        for _k, _v in _mod.__dict__.items():
            if not _k.startswith("__"):
                globals()[_k] = _v

from .gerencia_schemas import (
    KpiFinancieroDTO,
    DesglosePagoDTO,
    ResumenPagosDTO,
    FlujoOperativoDTO,
    BackorderGerenciaItemDTO,
    BackorderGerenciaListResponse,
    BackorderGerenciaKpisDTO,
    SucursalGerenciaDTO,
)
