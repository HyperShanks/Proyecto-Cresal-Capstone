# backend/tests/test_gerencia_dashboard.py
"""
Suite de Pruebas Unitarias y de Integración para el Dashboard Ejecutivo.
Valido aquí:
1. Seguridad Zero Trust y RBAC (Acceso permitido a roles 4 y 5, rechazo).
2. Aislamiento y consolidación de pagos eficaces ('Procesado' vs 'Anulado').
3. Filtro por sucursal y consolidado global.
4. Pulso operativo de bodega (etapas, courier, saldos y tasación).
"""

import uuid
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
import pytest
from models import (
    Region,
    Comuna,
    Sucursal,
    Rol,
    Usuario,
    Cliente,
    Categoria_Activo,
    Estado_Activo,
    Activo_Inventariado,
    Orden_Venta,
    Detalle_Orden,
    Transaccion_Pago,
    Despacho,
)
from core.security import create_access_token, hash_password
from routers.gerencia import calcular_limites_temporales_chile
from conftest import TestingSessionLocal

tz_chile = ZoneInfo("America/Santiago")


@pytest.fixture(scope="module")
def db_session_gerencia(setup_database):
    """
    Inicializo datos representativos de sucursales, usuarios con roles,
    órdenes con pagos y despachos para probar el dashboard gerencial.
    """
    db = TestingSessionLocal()
    try:
        # 1. Geografía y Sucursales
        r = Region(id_region=10, nombre_region="Valparaíso")
        db.add(r)
        c1 = Comuna(id_comuna=10, nombre_comuna="Viña del Mar", id_region=10)
        c2 = Comuna(id_comuna=20, nombre_comuna="Limache", id_region=10)
        db.add_all([c1, c2])

        suc1 = Sucursal(
            id_sucursal=101,
            nombre_sucursal="Casa Matriz - Viña",
            direccion="Av. Libertad 123",
            id_comuna=10,
        )
        suc2 = Sucursal(
            id_sucursal=102,
            nombre_sucursal="Patio Desarme - Limache",
            direccion="Calle Comercial 456",
            id_comuna=20,
        )
        db.add_all([suc1, suc2])

        # 2. Roles del sistema
        roles = [
            Rol(id_rol=1, nombre_rol="Bodeguero"),
            Rol(id_rol=2, nombre_rol="Vendedor"),
            Rol(id_rol=3, nombre_rol="Caja"),
            Rol(id_rol=4, nombre_rol="Gerente"),
            Rol(id_rol=5, nombre_rol="Administrador"),
            Rol(id_rol=8, nombre_rol="Auditor"),
        ]
        for rol in roles:
            if not db.query(Rol).filter_by(id_rol=rol.id_rol).first():
                db.add(rol)

        # 3. Categorías y Estados de activos
        if not db.query(Categoria_Activo).filter_by(id_categoria=1).first():
            db.add(Categoria_Activo(id_categoria=1, nombre_categoria="Motor"))
        if not db.query(Categoria_Activo).filter_by(id_categoria=2).first():
            db.add(Categoria_Activo(id_categoria=2, nombre_categoria="Caja"))

        est_disp = Estado_Activo(id_estado=1, nombre_estado="Disponible")
        est_pal = Estado_Activo(id_estado=7, nombre_estado="Paletizado")
        for est in [est_disp, est_pal]:
            if not db.query(Estado_Activo).filter_by(
                id_estado=est.id_estado
            ).first():
                db.add(est)

        # 4. Usuarios por Rol
        user_gerente = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=4,
            id_sucursal=101,
            rut_usuario="14.567.890-1",
            nombres="Roberto",
            apellidos="Gerente",
            email="gerente.test@cresal.cl",
            password_hash=hash_password("gerente123"),
            pin_acceso="4001",
            estado="Activo",
        )
        user_admin = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=5,
            id_sucursal=101,
            rut_usuario="11.111.111-1",
            nombres="Sistema",
            apellidos="Admin",
            email="admin.test@cresal.cl",
            password_hash=hash_password("admin123"),
            pin_acceso="5001",
            estado="Activo",
        )
        user_vendedor = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=101,
            rut_usuario="19.876.543-2",
            nombres="Carlos",
            apellidos="Vendedor",
            email="vendedor.test@cresal.cl",
            password_hash=hash_password("vendedor123"),
            pin_acceso="2001",
            estado="Activo",
        )
        user_bodeguero = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=101,
            rut_usuario="16.234.567-8",
            nombres="Juan",
            apellidos="Bodega",
            email="bodega.test@cresal.cl",
            password_hash=hash_password("bodega123"),
            pin_acceso="1001",
            estado="Activo",
        )
        user_auditor = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=8,
            id_sucursal=101,
            rut_usuario="13.456.789-0",
            nombres="Ricardo",
            apellidos="Crovetto",
            email="auditor.test@cresal.cl",
            password_hash=hash_password("auditor123"),
            pin_acceso="8001",
            estado="Activo",
        )
        user_auditor_limache = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=8,
            id_sucursal=102,
            rut_usuario="17.890.123-4",
            nombres="Auditor",
            apellidos="Limache",
            email="auditor.limache@cresal.cl",
            password_hash=hash_password("limache123"),
            pin_acceso="8002",
            estado="Activo",
        )
        db.add_all([user_gerente, user_admin, user_vendedor, user_bodeguero, user_auditor, user_auditor_limache])

        # 5. Clientes
        cli1 = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="76.452.119-K",
            nombres="Transportes Aconcagua",
            apellidos="Ltda.",
            correo="contacto@aconcagua.cl",
            id_comuna=10,
        )
        db.add(cli1)

        # 6. Activos inventariados
        act1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-TEST-001",
            id_categoria=1,
            id_estado=1,
            id_sucursal_actual=101,
            precio_referencia=1500000,
            estado="Activo",
        )
        act_sin_precio_1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="MOT-PAL-001",
            id_categoria=1,
            id_estado=7,
            id_sucursal_actual=101,
            precio_referencia=None,
            estado="Activo",
        )
        act_sin_precio_2 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="CAJ-PAL-002",
            id_categoria=2,
            id_estado=7,
            id_sucursal_actual=102,
            precio_referencia=0,
            estado="Activo",
        )
        db.add_all([act1, act_sin_precio_1, act_sin_precio_2])

        # 7. Órdenes y Pagos
        ahora_chile = datetime.now(tz_chile)
        hoy_utc = ahora_chile.astimezone(timezone.utc).replace(tzinfo=None)

        # Orden 1 en Sucursal 101: Pagada
        ord1 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=101,
            estado_orden="Pagada",
            total_venta=1000000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc,
        )
        db.add(ord1)

        pago1_efectivo = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord1.id_orden,
            monto=300000,
            metodo_pago="Efectivo",
            estado_pago="Procesado",
            fecha_pago=hoy_utc,
        )
        pago1_debito = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord1.id_orden,
            monto=700000,
            metodo_pago="Débito",
            estado_pago="Procesado",
            fecha_pago=hoy_utc,
        )
        det1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord1.id_orden,
            id_activo=act1.id_activo,
            cantidad=1,
            precio_final=1000000,
            estado_preparacion="Listo",
        )
        db.add_all([pago1_efectivo, pago1_debito, det1])

        # Orden 2 en Sucursal 101: Reservada con saldo pendiente
        ord2 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=101,
            estado_orden="Reservada",
            total_venta=500000,
            monto_pendiente=300000,
            fecha_creacion=hoy_utc,
        )
        db.add(ord2)

        pago2_transferencia = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord2.id_orden,
            monto=200000,
            metodo_pago="Transferencia",
            estado_pago="Procesado",
            fecha_pago=hoy_utc,
        )
        pago2_anulado = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord2.id_orden,
            monto=150000,
            metodo_pago="Efectivo",
            estado_pago="Anulado",
            fecha_pago=hoy_utc,
        )
        det2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=ord2.id_orden,
            cantidad=1,
            precio_final=500000,
            estado_preparacion="Pendiente",
        )
        db.add_all([pago2_transferencia, pago2_anulado, det2])

        # Orden 3 en Sucursal 102: Despachada
        ord3 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=102,
            estado_orden="Despachada",
            total_venta=500000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc,
        )
        db.add(ord3)

        pago3_credito = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord3.id_orden,
            monto=500000,
            metodo_pago="Crédito",
            estado_pago="Procesado",
            fecha_pago=hoy_utc,
        )
        desp3 = Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=ord3.id_orden,
            id_comuna_destino=10,
            direccion_envio="Calle Los Olivos 123",
            receptor_nombres="Manuel Courier",
            receptor_rut="15.123.456-7",
            receptor_telefono="+56911223344",
            empresa_transporte="Starken",
            estado_despacho="Enviado",
        )
        db.add_all([pago3_credito, desp3])

        # Orden 4: Anulada
        ord4_anulada = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=101,
            estado_orden="Anulada",
            total_venta=800000,
            monto_pendiente=0,
            fecha_creacion=hoy_utc - timedelta(hours=3),
        )
        db.add(ord4_anulada)
        pago4_anulado = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord4_anulada.id_orden,
            monto=800000,
            metodo_pago="Efectivo",
            estado_pago="Procesado",
            fecha_pago=hoy_utc - timedelta(hours=3),
        )
        db.add(pago4_anulado)

        # Pago MTD (debe caer dentro del mes pero antes de hoy para no duplicar ventas del día)
        inicio_hoy_test_utc, _, _ = calcular_limites_temporales_chile()
        if ahora_chile.day > 1:
            fecha_mtd = inicio_hoy_test_utc - timedelta(hours=2)
        else:
            fecha_mtd = inicio_hoy_test_utc + timedelta(hours=1)

        ord_mtd = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cli1.id_cliente,
            id_vendedor=user_vendedor.id_usuario,
            id_sucursal=101,
            estado_orden="Pagada",
            total_venta=400000,
            monto_pendiente=0,
            fecha_creacion=fecha_mtd,
        )
        db.add(ord_mtd)
        pago_mtd = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=ord_mtd.id_orden,
            monto=400000,
            metodo_pago="Transferencia",
            estado_pago="Procesado",
            fecha_pago=fecha_mtd,
        )
        db.add(pago_mtd)

        db.commit()

        yield {
            "user_gerente": user_gerente,
            "user_admin": user_admin,
            "user_vendedor": user_vendedor,
            "user_bodeguero": user_bodeguero,
            "user_auditor": user_auditor,
            "user_auditor_limache": user_auditor_limache,
            "sucursal_1": 101,
            "sucursal_2": 102,
        }
    finally:
        db.close()


