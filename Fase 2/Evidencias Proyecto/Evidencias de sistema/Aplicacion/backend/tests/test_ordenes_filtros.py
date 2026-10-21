# backend/tests/test_ordenes_filtros.py
"""
Suite de Pruebas Automatizadas para el Visor y Auditoría de Órdenes (HU-5.2).
Valido: RBAC (Roles 3, 4, 5 ok; 1, 2 denegado).
2. Filtros multidimensionales (sucursal, estado, método de pago, rango fechas).
3. Búsqueda predictiva y tolerante a formatos de RUT, Folio y Nombres.
4. Árbol de detalle jerárquico completo para auditoría 360°.
"""

import uuid
from datetime import datetime, timezone
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
from conftest import TestingSessionLocal

tz_chile = ZoneInfo("America/Santiago")


@pytest.fixture(scope="module")
def db_session_auditoria(setup_database):
    """
    Inicializo datos representativos de prueba: sucursales, clientes, usuarios
    con diferentes roles y órdenes con pagos en múltiples métodos y estados.
    """
    db = TestingSessionLocal()
    try:
        # 1. Geografía y Sucursales
        if not db.query(Region).filter_by(id_region=30).first():
            r = Region(id_region=30, nombre_region="Valparaíso Auditoría")
            db.add(r)
            db.commit()

        if not db.query(Comuna).filter_by(id_comuna=301).first():
            c1 = Comuna(
                id_comuna=301,
                nombre_comuna="Viña del Mar Aud",
                id_region=30
            )
            c2 = Comuna(
                id_comuna=302,
                nombre_comuna="Limache Aud",
                id_region=30
            )
            db.add_all([c1, c2])
            db.commit()

        suc1 = db.query(Sucursal).filter_by(id_sucursal=201).first()
        if not suc1:
            suc1 = Sucursal(
                id_sucursal=201,
                nombre_sucursal="Casa Matriz (Viña)",
                direccion="Calle Valparaíso 100",
                id_comuna=301,
            )
            db.add(suc1)

        suc2 = db.query(Sucursal).filter_by(id_sucursal=202).first()
        if not suc2:
            suc2 = Sucursal(
                id_sucursal=202,
                nombre_sucursal="Patio Desarme (Limache)",
                direccion="Av. Palmira 200",
                id_comuna=302,
            )
            db.add(suc2)
        db.commit()

        # 2. Roles
        for r_id, r_nom in [
            (1, "Bodeguero"),
            (2, "Vendedor"),
            (3, "Caja"),
            (4, "Gerente"),
            (5, "Administrador"),
        ]:
            if not db.query(Rol).filter_by(id_rol=r_id).first():
                db.add(Rol(id_rol=r_id, nombre_rol=r_nom))
        db.commit()

        # 3. Categorías y Estados
        if not db.query(Categoria_Activo).filter_by(id_categoria=20).first():
            db.add(
                Categoria_Activo(
                    id_categoria=20,
                    nombre_categoria="Suspensión"
                )
            )
        if not db.query(Estado_Activo).filter_by(id_estado=1).first():
            db.add(Estado_Activo(id_estado=1, nombre_estado="Disponible"))
        db.commit()

        # 4. Usuarios para pruebas RBAC
        u_gerente = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=4,
            id_sucursal=201,
            rut_usuario="14.111.222-3",
            nombres="Roberto",
            apellidos="GerenteAud",
            email="gerente.aud@cresal.cl",
            password_hash=hash_password("aud123"),
            pin_acceso="4444",
            estado="Activo",
        )
        u_admin = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=5,
            id_sucursal=201,
            rut_usuario="15.222.333-4",
            nombres="Elena",
            apellidos="AdminAud",
            email="admin.aud@cresal.cl",
            password_hash=hash_password("aud123"),
            pin_acceso="5555",
            estado="Activo",
        )
        u_caja = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=3,
            id_sucursal=201,
            rut_usuario="16.333.444-5",
            nombres="Lorena",
            apellidos="CajaAud",
            email="caja.aud@cresal.cl",
            password_hash=hash_password("aud123"),
            pin_acceso="3333",
            estado="Activo",
        )
        u_vendedor = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=2,
            id_sucursal=201,
            rut_usuario="17.444.555-6",
            nombres="Pedro",
            apellidos="VendedorAud",
            email="vendedor.aud@cresal.cl",
            password_hash=hash_password("aud123"),
            pin_acceso="2222",
            estado="Activo",
        )
        u_bodega = Usuario(
            id_usuario=uuid.uuid4(),
            id_rol=1,
            id_sucursal=201,
            rut_usuario="18.555.666-7",
            nombres="Mario",
            apellidos="BodegaAud",
            email="bodega.aud@cresal.cl",
            password_hash=hash_password("aud123"),
            pin_acceso="1111",
            estado="Activo",
        )
        db.add_all([u_gerente, u_admin, u_caja, u_vendedor, u_bodega])
        db.commit()

        # 5. Clientes
        c_perez = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="12.345.678-9",
            nombres="Juan Carlos",
            apellidos="Pérez Cotapos",
            correo="juan.perez@test.cl",
            telefono="+56911223344",
        )
        c_gonzalez = Cliente(
            id_cliente=uuid.uuid4(),
            rut_cliente="19.876.543-2",
            nombres="María Ignacia",
            apellidos="González Silva",
            correo="maria.gonzalez@test.cl",
            telefono="+56922334455",
        )
        db.add_all([c_perez, c_gonzalez])
        db.commit()

        # 6. Activo físico inventariado con SKU
        activo1 = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            id_sucursal_actual=201,
            id_categoria=20,
            sku_qr_fisico="AMORT-FRON-001",
            precio_referencia=85000,
            id_estado=1,
        )
        db.add(activo1)
        db.commit()

        # 7. Órdenes representativas
        ahora_utc = datetime.now(timezone.utc).replace(tzinfo=None)

        # Orden 1: Sucursal 201, Pagada en Efectivo, Cliente Juan Pérez
        o1 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=c_perez.id_cliente,
            id_vendedor=u_vendedor.id_usuario,
            id_cajera=u_caja.id_usuario,
            estado_orden="Pagada",
            total_venta=85000,
            monto_pendiente=0,
            fecha_creacion=ahora_utc,
            qr_transaccional_salida="ORD-AUD-001",
        )
        db.add(o1)
        db.commit()

        d1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o1.id_orden,
            id_activo=activo1.id_activo,
            descripcion_manual="Amortiguador Delantero Original",
            cantidad=1,
            precio_unitario=85000,
            precio_final=85000,
            estado_preparacion="Listo Retiro",
        )
        p1 = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=o1.id_orden,
            monto=85000,
            metodo_pago="Efectivo",
            estado_pago="Procesado",
            fecha_pago=ahora_utc,
        )
        desp1 = Despacho(
            id_despacho=uuid.uuid4(),
            id_orden=o1.id_orden,
            id_comuna_destino=301,
            direccion_envio="Av. Libertad 450",
            receptor_nombres="Juan Carlos Pérez",
            receptor_rut="12.345.678-9",
            receptor_telefono="+56911223344",
            estado_despacho="Enviado",
            costo_envio=0,
        )
        db.add_all([d1, p1, desp1])

        # Orden 2: Sucursal 202, Reservada (Transferencia), Cliente María G.
        o2 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=202,
            id_cliente=c_gonzalez.id_cliente,
            id_vendedor=u_vendedor.id_usuario,
            id_cajera=u_caja.id_usuario,
            estado_orden="Reservada",
            total_venta=150000,
            monto_pendiente=50000,
            fecha_creacion=ahora_utc,
            qr_transaccional_salida="ORD-AUD-002",
        )
        db.add(o2)
        db.commit()

        d2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o2.id_orden,
            descripcion_manual="Bandeja de Suspensión Derecha",
            cantidad=1,
            precio_unitario=150000,
            precio_final=150000,
            estado_preparacion="En Preparacion",
        )
        p2 = Transaccion_Pago(
            id_pago=uuid.uuid4(),
            id_orden=o2.id_orden,
            monto=100000,
            metodo_pago="Transferencia",
            estado_pago="Procesado",
            fecha_pago=ahora_utc,
        )
        db.add_all([d2, p2])
        db.commit()

        yield {
            "gerente": u_gerente,
            "admin": u_admin,
            "caja": u_caja,
            "vendedor": u_vendedor,
            "bodega": u_bodega,
            "orden_1": o1,
            "orden_2": o2,
            "cliente_perez": c_perez,
            "cliente_gonzalez": c_gonzalez,
        }
    finally:
        db.close()


