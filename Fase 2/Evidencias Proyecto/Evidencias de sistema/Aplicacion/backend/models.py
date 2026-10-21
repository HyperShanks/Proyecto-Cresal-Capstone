# El archivo models.py utiliza un ORM (Object-Relational Mapping).
# En lugar de escribir comandos SQL crudos como SELECT * FROM Vehiculo_Origen WHERE patente = 'XX', escribes código Python orientado a objetos.
# ¿Por qué? Porque previene inyecciones SQL (ataques de seguridad), hace que el código sea infinitamente más fácil de mantener y permite que FastAPI 
# autogenere la documentación Swagger.

import uuid
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Date, Text, ForeignKey, text, CheckConstraint, Sequence
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from database import Base

# ==========================================
# CONFIGURACIÓN, SUCURSALES, ROLES Y USUARIOS
# ==========================================

class Region(Base):
    __tablename__ = "Region"

    id_region = Column(Integer, primary_key=True, autoincrement=True)
    nombre_region = Column(String(100), nullable=False)

    # Relaciones
    comunas = relationship("Comuna", back_populates="region")

class Comuna(Base):
    __tablename__ = "Comuna"

    id_comuna = Column(Integer, primary_key=True, autoincrement=True)
    nombre_comuna = Column(String(100), nullable=False)
    id_region = Column(Integer, ForeignKey("Region.id_region"), nullable=False)

    # Relaciones
    region = relationship("Region", back_populates="comunas")
    sucursales = relationship("Sucursal", back_populates="comuna")

class Sucursal(Base):
    __tablename__ = "Sucursal"

    id_sucursal = Column(Integer, primary_key=True, autoincrement=True)
    nombre_sucursal = Column(String(100), nullable=False)
    direccion = Column(String(255), nullable=False)
    sector = Column(String(100), nullable=True)
    id_comuna = Column(Integer, ForeignKey("Comuna.id_comuna"), nullable=False)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

    # Relaciones
    comuna = relationship("Comuna", back_populates="sucursales")
    usuarios = relationship("Usuario", back_populates="sucursal")

class Rol(Base):
    __tablename__ = "Rol"

    id_rol = Column(Integer, primary_key=True, autoincrement=True)
    nombre_rol = Column(String(50), nullable=False, unique=True)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

    # Relaciones
    usuarios = relationship("Usuario", back_populates="rol")

class Usuario(Base):
    __tablename__ = "Usuario"

    id_usuario = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_rol = Column(Integer, ForeignKey("Rol.id_rol"), nullable=False)
    id_sucursal = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    rut_usuario = Column(String(12), nullable=False, unique=True)
    nombres = Column(String(100), nullable=False)
    apellidos = Column(String(100), nullable=False)
    email = Column(String(150), nullable=False, unique=True)
    password_hash = Column(String(255), nullable=False)
    pin_acceso = Column(String(4), nullable=False, unique=True)
    telegram_chat_id = Column(String(100), nullable=True)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

    # Relaciones
    rol = relationship("Rol", back_populates="usuarios")
    sucursal = relationship("Sucursal", back_populates="usuarios")

    @property
    def nombre_rol(self) -> str | None:
        return self.rol.nombre_rol if self.rol else None

    @property
    def nombre_sucursal(self) -> str | None:
        return self.sucursal.nombre_sucursal if self.sucursal else None

# ==========================================
# SOPORTE TÉCNICO Y MESA DE AYUDA INTERNA
# ==========================================

class Ticket_Soporte(Base):
    __tablename__ = "Ticket_Soporte"

    id_ticket = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tipo_ticket = Column(String(50), nullable=False)
    prioridad = Column(String(20), nullable=False, server_default="Media")
    asunto = Column(String(150), nullable=False)
    descripcion = Column(String(1000), nullable=False)
    id_usuario_creador = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    id_usuario_resolutor = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=True)
    tabla_referencia = Column(String(50), nullable=True)
    id_referencia = Column(UUID(as_uuid=True), nullable=True)
    estado_ticket = Column(String(30), nullable=False, server_default="Abierto")
    observacion_cierre = Column(String(1000), nullable=True)
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_cierre = Column(DateTime, nullable=True)