def test_gerencia_kpis_acceso_denegado_para_roles_no_autorizados(
    client, db_session_gerencia
):
    """
    Verifico que operarios sin rol gerencial (Bodeguero o Vendedor)
    reciban un código HTTP 403 Forbidden al consultar los KPIs ejecutivos.
    """
    vendedor = db_session_gerencia["user_vendedor"]
    token_vendedor = create_access_token(
        data={"sub": str(vendedor.id_usuario), "rol": vendedor.id_rol}
    )
    headers = {"Authorization": f"Bearer {token_vendedor}"}

    response = client.get("/api/v1/gerencia/dashboard/kpis", headers=headers)
    assert response.status_code == 403
    assert "privilegios gerenciales" in response.json()["detail"]

    bodeguero = db_session_gerencia["user_bodeguero"]
    token_bodega = create_access_token(
        data={"sub": str(bodeguero.id_usuario), "rol": bodeguero.id_rol}
    )
    headers_bodega = {"Authorization": f"Bearer {token_bodega}"}

    response_bodega = client.get(
        "/api/v1/gerencia/dashboard/kpis", headers=headers_bodega
    )
    assert response_bodega.status_code == 403


def test_gerencia_kpis_acceso_permitido_para_gerente_y_admin(
    client, db_session_gerencia
):
    """
    Verifico que tanto el Gerente (id_rol=4) como el Administrador (id_rol=5)
    accedan con éxito (HTTP 200) a los reportes analíticos.
    """
    gerente = db_session_gerencia["user_gerente"]
    token_gerente = create_access_token(
        data={"sub": str(gerente.id_usuario), "rol": gerente.id_rol}
    )
    headers_gerente = {"Authorization": f"Bearer {token_gerente}"}

    resp_gerente = client.get(
        "/api/v1/gerencia/dashboard/kpis", headers=headers_gerente
    )
    assert resp_gerente.status_code == 200

    admin = db_session_gerencia["user_admin"]
    token_admin = create_access_token(
        data={"sub": str(admin.id_usuario), "rol": admin.id_rol}
    )
    headers_admin = {"Authorization": f"Bearer {token_admin}"}

    resp_admin = client.get(
        "/api/v1/gerencia/dashboard/kpis", headers=headers_admin
    )
    assert resp_admin.status_code == 200


