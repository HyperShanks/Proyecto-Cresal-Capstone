-- ==============================================================================
-- SISTEMA CRESAL SAAS - ESQUEMA DE BASE DE DATOS OFICIAL (DDL)
-- Proyecto: Capstone Profesional de Ingeniería
-- Motor: PostgreSQL 14+ / Supabase
-- Archivo: 01_schema_cresal.sql
-- ==============================================================================

-- 0. Habilitar extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==========================================
-- 1. ESTRUCTURA GEOGRÁFICA Y SUCURSALES
-- ==========================================

CREATE TABLE IF NOT EXISTS "Region" (
    id_region SERIAL PRIMARY KEY,
    nombre_region VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS "Comuna" (
    id_comuna SERIAL PRIMARY KEY,
    nombre_comuna VARCHAR(100) NOT NULL,
    id_region INTEGER NOT NULL REFERENCES "Region"(id_region) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "Sucursal" (
    id_sucursal SERIAL PRIMARY KEY,
    nombre_sucursal VARCHAR(100) NOT NULL,
    direccion VARCHAR(255) NOT NULL,
    sector VARCHAR(100) NULL,
    id_comuna INTEGER NOT NULL REFERENCES "Comuna"(id_comuna) ON DELETE RESTRICT,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

-- ==========================================
-- 2. CONTROL DE ACCESO (RBAC) Y USUARIOS
-- ==========================================

CREATE TABLE IF NOT EXISTS "Rol" (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL UNIQUE,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE IF NOT EXISTS "Usuario" (
    id_usuario UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_rol INTEGER NOT NULL REFERENCES "Rol"(id_rol) ON DELETE RESTRICT,
    id_sucursal INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    rut_usuario VARCHAR(12) NOT NULL UNIQUE,
    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    pin_acceso VARCHAR(4) NOT NULL UNIQUE,
    telegram_chat_id VARCHAR(100) NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_usuario_email ON "Usuario"(email);
CREATE INDEX IF NOT EXISTS idx_usuario_pin ON "Usuario"(pin_acceso);

-- ==========================================
-- 3. MESA DE AYUDA Y TICKETS INTERNOS
-- ==========================================

CREATE TABLE IF NOT EXISTS "Ticket_Soporte" (
    id_ticket UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo_ticket VARCHAR(50) NOT NULL,
    prioridad VARCHAR(20) NOT NULL DEFAULT 'Media',
    asunto VARCHAR(150) NOT NULL,
    descripcion VARCHAR(1000) NOT NULL,
    id_usuario_creador UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE CASCADE,
    id_usuario_resolutor UUID NULL REFERENCES "Usuario"(id_usuario) ON DELETE SET NULL,
    tabla_referencia VARCHAR(50) NULL,
    id_referencia UUID NULL,
    estado_ticket VARCHAR(30) NOT NULL DEFAULT 'Abierto',
    observacion_cierre VARCHAR(1000) NULL,
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_cierre TIMESTAMP WITHOUT TIME ZONE NULL
);

-- ==========================================
-- 4. VEHÍCULOS DONANTES E INVENTARIO
-- ==========================================

CREATE TABLE IF NOT EXISTS "Vehiculo_Origen" (
    id_vehiculo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_ingreso VARCHAR(10) NOT NULL UNIQUE,
    patente VARCHAR(20) NOT NULL UNIQUE,
    vin VARCHAR(17) NULL UNIQUE,
    factura VARCHAR(50) NULL,
    fecha_ingreso DATE NULL DEFAULT CURRENT_DATE,
    origen VARCHAR(100) NULL,
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(100) NOT NULL,
    anio INTEGER NULL,
    color VARCHAR(50) NULL,
    numero_motor VARCHAR(100) NULL,
    destino VARCHAR(50) NULL DEFAULT 'DESARME',
    grua VARCHAR(100) NULL,
    observaciones TEXT NULL,
    traccion VARCHAR(50) NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE IF NOT EXISTS "Categoria_Activo" (
    id_categoria SERIAL PRIMARY KEY,
    nombre_categoria VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "Estado_Activo" (
    id_estado SERIAL PRIMARY KEY,
    nombre_estado VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "Activo_Inventariado" (
    id_activo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku_qr_fisico VARCHAR(100) NOT NULL UNIQUE,
    id_categoria INTEGER NOT NULL REFERENCES "Categoria_Activo"(id_categoria) ON DELETE RESTRICT,
    id_estado INTEGER NOT NULL REFERENCES "Estado_Activo"(id_estado) ON DELETE RESTRICT,
    id_sucursal_actual INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    id_vehiculo UUID NULL REFERENCES "Vehiculo_Origen"(id_vehiculo) ON DELETE SET NULL,
    ubicacion_pasillo VARCHAR(50) NULL,
    ubicacion_galpon VARCHAR(50) NULL,
    ubicacion_pallet VARCHAR(50) NULL,
    precio_referencia INTEGER NULL,
    precio_minimo INTEGER NULL,
    precio_maximo INTEGER NULL,
    observacion_estado TEXT NULL,
    version_lock INTEGER NOT NULL DEFAULT 1,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL,
    qr_impreso BOOLEAN NOT NULL DEFAULT FALSE,
    reservado_por UUID NULL REFERENCES "Usuario"(id_usuario) ON DELETE SET NULL,
    reserva_expira_en TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_activo_sku ON "Activo_Inventariado"(sku_qr_fisico);
CREATE INDEX IF NOT EXISTS idx_activo_sucursal_estado ON "Activo_Inventariado"(id_sucursal_actual, id_estado);

CREATE TABLE IF NOT EXISTS "Detalle_Motor" (
    id_activo UUID PRIMARY KEY REFERENCES "Activo_Inventariado"(id_activo) ON DELETE CASCADE,
    numero_motor VARCHAR(100) NULL,
    cilindrada VARCHAR(20) NULL,
    combustible VARCHAR(50) NULL,
    transmision_tipo VARCHAR(50) NULL
);

CREATE TABLE IF NOT EXISTS "Detalle_Caja_Cambio" (
    id_activo UUID PRIMARY KEY REFERENCES "Activo_Inventariado"(id_activo) ON DELETE CASCADE,
    transmision_tipo VARCHAR(50) NULL
);

CREATE TABLE IF NOT EXISTS "Multimedia_Activo" (
    id_multimedia UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_activo UUID NOT NULL REFERENCES "Activo_Inventariado"(id_activo) ON DELETE CASCADE,
    url_storage VARCHAR(255) NOT NULL,
    tipo_archivo VARCHAR(20) NOT NULL
);

-- ==========================================
-- 5. CLIENTES, VENTAS Y CAJA
-- ==========================================

CREATE TABLE IF NOT EXISTS "Cliente" (
    id_cliente UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rut_cliente VARCHAR(12) NOT NULL UNIQUE,
    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    correo VARCHAR(150) NULL,
    telefono VARCHAR(20) NULL,
    id_comuna INTEGER NULL REFERENCES "Comuna"(id_comuna) ON DELETE SET NULL,
    consentimiento_legal BOOLEAN NOT NULL DEFAULT TRUE,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_cliente_rut ON "Cliente"(rut_cliente);

CREATE SEQUENCE IF NOT EXISTS "Orden_Venta_numero_orden_seq" START 1;

CREATE TABLE IF NOT EXISTS "Orden_Venta" (
    id_orden UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente UUID NOT NULL REFERENCES "Cliente"(id_cliente) ON DELETE RESTRICT,
    id_vendedor UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE RESTRICT,
    id_vendedor_asignado UUID NULL REFERENCES "Usuario"(id_usuario) ON DELETE SET NULL,
    id_cajera UUID NULL REFERENCES "Usuario"(id_usuario) ON DELETE SET NULL,
    id_sucursal INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    estado_orden VARCHAR(30) NOT NULL DEFAULT 'Reservada',
    qr_transaccional_salida VARCHAR(255) NULL UNIQUE,
    total_venta INTEGER NOT NULL DEFAULT 0,
    descuento INTEGER NOT NULL DEFAULT 0,
    monto_pendiente INTEGER NOT NULL DEFAULT 0,
    abono_requerido INTEGER NOT NULL DEFAULT 0,
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL,
    numero_orden INTEGER DEFAULT nextval('"Orden_Venta_numero_orden_seq"'),
    motivo_anulacion VARCHAR(100) NULL,
    observacion_anulacion TEXT NULL,
    id_usuario_anulacion UUID NULL REFERENCES "Usuario"(id_usuario) ON DELETE SET NULL,
    fecha_anulacion TIMESTAMP WITH TIME ZONE NULL,
    CONSTRAINT check_orden_venta_estado_orden CHECK (estado_orden IN ('Reservada', 'Pagada', 'Despachada', 'Completada', 'Anulada'))
);

CREATE INDEX IF NOT EXISTS idx_orden_venta_sucursal_estado ON "Orden_Venta"(id_sucursal, estado_orden);

CREATE TABLE IF NOT EXISTS "Detalle_Orden" (
    id_detalle UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden UUID NOT NULL REFERENCES "Orden_Venta"(id_orden) ON DELETE CASCADE,
    id_activo UUID NULL REFERENCES "Activo_Inventariado"(id_activo) ON DELETE SET NULL,
    descripcion_manual VARCHAR(255) NULL,
    notas_preparacion VARCHAR(255) NULL,
    cantidad INTEGER NOT NULL DEFAULT 1,
    precio_unitario INTEGER NULL,
    precio_final INTEGER NOT NULL,
    estado_preparacion VARCHAR(30) NOT NULL DEFAULT 'Pendiente',
    fecha_preparacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE IF NOT EXISTS "Reservas_Backorder" (
    id_reserva UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cliente UUID NOT NULL REFERENCES "Cliente"(id_cliente) ON DELETE RESTRICT,
    id_vendedor UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE RESTRICT,
    id_orden UUID NULL REFERENCES "Orden_Venta"(id_orden) ON DELETE SET NULL,
    id_sucursal_registro INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    id_categoria_requerida INTEGER NOT NULL REFERENCES "Categoria_Activo"(id_categoria) ON DELETE RESTRICT,
    marca_requerida VARCHAR(100) NOT NULL,
    modelo_requerido VARCHAR(100) NOT NULL,
    anio_requerido INTEGER NULL,
    cilindrada_requerida VARCHAR(20) NULL,
    combustible_requerido VARCHAR(50) NULL,
    transmision_requerida VARCHAR(50) NULL,
    notas_preparacion VARCHAR(255) NULL,
    precio_acordado INTEGER NOT NULL,
    monto_abonado INTEGER NOT NULL DEFAULT 0,
    abono_requerido INTEGER NOT NULL DEFAULT 0,
    id_activo_asignado UUID NULL REFERENCES "Activo_Inventariado"(id_activo) ON DELETE SET NULL,
    estado_reserva VARCHAR(30) NOT NULL DEFAULT 'Pendiente',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE IF NOT EXISTS "Transaccion_Pago" (
    id_pago UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden UUID NULL REFERENCES "Orden_Venta"(id_orden) ON DELETE CASCADE,
    id_reserva UUID NULL REFERENCES "Reservas_Backorder"(id_reserva) ON DELETE CASCADE,
    monto INTEGER NOT NULL,
    metodo_pago VARCHAR(50) NOT NULL,
    estado_pago VARCHAR(20) NOT NULL DEFAULT 'Procesado',
    fecha_pago TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 6. BARRERA DIGITAL, LOGÍSTICA Y DESPACHOS
-- ==========================================

CREATE TABLE IF NOT EXISTS "Auditoria_Barrera" (
    id_auditoria UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden UUID NOT NULL REFERENCES "Orden_Venta"(id_orden) ON DELETE CASCADE,
    id_bodeguero UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE RESTRICT,
    fecha_escaneo TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    match_exitoso BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS "Tracking_Logistico" (
    id_tracking UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_activo UUID NOT NULL REFERENCES "Activo_Inventariado"(id_activo) ON DELETE CASCADE,
    id_sucursal_origen INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    id_sucursal_destino INTEGER NOT NULL REFERENCES "Sucursal"(id_sucursal) ON DELETE RESTRICT,
    id_usuario_gestor UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE RESTRICT,
    id_orden UUID NULL REFERENCES "Orden_Venta"(id_orden) ON DELETE SET NULL,
    fecha_movimiento TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    estado_traslado VARCHAR(30) NOT NULL
);

CREATE TABLE IF NOT EXISTS "Despacho" (
    id_despacho UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden UUID NOT NULL UNIQUE REFERENCES "Orden_Venta"(id_orden) ON DELETE CASCADE,
    id_comuna_destino INTEGER NOT NULL REFERENCES "Comuna"(id_comuna) ON DELETE RESTRICT,
    direccion_envio VARCHAR(255) NOT NULL,
    receptor_nombres VARCHAR(100) NOT NULL,
    receptor_rut VARCHAR(12) NOT NULL,
    receptor_telefono VARCHAR(20) NOT NULL,
    empresa_transporte VARCHAR(100) NULL,
    costo_envio INTEGER NULL,
    estado_despacho VARCHAR(30) NOT NULL DEFAULT 'Enviado',
    estado VARCHAR(20) NOT NULL DEFAULT 'Activo',
    fecha_creacion TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE NULL,
    CONSTRAINT check_despacho_estado_despacho CHECK (estado_despacho IN ('Por Enviar', 'Enviado'))
);

-- ==========================================
-- 7. BITÁCORA FORENSE WMS Y NOTIFICACIONES
-- ==========================================

CREATE TABLE IF NOT EXISTS "Bitacora_Movimiento_Inventario" (
    id_bitacora SERIAL PRIMARY KEY,
    id_activo UUID NOT NULL REFERENCES "Activo_Inventariado"(id_activo) ON DELETE CASCADE,
    id_usuario UUID NOT NULL REFERENCES "Usuario"(id_usuario) ON DELETE RESTRICT,
    tipo_evento VARCHAR(50) NOT NULL,
    ubicacion_anterior VARCHAR(100) NULL,
    ubicacion_nueva VARCHAR(100) NULL,
    motivo VARCHAR(100) NOT NULL,
    observacion TEXT NOT NULL,
    fecha_registro TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bitacora_activo ON "Bitacora_Movimiento_Inventario"(id_activo);
CREATE INDEX IF NOT EXISTS idx_bitacora_fecha ON "Bitacora_Movimiento_Inventario"(fecha_registro DESC);

CREATE TABLE IF NOT EXISTS "Notificacion_Sistema" (
    id_notificacion SERIAL PRIMARY KEY,
    canal VARCHAR(20) NOT NULL DEFAULT 'TELEGRAM',
    destinatario VARCHAR(100) NOT NULL,
    tipo_evento VARCHAR(50) NOT NULL,
    referencia_id VARCHAR(100) NOT NULL,
    mensaje TEXT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    intentos INTEGER NOT NULL DEFAULT 0,
    ultimo_error TEXT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_envio TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_notif_estado_fecha ON "Notificacion_Sistema"(estado, fecha_creacion DESC);
