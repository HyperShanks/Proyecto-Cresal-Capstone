"""
Pruebas Unitarias de Políticas de Horario Comercial y Periodo de Gracia (backend/core/policies.py).
Valida:
1. Bypass para roles exentos (Gerente 4, Admin 5, Jefe 6, Online 7) en cualquier momento.
2. Roles regulados (Vendedor 2, Bodega 1, Caja 3) en horario regular.
3. Periodo de gracia de 30 minutos post-cierre.
4. Respeto a transacciones activas con reserva atómica viva.
5. Bloqueo 403 fuera de turno y domingos.
"""

from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
import uuid
import pytest
from fastapi import HTTPException

from core.policies import (
    TZ_CHILE,
    evaluar_horario_sucursal,
    validar_horario_operativo_ordenes,
    validar_horario_operativo_bodega,
    validar_horario_operativo_caja,
)
from models import Usuario, Activo_Inventariado


class MockUsuario:
    def __init__(self, id_rol: int, id_usuario: uuid.UUID = None):
        self.id_rol = id_rol
        self.id_usuario = id_usuario or uuid.uuid4()


class MockItem:
    def __init__(self, id_activo: int):
        self.id_activo = id_activo


def test_evaluar_horario_semana_abierto():
    # Miércoles a las 11:00 AM (Chile)
    dt = datetime(2026, 9, 16, 11, 0, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is True
    assert res["en_gracia"] is False


def test_evaluar_horario_semana_periodo_gracia():
    # Miércoles a las 18:45 PM (Chile) -> Gracia (18:30 a 19:00)
    dt = datetime(2026, 9, 16, 18, 45, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is False
    assert res["en_gracia"] is True


def test_evaluar_horario_semana_cerrado():
    # Miércoles a las 20:30 PM (Chile) -> Cerrado
    dt = datetime(2026, 9, 16, 20, 30, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is False
    assert res["en_gracia"] is False


def test_evaluar_horario_sabado_abierto():
    # Sábado a las 11:00 AM (Chile)
    dt = datetime(2026, 9, 19, 11, 0, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is True
    assert res["en_gracia"] is False


def test_evaluar_horario_sabado_gracia():
    # Sábado a las 14:15 PM (Chile) -> Gracia (14:00 a 14:30)
    dt = datetime(2026, 9, 19, 14, 15, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is False
    assert res["en_gracia"] is True


def test_evaluar_horario_sabado_cerrado():
    # Sábado a las 16:00 PM (Chile) -> Cerrado
    dt = datetime(2026, 9, 19, 16, 0, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is False
    assert res["en_gracia"] is False


def test_evaluar_horario_domingo():
    # Domingo cualquiera a las 12:00 PM (Chile)
    dt = datetime(2026, 9, 20, 12, 0, tzinfo=TZ_CHILE)
    res = evaluar_horario_sucursal(dt)
    assert res["abierto"] is False
    assert res["en_gracia"] is False
    assert "domingos" in res["motivo"].lower()


def test_roles_exentos_permitidos_siempre():
    # Domingo en la noche (23:00)
    dt_domingo_noche = datetime(2026, 9, 20, 23, 0, tzinfo=TZ_CHILE)

    # Rol 2 (Vendedor Mesón), 4 (Gerente), 5 (Admin), 6 (Jefe Ventas), 7 (Vendedor Online)
    for id_rol in [2, 4, 5, 6, 7]:
        user = MockUsuario(id_rol=id_rol)
        permitido = validar_horario_operativo_ordenes(user, ahora_local=dt_domingo_noche)
        assert permitido is True


def test_rol_regulado_horario_regular_permitido():
    # Miércoles a las 15:00
    dt_miercoles = datetime(2026, 9, 16, 15, 0, tzinfo=TZ_CHILE)
    for id_rol in [1, 3]:  # Bodega y Caja
        user = MockUsuario(id_rol=id_rol)
        assert validar_horario_operativo_ordenes(user, ahora_local=dt_miercoles) is True


def test_rol_regulado_periodo_gracia_permitido():
    # Miércoles a las 18:40 (Cierre 18:30 + Gracia hasta 19:00)
    dt_gracia = datetime(2026, 9, 16, 18, 40, tzinfo=TZ_CHILE)
    for id_rol in [1, 3]:
        user = MockUsuario(id_rol=id_rol)
        assert validar_horario_operativo_ordenes(user, ahora_local=dt_gracia) is True


def test_rol_regulado_fuera_horario_rechazado_403():
    # Miércoles a las 21:00 (Sin reserva activa)
    dt_noche = datetime(2026, 9, 16, 21, 0, tzinfo=TZ_CHILE)
    for id_rol in [1, 3]:
        user = MockUsuario(id_rol=id_rol)
        with pytest.raises(HTTPException) as exc_info:
            validar_horario_operativo_ordenes(user, items_orden=[], ahora_local=dt_noche)
        assert exc_info.value.status_code == 403
        assert "Operación rechazada" in exc_info.value.detail


from unittest.mock import MagicMock

def test_respeto_transaccion_activa_con_reserva_viva():
    """
    Si son las 19:15 (pasado incluso el periodo de gracia), pero un rol regulado
    posee una reserva atómica activa en BD (motor en el carrito), la orden procede.
    """
    user_id = uuid.uuid4()
    user = MockUsuario(id_rol=3, id_usuario=user_id)

    # Simular base de datos con reserva activa encontrada
    mock_db = MagicMock()
    mock_reserva = MagicMock()
    mock_db.query.return_value.filter.return_value.first.return_value = mock_reserva

    items = [MockItem(id_activo=999901)]
    dt_tarde = datetime(2026, 9, 16, 19, 15, tzinfo=TZ_CHILE)

    permitido = validar_horario_operativo_ordenes(
        usuario=user,
        items_orden=items,
        db=mock_db,
        ahora_local=dt_tarde,
    )
    assert permitido is True
    assert mock_db.query.called


def test_rechazo_si_reserva_expirada_fuera_de_horario():
    """
    Si son las 19:15 y la reserva del carrito ya expiró (reserva_activa es None),
    se debe rechazar con 403 Forbidden.
    """
    user_id = uuid.uuid4()
    user = MockUsuario(id_rol=3, id_usuario=user_id)

    mock_db = MagicMock()
    # first() retorna None (no hay reservas activas vigentes)
    mock_db.query.return_value.filter.return_value.first.return_value = None

    items = [MockItem(id_activo=999901)]
    dt_tarde = datetime(2026, 9, 16, 19, 15, tzinfo=TZ_CHILE)

    with pytest.raises(HTTPException) as exc_info:
        validar_horario_operativo_ordenes(
            usuario=user,
            items_orden=items,
            db=mock_db,
            ahora_local=dt_tarde,
        )
    assert exc_info.value.status_code == 403
    assert "Operación rechazada" in exc_info.value.detail


def test_validar_horario_operativo_bodega():
    # Bodeguero (id_rol 1) dentro de horario regular -> OK
    dt_abierto = datetime(2026, 9, 16, 11, 0, tzinfo=TZ_CHILE)
    bodeguero = MockUsuario(id_rol=1)
    assert validar_horario_operativo_bodega(bodeguero, ahora_local=dt_abierto) is True

    # Bodeguero en periodo de gracia (18:45) -> OK
    dt_gracia = datetime(2026, 9, 16, 18, 45, tzinfo=TZ_CHILE)
    assert validar_horario_operativo_bodega(bodeguero, ahora_local=dt_gracia) is True

    # Bodeguero de noche (22:00) -> 403
    dt_noche = datetime(2026, 9, 16, 22, 0, tzinfo=TZ_CHILE)
    with pytest.raises(HTTPException) as exc_info:
        validar_horario_operativo_bodega(bodeguero, ahora_local=dt_noche)
    assert exc_info.value.status_code == 403
    assert "Operación de bodega rechazada" in exc_info.value.detail

    # Gerente (id_rol 4) o Admin (id_rol 5) de noche -> Bypass 24/7 OK
    admin = MockUsuario(id_rol=5)
    assert validar_horario_operativo_bodega(admin, ahora_local=dt_noche) is True


def test_validar_horario_operativo_caja():
    # Caja (id_rol 3) dentro de horario regular -> OK
    dt_abierto = datetime(2026, 9, 16, 11, 0, tzinfo=TZ_CHILE)
    cajera = MockUsuario(id_rol=3)
    assert validar_horario_operativo_caja(cajera, ahora_local=dt_abierto) is True

    # Caja en periodo de gracia para cuadre (18:45) -> OK
    dt_gracia = datetime(2026, 9, 16, 18, 45, tzinfo=TZ_CHILE)
    assert validar_horario_operativo_caja(cajera, ahora_local=dt_gracia) is True

    # Caja de noche (22:00) o domingo -> 403
    dt_domingo = datetime(2026, 9, 20, 15, 0, tzinfo=TZ_CHILE)
    with pytest.raises(HTTPException) as exc_info:
        validar_horario_operativo_caja(cajera, ahora_local=dt_domingo)
    assert exc_info.value.status_code == 403
    assert "Operación de caja rechazada" in exc_info.value.detail