# ==========================================
# INVENTARIO Y EXTRACCIÓN (WEB SCRAPING)
# ==========================================

class Vehiculo_Origen(Base):
    __tablename__ = "Vehiculo_Origen"
    
    id_vehiculo = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    numero_ingreso = Column(String(10), nullable=False, unique=True)
    patente = Column(String(20), nullable=False, unique=True, default=lambda: f"SPPU-{uuid.uuid4().hex[:6].upper()}")
    vin = Column(String(17), nullable=True, unique=True)
    factura = Column(String(50), nullable=True)
    fecha_ingreso = Column(Date, nullable=True, server_default=text("CURRENT_DATE"))
    origen = Column(String(100), nullable=True)
    marca = Column(String(100), nullable=False)
    modelo = Column(String(100), nullable=False)
    anio = Column(Integer, nullable=True)
    color = Column(String(50), nullable=True)
    numero_motor = Column(String(100), nullable=True)
    destino = Column(String(50), nullable=True, server_default="DESARME")
    grua = Column(String(100), nullable=True)
    observaciones = Column(Text, nullable=True)
    traccion = Column(String(50), nullable=True)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

class Categoria_Activo(Base):
    __tablename__ = "Categoria_Activo"

    id_categoria = Column(Integer, primary_key=True, autoincrement=True)
    nombre_categoria = Column(String(50), nullable=False, unique=True)

class Estado_Activo(Base):
    __tablename__ = "Estado_Activo"

    id_estado = Column(Integer, primary_key=True, autoincrement=True)
    nombre_estado = Column(String(50), nullable=False, unique=True)

class Activo_Inventariado(Base):
    __tablename__ = "Activo_Inventariado"

    id_activo = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sku_qr_fisico = Column(String(100), nullable=False, unique=True)
    id_categoria = Column(Integer, ForeignKey("Categoria_Activo.id_categoria"), nullable=False)
    id_estado = Column(Integer, ForeignKey("Estado_Activo.id_estado"), nullable=False)
    id_sucursal_actual = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    id_vehiculo = Column(UUID(as_uuid=True), ForeignKey("Vehiculo_Origen.id_vehiculo"), nullable=True)
    ubicacion_pasillo = Column(String(50), nullable=True)
    ubicacion_galpon = Column(String(50), nullable=True)
    ubicacion_pallet = Column(String(50), nullable=True)
    precio_referencia = Column(Integer, nullable=True)
    precio_minimo = Column(Integer, nullable=True)
    precio_maximo = Column(Integer, nullable=True)
    observacion_estado = Column(Text, nullable=True)
    version_lock = Column(Integer, nullable=False, default=1)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)
    qr_impreso = Column(Boolean, nullable=False, default=False)
    reservado_por = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=True)
    reserva_expira_en = Column(DateTime, nullable=True)

class Detalle_Motor(Base):
    __tablename__ = "Detalle_Motor"

    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), primary_key=True)
    numero_motor = Column(String(100), nullable=True)
    cilindrada = Column(String(20), nullable=True)
    combustible = Column(String(50), nullable=True)
    transmision_tipo = Column(String(50), nullable=True)

class Detalle_Caja_Cambio(Base):
    __tablename__ = "Detalle_Caja_Cambio"

    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), primary_key=True)
    transmision_tipo = Column(String(50), nullable=True)

class Multimedia_Activo(Base):
    __tablename__ = "Multimedia_Activo"

    id_multimedia = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), nullable=False)
    url_storage = Column(String(255), nullable=False)
    tipo_archivo = Column(String(20), nullable=False) 

# ==========================================
# MICRO-CRM, VENTAS Y PAGOS
# ==========================================

class Cliente(Base):
    __tablename__ = "Cliente"

    id_cliente = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    rut_cliente = Column(String(12), nullable=False, unique=True)
    nombres = Column(String(100), nullable=False)
    apellidos = Column(String(100), nullable=False)
    correo = Column(String(150), nullable=True)
    telefono = Column(String(20), nullable=True)
    id_comuna = Column(Integer, ForeignKey("Comuna.id_comuna"), nullable=True)
    consentimiento_legal = Column(Boolean, nullable=False, default=True)
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