def test_ordenes_acceso_denegado_para_bodeguero_y_vendedor(
    client, db_session_auditoria
):
    """
    Verifico que roles operativos (Bodeguero 1, Vendedor 2) sean rechazados
    con código 403 Forbidden al intentar consultar el visor de auditoría.
    """
    token_bodega = create_access_token(
        {"sub": str(db_session_auditoria["bodega"].id_usuario)}
    )
    res_b = client.get(
        "/api/v1/ordenes",
        headers={"Authorization": f"Bearer {token_bodega}"},
    )
    assert res_b.status_code == 403
    assert "Acceso restringido" in res_b.json()["detail"]

    token_vendedor = create_access_token(
        {"sub": str(db_session_auditoria["vendedor"].id_usuario)}
    )
    res_v = client.get(
        "/api/v1/ordenes",
        headers={"Authorization": f"Bearer {token_vendedor}"},
    )
    assert res_v.status_code == 403


def test_ordenes_acceso_permitido_para_gerente_admin_y_caja(
    client, db_session_auditoria
):
    """
    Verifico que Gerente (4), Administrador (5) y Caja (3) puedan acceder
    satisfactoriamente al visor de órdenes con código 200 OK.
    """
    for rol_key in ["gerente", "admin", "caja"]:
        token = create_access_token(
            {"sub": str(db_session_auditoria[rol_key].id_usuario)}
        )
        res = client.get(
            "/api/v1/ordenes",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res.status_code == 200
        data = res.json()
        assert "items" in data
        assert "total_registros" in data
        assert "total_monto_consolidado" in data


def test_ordenes_filtro_por_sucursal_y_consolidado_global(
    client, db_session_auditoria
):
    """
    Verifico que el parámetro `id_sucursal` segmente las órdenes correctamente,
    y que al omitirlo se retornen de forma consolidada todas las sucursales.
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )

    # 1. Filtro Sucursal 201 (Casa Matriz)
    res_201 = client.get(
        "/api/v1/ordenes?id_sucursal=201",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_201.status_code == 200
    folios_201 = [it["folio"] for it in res_201.json()["items"]]
    assert "ORD-AUD-001" in folios_201
    assert "ORD-AUD-002" not in folios_201
    assert res_201.json()["total_monto_consolidado"] == 85000

    # 2. Filtro Sucursal 202 (Patio Desarme) - Orden con abono de 100.000 (total 150.000 - 50.000 pendiente)
    res_202 = client.get(
        "/api/v1/ordenes?id_sucursal=202",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_202.status_code == 200
    folios_202 = [it["folio"] for it in res_202.json()["items"]]
    assert "ORD-AUD-002" in folios_202
    assert "ORD-AUD-001" not in folios_202
    assert res_202.json()["total_monto_consolidado"] == 100000

    # 3. Consolidado Global (sin sucursal) - Suma 85.000 (pagada) + 100.000 (abono) = 185.000
    res_global = client.get(
        "/api/v1/ordenes",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_global.status_code == 200
    folios_global = [it["folio"] for it in res_global.json()["items"]]
    assert "ORD-AUD-001" in folios_global
    assert "ORD-AUD-002" in folios_global
    assert res_global.json()["total_monto_consolidado"] == 185000


def test_ordenes_filtro_multidimensional_estado_y_metodo_pago(
    client, db_session_auditoria
):
    """
    Verifico filtros combinados de estado ('Pagada', 'Reservada') y
    método de pago ('Efectivo', 'Transferencia').
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )

    # Filtro solo estado Pagada
    res_pagada = client.get(
        "/api/v1/ordenes?estado=Pagada",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_pagada.status_code == 200
    for it in res_pagada.json()["items"]:
        assert it["estado_orden"] == "Pagada"

    # Filtro método de pago Transferencia
    res_transf = client.get(
        "/api/v1/ordenes?metodo_pago=Transferencia",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_transf.status_code == 200
    folios_transf = [it["folio"] for it in res_transf.json()["items"]]
    assert "ORD-AUD-002" in folios_transf
    assert "ORD-AUD-001" not in folios_transf


def test_ordenes_busqueda_predictiva_por_rut_y_folio(
    client, db_session_auditoria
):
    """
    Verifico búsqueda tolerante por folio, nombre de cliente y RUT
    (tanto con puntos y guión como solo dígitos numéricos).
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )

    # 1. Búsqueda por Folio
    res_fol = client.get(
        "/api/v1/ordenes?search=AUD-001",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_fol.status_code == 200
    assert any(it["folio"] == "ORD-AUD-001" for it in res_fol.json()["items"])

    # 2. Búsqueda por Nombre Parcial de Cliente
    res_nom = client.get(
        "/api/v1/ordenes?search=Cotapos",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_nom.status_code == 200
    assert any(it["folio"] == "ORD-AUD-001" for it in res_nom.json()["items"])

    # 3. Búsqueda por RUT sin puntos (123456789)
    res_rut = client.get(
        "/api/v1/ordenes?search=123456789",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res_rut.status_code == 200
    assert any(it["folio"] == "ORD-AUD-001" for it in res_rut.json()["items"])


def test_orden_detalle_arbol_completo_auditoria(client, db_session_auditoria):
    """
    Verifico que GET /api/v1/ordenes/{id_orden} retorne el árbol jerárquico
    completo: folio, cliente, despacho, detalles con SKU y lista de pagos.
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )
    o1_id = str(db_session_auditoria["orden_1"].id_orden)

    res = client.get(
        f"/api/v1/ordenes/{o1_id}",
        headers={"Authorization": f"Bearer {token_gerente}"},
    )
    assert res.status_code == 200
    detalle = res.json()

    assert detalle["folio"] == "ORD-AUD-001"
    assert detalle["estado_orden"] == "Pagada"
    assert detalle["total_venta"] == 85000
    assert detalle["cliente"]["rut"] == "12.345.678-9"
    assert "Pérez" in detalle["cliente"]["apellidos"]

    # Detalle de ítems
    assert len(detalle["detalles"]) == 1
    item = detalle["detalles"][0]
    assert item["sku"] == "AMORT-FRON-001"
    assert item["estado_preparacion"] == "Listo Retiro"

    # Pagos aplicados
    assert len(detalle["pagos"]) == 1
    pago = detalle["pagos"][0]
    assert pago["metodo_pago"] == "Efectivo"
    assert pago["monto"] == 85000
    assert pago["estado_pago"] == "Procesado"


def test_ordenes_filtro_por_tipo_activo(client, db_session_auditoria):
    """
    Verifico filtrado por motores y cajas (únicos activos inventariados de Cresal):
    - MOTORES_CAJAS: sólo órdenes que incluyan motores o cajas de cambio
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )

    db = TestingSessionLocal()
    o_motor = None
    activo_motor = None
    try:
        cat_motor = db.query(Categoria_Activo).filter_by(id_categoria=1).first()
        if not cat_motor:
            cat_motor = Categoria_Activo(id_categoria=1, nombre_categoria="Motores")
            db.add(cat_motor)
            db.commit()

        activo_motor = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            id_sucursal_actual=201,
            id_categoria=1,
            sku_qr_fisico="MOT-TEST-001",
            precio_referencia=500000,
            id_estado=1,
        )
        db.add(activo_motor)
        db.commit()

        o_motor = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=500000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-AUD-MOTOR",
        )
        db.add(o_motor)
        db.commit()

        d_motor = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_motor.id_orden,
            id_activo=activo_motor.id_activo,
            descripcion_manual="Motor 2.0 HDI Completo",
            cantidad=1,
            precio_unitario=500000,
            precio_final=500000,
            estado_preparacion="Listo Retiro",
        )
        db.add(d_motor)
        db.commit()

        # Filtro MOTORES_CAJAS (ORD-AUD-MOTOR debe aparecer; 001 y 002 no)
        res_motores = client.get(
            "/api/v1/ordenes?tipo_activo=MOTORES_CAJAS",
            headers={"Authorization": f"Bearer {token_gerente}"},
        )
        assert res_motores.status_code == 200
        folios_motores = [it["folio"] for it in res_motores.json()["items"]]
        assert "ORD-AUD-MOTOR" in folios_motores
        assert "ORD-AUD-001" not in folios_motores
        assert "ORD-AUD-002" not in folios_motores
    finally:
        if o_motor:
            db.query(Detalle_Orden).filter_by(id_orden=o_motor.id_orden).delete()
            db.query(Orden_Venta).filter_by(id_orden=o_motor.id_orden).delete()
        if activo_motor:
            db.query(Activo_Inventariado).filter_by(id_activo=activo_motor.id_activo).delete()
        db.commit()
        db.close()


def test_ordenes_filtro_motores_cajas_exclusion_falsos_positivos(client, db_session_auditoria):
    """
    SPEC CRES-240 / Definition of Done:
    Valida que los filtros de Gerencia excluyan estrictamente falsos positivos:
    - «Motor de cremallera», «Motor de partida», «Caja de fusibles» NO se computan como motores/cajas.
    - Misceláneos genuinos como «Motor Toyota 1.5» o «Caja de cambios 5ta» SÍ se computan.
    """
    token_gerente = create_access_token(
        {"sub": str(db_session_auditoria["gerente"].id_usuario)}
    )

    db = TestingSessionLocal()
    ordenes_creadas = []
    try:
        # 1. Orden Falsa: Motor de partida
        o_partida = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=45000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-FP-PARTIDA",
        )
        db.add(o_partida)
        ordenes_creadas.append(o_partida.id_orden)
        d_partida = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_partida.id_orden,
            descripcion_manual="Motor de partida Bosch 12V",
            cantidad=1,
            precio_unitario=45000,
            precio_final=45000,
        )
        db.add(d_partida)

        # 2. Orden Falsa: Caja de fusibles
        o_fusibles = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=35000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-FP-FUSIBLES",
        )
        db.add(o_fusibles)
        ordenes_creadas.append(o_fusibles.id_orden)
        d_fusibles = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_fusibles.id_orden,
            descripcion_manual="Caja de fusibles de cabina",
            cantidad=1,
            precio_unitario=35000,
            precio_final=35000,
        )
        db.add(d_fusibles)

        # 3. Orden Falsa: Motor de cremallera
        o_cremallera = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=60000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-FP-CREMALLERA",
        )
        db.add(o_cremallera)
        ordenes_creadas.append(o_cremallera.id_orden)
        d_cremallera = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_cremallera.id_orden,
            descripcion_manual="Motor de cremallera hidráulica",
            cantidad=1,
            precio_unitario=60000,
            precio_final=60000,
        )
        db.add(d_cremallera)

        # 4. Orden Verdadera Miscelánea: Motor principal
        o_motor_real = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=850000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-OK-MOTOR-MISC",
        )
        db.add(o_motor_real)
        ordenes_creadas.append(o_motor_real.id_orden)
        d_motor_real = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_motor_real.id_orden,
            descripcion_manual="Motor Toyota Yaris 1NZ 1.5 Bencinero Completo",
            cantidad=1,
            precio_unitario=850000,
            precio_final=850000,
        )
        db.add(d_motor_real)

        # 5. Orden Verdadera Miscelánea: Caja de cambios
        o_caja_real = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_sucursal=201,
            id_cliente=db_session_auditoria["cliente_perez"].id_cliente,
            id_vendedor=db_session_auditoria["vendedor"].id_usuario,
            id_cajera=db_session_auditoria["caja"].id_usuario,
            estado_orden="Pagada",
            total_venta=420000,
            monto_pendiente=0,
            fecha_creacion=datetime.now(timezone.utc).replace(tzinfo=None),
            qr_transaccional_salida="ORD-OK-CAJA-MISC",
        )
        db.add(o_caja_real)
        ordenes_creadas.append(o_caja_real.id_orden)
        d_caja_real = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=o_caja_real.id_orden,
            descripcion_manual="Caja de cambios mecánica 5 velocidades Hyundai Accent",
            cantidad=1,
            precio_unitario=420000,
            precio_final=420000,
        )
        db.add(d_caja_real)

        db.commit()

        # Consultar filtro MOTORES_CAJAS
        res = client.get(
            "/api/v1/ordenes?tipo_activo=MOTORES_CAJAS",
            headers={"Authorization": f"Bearer {token_gerente}"},
        )
        assert res.status_code == 200
        data = res.json()
        folios = [it["folio"] for it in data["items"]]

        # Validaciones de aceptación:
        # A. Falsos positivos NO deben estar en folios
        assert "ORD-FP-PARTIDA" not in folios
        assert "ORD-FP-FUSIBLES" not in folios
        assert "ORD-FP-CREMALLERA" not in folios

        # B. Misceláneos legítimos de motor y caja SÍ deben estar
        assert "ORD-OK-MOTOR-MISC" in folios
        assert "ORD-OK-CAJA-MISC" in folios
    finally:
        for ord_id in ordenes_creadas:
            db.query(Detalle_Orden).filter_by(id_orden=ord_id).delete()
            db.query(Orden_Venta).filter_by(id_orden=ord_id).delete()
        db.commit()
        db.close()


