import uuid
from sqlalchemy.orm import Session
from database import SessionLocal
from models import (Vehiculo_Origen, Activo_Inventariado, Orden_Venta, Detalle_Orden, 
                    Categoria_Activo, Estado_Activo, Sucursal, Usuario, Cliente, Rol, Region, Comuna)

def poblar_datos_prueba():
    db: Session = SessionLocal()
    
    try:
        print("Iniciando verificación e inyección de datos maestros...")

        # ==========================================
        # FASE 1: CREACIÓN DE DATOS MAESTROS (Dependencias)
        # ==========================================
        
        # 1. Región y Comuna
        region = db.query(Region).first()
        if not region:
            region = Region(nombre_region="Valparaíso")
            db.add(region)
            db.commit()

        comuna = db.query(Comuna).first()
        if not comuna:
            comuna = Comuna(nombre_comuna="Viña del Mar", id_region=region.id_region)
            db.add(comuna)
            db.commit()

        # 2. Sucursal
        sucursal = db.query(Sucursal).filter((Sucursal.id_sucursal == 1) | (Sucursal.nombre_sucursal.ilike("%Viña%"))).first()
        if not sucursal:
            sucursal = Sucursal(id_sucursal=1, nombre_sucursal="Viña del Mar", direccion="Camino Internacional 4105", id_comuna=comuna.id_comuna)
            db.add(sucursal)
            db.commit()

        # 3. Rol y Usuario (Vendedor)
        rol = db.query(Rol).first()
        if not rol:
            rol = Rol(nombre_rol="Vendedor")
            db.add(rol)
            db.commit()

        vendedor = db.query(Usuario).first()
        if not vendedor:
            vendedor = Usuario(
                id_rol=rol.id_rol,
                id_sucursal=sucursal.id_sucursal,
                rut_usuario="11111111-1",
                nombres="Juan",
                apellidos="Pérez",
                email="vendedor@cresal.cl",
                password_hash="hash_falso",
                pin_acceso="1234"
            )
            db.add(vendedor)
            db.commit()

        # 4. Cliente
        cliente = db.query(Cliente).first()
        if not cliente:
            cliente = Cliente(
                rut_cliente="22222222-2",
                nombres="Pedro",
                apellidos="Gómez",
                id_comuna=comuna.id_comuna
            )
            db.add(cliente)
            db.commit()

        # 5. Categoría y Estado de Activo
        categoria = db.query(Categoria_Activo).first()
        if not categoria:
            categoria = Categoria_Activo(nombre_categoria="Motor")
            db.add(categoria)
            db.commit()

        estado = db.query(Estado_Activo).first()
        if not estado:
            estado = Estado_Activo(nombre_estado="Disponible")
            db.add(estado)
            db.commit()

        # 6. Vehículo Origen
        vehiculo = db.query(Vehiculo_Origen).first()
        if not vehiculo:
            vehiculo = Vehiculo_Origen(
                numero_ingreso="ING-001",
                patente="AB1234",
                marca="Peugeot",
                modelo="206",
                anio=2008
            )
            db.add(vehiculo)
            db.commit()

        print("Datos maestros listos. Procediendo a inyectar Alertas (Activos y Órdenes)...")

        # ==========================================
        # FASE 2: INYECCIÓN DE ALERTAS 
        # ==========================================

        # CASO 1: ALERTA DE IMPRESIÓN PENDIENTE
        activo_impresion = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="QR-MOCK-001",
            id_categoria=categoria.id_categoria,
            id_estado=estado.id_estado,
            id_sucursal_actual=sucursal.id_sucursal,
            id_vehiculo=vehiculo.id_vehiculo,
            ubicacion_pasillo="PASILLO 5",
            ubicacion_pallet="PALLET 2",
            qr_impreso=False, # <-- ESTO GATILLA LA ALERTA 1
            estado="Activo"
        )
        db.add(activo_impresion)

        # CASO 2: ALERTA DE PREPARACIÓN (Falta Pago)
        activo_preparacion = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="QR-MOCK-002",
            id_categoria=categoria.id_categoria,
            id_estado=estado.id_estado,
            id_sucursal_actual=sucursal.id_sucursal,
            id_vehiculo=vehiculo.id_vehiculo,
            ubicacion_pasillo="PASILLO 4",
            ubicacion_pallet="PALLET 12",
            qr_impreso=True,
            estado="Activo"
        )
        db.add(activo_preparacion)
        db.commit() 

        orden_1 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente.id_cliente,
            id_vendedor=vendedor.id_usuario,
            id_sucursal=sucursal.id_sucursal,
            estado_orden="Reservada",
            total_venta=500000,
            monto_pendiente=500000 # <-- ESTO GATILLA LA ALERTA 2
        )
        db.add(orden_1)
        db.commit()

        detalle_1 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_1.id_orden,
            id_activo=activo_preparacion.id_activo,
            notas_preparacion="ENTREGAR MOTOR PELADO (SIN ACCESORIOS)",
            precio_final=500000
        )
        db.add(detalle_1)

        # CASO 3: ALERTA DE LIBERACIÓN (Pagado)
        activo_liberado = Activo_Inventariado(
            id_activo=uuid.uuid4(),
            sku_qr_fisico="QR-MOCK-003",
            id_categoria=categoria.id_categoria,
            id_estado=estado.id_estado,
            id_sucursal_actual=sucursal.id_sucursal,
            id_vehiculo=vehiculo.id_vehiculo,
            ubicacion_pasillo="PASILLO 1",
            ubicacion_pallet="PALLET 3",
            qr_impreso=True,
            estado="Activo"
        )
        db.add(activo_liberado)
        db.commit()

        orden_2 = Orden_Venta(
            id_orden=uuid.uuid4(),
            id_cliente=cliente.id_cliente,
            id_vendedor=vendedor.id_usuario,
            id_sucursal=sucursal.id_sucursal,
            estado_orden="Pagada",
            total_venta=250000,
            monto_pendiente=0 # <-- ESTO GATILLA LA ALERTA 3
        )
        db.add(orden_2)
        db.commit()

        detalle_2 = Detalle_Orden(
            id_detalle=uuid.uuid4(),
            id_orden=orden_2.id_orden,
            id_activo=activo_liberado.id_activo,
            precio_final=250000
        )
        db.add(detalle_2)

        db.commit()
        print("¡Datos mock insertados con éxito! Ahora puedes abrir tu app en Flutter.")

    except Exception as e:
        db.rollback()
        print(f"Error al poblar base de datos: {str(e)}")
    finally:
        db.close()

if __name__ == "__main__":
    poblar_datos_prueba()