class Orden_Venta(Base):
    __tablename__ = "Orden_Venta"
    __table_args__ = (
        CheckConstraint(
            "estado_orden IN ('Reservada', 'Pagada', 'Despachada', 'Completada', 'Anulada')",
            name="check_orden_venta_estado_orden",
        ),
    )

    id_orden = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_cliente = Column(UUID(as_uuid=True), ForeignKey("Cliente.id_cliente"), nullable=False)
    id_vendedor = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    id_vendedor_asignado = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=True)
    id_cajera = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=True)
    id_sucursal = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    estado_orden = Column(String(30), nullable=False, server_default="Reservada")
    qr_transaccional_salida = Column(String(255), nullable=True, unique=True)
    total_venta = Column(Integer, nullable=False, default=0)
    descuento = Column(Integer, nullable=False, server_default="0", default=0)
    monto_pendiente = Column(Integer, nullable=False, default=0)
    abono_requerido = Column(Integer, nullable=False, default=0)
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)
    numero_orden = Column(Integer, Sequence("Orden_Venta_numero_orden_seq"), nullable=True)
    motivo_anulacion = Column(String(100), nullable=True)
    observacion_anulacion = Column(Text, nullable=True)
    id_usuario_anulacion = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=True)
    fecha_anulacion = Column(DateTime(timezone=True), nullable=True)

    usuario_anulacion = relationship("Usuario", foreign_keys=[id_usuario_anulacion])

    @property
    def folio(self) -> str:
        """
        Retorna el folio comercial formateado de la orden.
        Si posee numero_orden asignado por BD, formatea ORD-0001.
        De lo contrario, genera la convención ORD-XXXXXXXX con los primeros 8 caracteres del UUID.
        """
        if self.numero_orden is not None:
            return f"ORD-{self.numero_orden:04d}"
        if self.qr_transaccional_salida and self.qr_transaccional_salida.startswith("ORD-"):
            return self.qr_transaccional_salida
        return f"ORD-{str(self.id_orden).replace('-', '')[:8].upper()}"

class Detalle_Orden(Base):
    __tablename__ = "Detalle_Orden"

    id_detalle = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=False)
    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), nullable=True)
    descripcion_manual = Column(String(255), nullable=True)
    notas_preparacion = Column(String(255), nullable=True)
    cantidad = Column(Integer, nullable=False, default=1)
    precio_unitario = Column(Integer, nullable=True)
    precio_final = Column(Integer, nullable=False)
    estado_preparacion = Column(String(30), nullable=False, server_default="Pendiente", default="Pendiente")
    fecha_preparacion = Column(DateTime, nullable=True)

    @property
    def preparacion_lista(self) -> bool:
        return self.estado_preparacion == "Listo"

    @preparacion_lista.setter
    def preparacion_lista(self, val: bool) -> None:
        self.estado_preparacion = "Listo" if val else "Pendiente"

class Reservas_Backorder(Base):
    __tablename__ = "Reservas_Backorder"

    id_reserva = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_cliente = Column(UUID(as_uuid=True), ForeignKey("Cliente.id_cliente"), nullable=False)
    id_vendedor = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=True)
    id_sucursal_registro = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    id_categoria_requerida = Column(Integer, ForeignKey("Categoria_Activo.id_categoria"), nullable=False)
    marca_requerida = Column(String(100), nullable=False)
    modelo_requerido = Column(String(100), nullable=False)
    anio_requerido = Column(Integer, nullable=True)
    cilindrada_requerida = Column(String(20), nullable=True)
    combustible_requerido = Column(String(50), nullable=True)
    transmision_requerida = Column(String(50), nullable=True)
    notas_preparacion = Column(String(255), nullable=True)
    precio_acordado = Column(Integer, nullable=False)
    monto_abonado = Column(Integer, nullable=False, default=0)
    abono_requerido = Column(Integer, nullable=False, default=0)
    id_activo_asignado = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), nullable=True)
    estado_reserva = Column(String(30), nullable=False, server_default="Pendiente")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