def test_gerencia_kpis_aislamiento_por_sucursal_y_exclusion_pagos_anulados(
    client, db_session_gerencia
):
    """
    Valido que:
    1. Solo pagos 'Procesados' sumen en recaudación.
    2. Los pagos de órdenes 'Anuladas' queden excluidos.
    3. El filtro id_sucursal=101 reporte exactamente los montos de Casa Matriz.
    """
    gerente = db_session_gerencia["user_gerente"]
    token = create_access_token(
        data={"sub": str(gerente.id_usuario), "rol": gerente.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    # Sucursal 101: 1.000.000 + 200.000 = 1.200.000
    response = client.get(
        "/api/v1/gerencia/dashboard/kpis?id_sucursal=101", headers=headers
    )
    assert response.status_code == 200
    data = response.json()

    assert data["ventas_del_dia"] == 1200000
    assert data["transacciones_hoy"] == 2
    assert data["ticket_promedio"] == 600000.0
    assert data["acumulado_mensual_mtd"] >= 1200000
    assert data["margen_bruto"] == 64.8


def test_gerencia_kpis_consolidado_global_toda_la_cadena(
    client, db_session_gerencia
):
    """
    Compruebo que al omitir el parámetro id_sucursal, las métricas consolidan
    la totalidad de las sucursales de Cresal.
    """
    admin = db_session_gerencia["user_admin"]
    token = create_access_token(
        data={"sub": str(admin.id_usuario), "rol": admin.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/api/v1/gerencia/dashboard/kpis", headers=headers)
    assert response.status_code == 200
    data = response.json()

    assert data["ventas_del_dia"] == 1700000
    assert data["transacciones_hoy"] == 3
    assert data["ticket_promedio"] == round(1700000 / 3, 2)


def test_gerencia_pagos_desglose_efectivo_vs_canales_electronicos(
    client, db_session_gerencia
):
    """
    Compruebo que el endpoint /dashboard/pagos categorice correctamente
    el Efectivo físico frente a canales electrónicos y calcule porcentajes.
    """
    gerente = db_session_gerencia["user_gerente"]
    token = create_access_token(
        data={"sub": str(gerente.id_usuario), "rol": gerente.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get(
        "/api/v1/gerencia/dashboard/pagos?id_sucursal=101", headers=headers
    )
    assert response.status_code == 200
    data = response.json()

    assert data["efectivo_fisico"] == 300000
    assert data["canales_electronicos"] == 900000
    assert len(data["desglose"]) >= 3

    total_pct = sum(item["porcentaje"] for item in data["desglose"])
    assert 99.0 <= total_pct <= 101.0


def test_gerencia_operativa_alertas_y_flujo_bodega(
    client, db_session_gerencia
):
    """
    Valido el pulso operativo de bodega:
    - En preparación
    - Listos en mostrador
    - Despachos courier enviados
    - Saldos pendientes de cobro
    - Cuellos de botella paletizados sin precio
    """
    admin = db_session_gerencia["user_admin"]
    token = create_access_token(
        data={"sub": str(admin.id_usuario), "rol": admin.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get(
        "/api/v1/gerencia/dashboard/operativa", headers=headers
    )
    assert response.status_code == 200
    data = response.json()

    assert data["en_preparacion"] >= 1
    assert data["listos_mostrador"] >= 1
    assert data["enviados_courier"] >= 1
    assert data["alertas_saldo_pendiente"] >= 1
    assert data["cuellos_botella_paletizados"] >= 2

    resp_suc1 = client.get(
        "/api/v1/gerencia/dashboard/operativa?id_sucursal=101",
        headers=headers,
    )
    assert resp_suc1.status_code == 200
    data_suc1 = resp_suc1.json()

    assert data_suc1["cuellos_botella_paletizados"] == 1
    assert data_suc1["alertas_saldo_pendiente"] == 1


def test_auditor_zero_trust_read_only_and_mutation_blocked(
    client, db_session_gerencia
):
    """
    Verifica que el Auditor (id_rol=8):
    1. Puede consultar los endpoints GET de Gerencia (200 OK).
    2. Recibe 403 Forbidden estricto si intenta emitir órdenes (POST /api/v1/ordenes).
    3. Recibe 403 Forbidden estricto si intenta anular órdenes (POST /api/v1/ordenes/{id}/anular).
    """
    auditor = db_session_gerencia["user_auditor"]
    token = create_access_token(
        data={"sub": str(auditor.id_usuario), "rol": auditor.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Consulta lectura exitosa
    resp_kpis = client.get("/api/v1/gerencia/dashboard/kpis", headers=headers)
    assert resp_kpis.status_code == 200

    # 2. Bloqueo de emisión de orden
    payload_orden = {
        "id_sucursal": 101,
        "consentimiento_legal": True,
        "cliente": {
            "rut_cliente": "12.345.678-9",
            "nombres": "Cliente",
            "apellidos": "Prueba",
        },
        "items": [{"id_activo": str(uuid.uuid4()), "cantidad": 1, "precio_final": 50000}],
    }
    resp_crear = client.post("/api/v1/ordenes", json=payload_orden, headers=headers)
    assert resp_crear.status_code == 403
    assert "Auditoría no posee permisos" in resp_crear.json()["detail"]

    # 3. Bloqueo de anulación de orden
    fake_order_id = str(uuid.uuid4())
    resp_anular = client.post(f"/api/v1/ordenes/{fake_order_id}/anular", headers=headers)
    assert resp_anular.status_code == 403
    assert "Auditoría no posee permisos" in resp_anular.json()["detail"]


def test_auditor_satelite_limache_aislamiento_estricto(
    client, db_session_gerencia
):
    """
    Verifica el aislamiento estricto Zero-Trust del Auditor de Sucursal Satélite (Limache, id_rol=8, id_sucursal=102):
    1. Bloqueo 403 Forbidden a /dashboard/kpis.
    2. Bloqueo 403 Forbidden a /dashboard/pagos.
    3. Bloqueo 403 Forbidden a /dashboard/operativa.
    4. Bloqueo 403 Forbidden a /backorders.
    5. Bloqueo 403 Forbidden a /api/v1/ordenes (historial de clientes).
    6. Permiso 200 OK a /api/v1/gerencia/sucursales (para listado de sucursales en selector).
    7. Permiso 200 OK a /api/v1/inventario/maestro (para consulta de stock de Viña del Mar y Limache).
    """
    auditor_limache = db_session_gerencia["user_auditor_limache"]
    token = create_access_token(
        data={"sub": str(auditor_limache.id_usuario), "rol": auditor_limache.id_rol}
    )
    headers = {"Authorization": f"Bearer {token}"}

    # 1. KPIs ejecutivos bloqueados
    r_kpi = client.get("/api/v1/gerencia/dashboard/kpis", headers=headers)
    assert r_kpi.status_code == 403
    assert "sucursal satélite" in r_kpi.json()["detail"].lower()

    # 2. Resumen pagos bloqueado
    r_pagos = client.get("/api/v1/gerencia/dashboard/pagos", headers=headers)
    assert r_pagos.status_code == 403

    # 3. Pulso operativo bloqueado
    r_flujo = client.get("/api/v1/gerencia/dashboard/operativa", headers=headers)
    assert r_flujo.status_code == 403

    # 4. Backorders bloqueados
    r_backorders = client.get("/api/v1/gerencia/backorders", headers=headers)
    assert r_backorders.status_code == 403

    # 5. Historial de órdenes bloqueado
    r_ordenes = client.get("/api/v1/ordenes", headers=headers)
    assert r_ordenes.status_code == 403
    assert "sucursal satélite" in r_ordenes.json()["detail"].lower()

    # 6. Sucursales permitido para selector
    r_suc = client.get("/api/v1/gerencia/sucursales", headers=headers)
    assert r_suc.status_code == 200
    assert len(r_suc.json()) >= 2

    # 7. Maestro de inventario multi-sucursal permitido para chequear stock de Viña del Mar
    r_inv = client.get("/api/v1/inventario/maestro?id_sucursal=101", headers=headers)
    assert r_inv.status_code == 200