class Transaccion_Pago(Base):
    __tablename__ = "Transaccion_Pago"

    id_pago = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=True)
    id_reserva = Column(UUID(as_uuid=True), ForeignKey("Reservas_Backorder.id_reserva"), nullable=True)
    monto = Column(Integer, nullable=False)
    metodo_pago = Column(String(50), nullable=False)
    estado_pago = Column(String(20), nullable=False, server_default="Procesado")
    fecha_pago = Column(DateTime, nullable=False, server_default=text("now()"))

# ==========================================
# BARRERA DIGITAL Y LOGÍSTICA
# ==========================================

class Auditoria_Barrera(Base):
    __tablename__ = "Auditoria_Barrera"

    id_auditoria = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=False)
    id_bodeguero = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    fecha_escaneo = Column(DateTime, nullable=False, server_default=text("now()"))
    match_exitoso = Column(Boolean, nullable=False)

class Tracking_Logistico(Base):
    __tablename__ = "Tracking_Logistico"

    id_tracking = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), nullable=False)
    id_sucursal_origen = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    id_sucursal_destino = Column(Integer, ForeignKey("Sucursal.id_sucursal"), nullable=False)
    id_usuario_gestor = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=True)
    fecha_movimiento = Column(DateTime, nullable=False, server_default=text("now()"))
    estado_traslado = Column(String(30), nullable=False)

class Despacho(Base):
    __tablename__ = "Despacho"
    __table_args__ = (
        CheckConstraint(
            "estado_despacho IN ('Por Enviar', 'Enviado')",
            name="check_despacho_estado_despacho",
        ),
    )

    id_despacho = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    id_orden = Column(UUID(as_uuid=True), ForeignKey("Orden_Venta.id_orden"), nullable=False, unique=True)
    id_comuna_destino = Column(Integer, ForeignKey("Comuna.id_comuna"), nullable=False)
    direccion_envio = Column(String(255), nullable=False)
    receptor_nombres = Column(String(100), nullable=False)
    receptor_rut = Column(String(12), nullable=False)
    receptor_telefono = Column(String(20), nullable=False)
    empresa_transporte = Column(String(100), nullable=True)
    costo_envio = Column(Integer, nullable=True)
    estado_despacho = Column(String(30), nullable=False, server_default="Enviado")
    estado = Column(String(20), nullable=False, server_default="Activo")
    fecha_creacion = Column(DateTime, nullable=False, server_default=text("now()"))
    fecha_actualizacion = Column(DateTime, nullable=True)

# ==========================================
# BITÁCORA Y AUDITORÍA DE MOVIMIENTOS WMS
# ==========================================

class Bitacora_Movimiento_Inventario(Base):
    __tablename__ = "Bitacora_Movimiento_Inventario"

    id_bitacora = Column(Integer, primary_key=True, autoincrement=True)
    id_activo = Column(UUID(as_uuid=True), ForeignKey("Activo_Inventariado.id_activo"), nullable=False)
    id_usuario = Column(UUID(as_uuid=True), ForeignKey("Usuario.id_usuario"), nullable=False)
    tipo_evento = Column(String(50), nullable=False)
    ubicacion_anterior = Column(String(100), nullable=True)
    ubicacion_nueva = Column(String(100), nullable=True)
    motivo = Column(String(100), nullable=False)
    observacion = Column(Text, nullable=False)
    fecha_registro = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))

    activo = relationship("Activo_Inventariado")
    usuario = relationship("Usuario")

# ==========================================
# COLA Y RESILIENCIA DE NOTIFICACIONES SISTEMA
# ==========================================

class Notificacion_Sistema(Base):
    __tablename__ = "Notificacion_Sistema"

    id_notificacion = Column(Integer, primary_key=True, autoincrement=True)
    canal = Column(String(20), nullable=False, server_default="TELEGRAM")
    destinatario = Column(String(100), nullable=False)
    tipo_evento = Column(String(50), nullable=False)
    referencia_id = Column(String(100), nullable=False)
    mensaje = Column(Text, nullable=False)
    estado = Column(String(20), nullable=False, server_default="PENDIENTE")
    intentos = Column(Integer, nullable=False, default=0)
    ultimo_error = Column(Text, nullable=True)
    fecha_creacion = Column(DateTime(timezone=True), nullable=False, server_default=text("now()"))
    fecha_envio = Column(DateTime(timezone=True), nullable=True)