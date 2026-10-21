-- ==============================================================================
-- SISTEMA CRESAL SAAS - DATOS SIMULADOS DE EVALUACIÓN ACADÉMICA (SEEDS)
-- Proyecto: Capstone Profesional de Ingeniería
-- Motor: PostgreSQL 14+ / Supabase
-- Archivo: 02_seed_simulado.sql
-- ==============================================================================

-- 1. GEOGRAFÍA BASE (Regiones y Comunas de Operación)
INSERT INTO "Region" (id_region, nombre_region) VALUES 
    (1, 'Valparaíso'),
    (2, 'Metropolitana de Santiago')
ON CONFLICT (id_region) DO NOTHING;

INSERT INTO "Comuna" (id_comuna, nombre_comuna, id_region) VALUES 
    (1, 'Viña del Mar', 1),
    (2, 'Limache', 1),
    (3, 'Quilpué', 1),
    (4, 'Santiago Centro', 2)
ON CONFLICT (id_comuna) DO NOTHING;

-- 2. SUCURSALES OPERATIVAS
INSERT INTO "Sucursal" (id_sucursal, nombre_sucursal, direccion, sector, id_comuna, estado) VALUES
    (1, 'Casa Matriz Viña del Mar', 'Av. Libertad 1234', 'Central', 1, 'Activo'),
    (2, 'Sucursal Limache', 'Calle Los Aromos 456', 'Industrial', 2, 'Activo')
ON CONFLICT (id_sucursal) DO UPDATE 
SET nombre_sucursal = EXCLUDED.nombre_sucursal, direccion = EXCLUDED.direccion;

-- 3. ROLES DE SISTEMA (RBAC)
INSERT INTO "Rol" (id_rol, nombre_rol, estado) VALUES
    (1, 'Bodeguero', 'Activo'),
    (2, 'Vendedor', 'Activo'),
    (3, 'Caja', 'Activo'),
    (4, 'Gerente', 'Activo'),
    (5, 'Administrador', 'Activo')
ON CONFLICT (id_rol) DO UPDATE SET nombre_rol = EXCLUDED.nombre_rol;

-- 4. CATEGORÍAS DE INVENTARIO
INSERT INTO "Categoria_Activo" (id_categoria, nombre_categoria) VALUES
    (1, 'Motor'),
    (2, 'Caja de Cambios'),
    (3, 'Accesorio')
ON CONFLICT (id_categoria) DO NOTHING;

-- 5. ESTADOS DEL ACTIVO LOGÍSTICO
INSERT INTO "Estado_Activo" (id_estado, nombre_estado) VALUES
    (1, 'En Desarme'),
    (2, 'Disponible'),
    (3, 'Reservado'),
    (4, 'Vendido'),
    (5, 'En Importación'),
    (6, 'Entregado'),
    (7, 'Paletizado')
ON CONFLICT (id_estado) DO NOTHING;

-- Sincronizar secuencias seriales de catálogos
SELECT setval(pg_get_serial_sequence('"Region"', 'id_region'), COALESCE((SELECT MAX(id_region) FROM "Region"), 1));
SELECT setval(pg_get_serial_sequence('"Comuna"', 'id_comuna'), COALESCE((SELECT MAX(id_comuna) FROM "Comuna"), 1));
SELECT setval(pg_get_serial_sequence('"Sucursal"', 'id_sucursal'), COALESCE((SELECT MAX(id_sucursal) FROM "Sucursal"), 1));
SELECT setval(pg_get_serial_sequence('"Rol"', 'id_rol'), COALESCE((SELECT MAX(id_rol) FROM "Rol"), 1));
SELECT setval(pg_get_serial_sequence('"Categoria_Activo"', 'id_categoria'), COALESCE((SELECT MAX(id_categoria) FROM "Categoria_Activo"), 1));
SELECT setval(pg_get_serial_sequence('"Estado_Activo"', 'id_estado'), COALESCE((SELECT MAX(id_estado) FROM "Estado_Activo"), 1));

-- ==============================================================================
-- 6. USUARIOS ACADÉMICOS DE PRUEBA (4 ROLES CRÍTICOS)
-- Contraseña genérica para todos: Password123! (hash bcrypt standard)
-- ==============================================================================

-- Hash Bcrypt para 'Password123!': $2b$12$K1bO.mK4P.lqK0bYwP8e5.7pL1.wI9W2vU5nJ6oQ1.eY2pW4z7a1u
INSERT INTO "Usuario" (
    id_usuario, id_rol, id_sucursal, rut_usuario, nombres, apellidos, 
    email, password_hash, pin_acceso, estado
) VALUES
    (
        '11111111-1111-1111-1111-111111111111', 5, 1, '11.111.111-1', 
        'Administrador', 'Sistema Cresal', 'admin@cresal.cl', 
        '$2b$12$K1bO.mK4P.lqK0bYwP8e5.7pL1.wI9W2vU5nJ6oQ1.eY2pW4z7a1u', '5005', 'Activo'
    ),
    (
        '22222222-2222-2222-2222-222222222222', 2, 1, '12.222.222-2', 
        'Carlos', 'Vendedor Mesón', 'vendedor@cresal.cl', 
        '$2b$12$K1bO.mK4P.lqK0bYwP8e5.7pL1.wI9W2vU5nJ6oQ1.eY2pW4z7a1u', '2002', 'Activo'
    ),
    (
        '33333333-3333-3333-3333-333333333333', 3, 1, '13.333.333-3', 
        'Lorena', 'Cajera Central', 'caja@cresal.cl', 
        '$2b$12$K1bO.mK4P.lqK0bYwP8e5.7pL1.wI9W2vU5nJ6oQ1.eY2pW4z7a1u', '3003', 'Activo'
    ),
    (
        '44444444-4444-4444-4444-444444444444', 1, 1, '14.444.444-4', 
        'Juan Pablo', 'Bodeguero Patio', 'bodega@cresal.cl', 
        '$2b$12$K1bO.mK4P.lqK0bYwP8e5.7pL1.wI9W2vU5nJ6oQ1.eY2pW4z7a1u', '1001', 'Activo'
    )
ON CONFLICT (rut_usuario) DO NOTHING;

-- ==============================================================================
-- 7. VEHÍCULOS DONANTES DE PRUEBA
-- ==============================================================================
INSERT INTO "Vehiculo_Origen" (
    id_vehiculo, numero_ingreso, patente, vin, marca, modelo, anio, color, numero_motor, destino, estado
) VALUES
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ING-1001', 'KJHT22', '8AJBA3CD4E5678901', 
        'Toyota', 'Hilux 2.4 Diesel', 2021, 'Blanco', '2GD-FTV-998811', 'DESARME', 'Activo'
    ),
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'ING-1002', 'LPRT88', 'KMHCT81DBJU123456', 
        'Hyundai', 'Tucson 2.0 CRDi', 2019, 'Gris Plata', 'D4HA-123456', 'DESARME', 'Activo'
    )
ON CONFLICT (numero_ingreso) DO NOTHING;

-- ==============================================================================
-- 8. 10 REPUESTOS AUTOMOTRICES FICTICIOS (STOCK Y PRECIOS SIMULADOS)
-- ==============================================================================

-- 8.1. Motor Completo Toyota Hilux 2.4 Diesel (MOT-1001)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000001-0000-0000-0000-000000000001', 'MOT-1001', 1, 2, 1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Pasillo A', 'Galpón 1', 'PAL-01', 2500000, 2200000, 2800000,
    'Motor probado en banco, compresión 180 PSI uniforme. Sin fugas.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

INSERT INTO "Detalle_Motor" (id_activo, numero_motor, cilindrada, combustible, transmision_tipo)
VALUES ('a0000001-0000-0000-0000-000000000001', '2GD-FTV-998811', '2400', 'Diesel', 'Manual')
ON CONFLICT (id_activo) DO NOTHING;

-- 8.2. Caja de Cambios Toyota Hilux 4x4 Manual (CAJ-1001)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000002-0000-0000-0000-000000000002', 'CAJ-1001', 2, 2, 1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Pasillo A', 'Galpón 1', 'PAL-02', 850000, 750000, 950000,
    'Transmisión 6 velocidades manual 4WD en excelente estado sincronizado.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

INSERT INTO "Detalle_Caja_Cambio" (id_activo, transmision_tipo)
VALUES ('a0000002-0000-0000-0000-000000000002', 'Manual 4x4')
ON CONFLICT (id_activo) DO NOTHING;

-- 8.3. Turbo Compresor Hilux 2GD (ACC-1001)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000003-0000-0000-0000-000000000003', 'ACC-1001', 3, 2, 1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Estante B3', 'Galpón 1', 'PAL-03', 380000, 320000, 420000,
    'Turbocompresor de geometría variable original Toyota / IHI sin juego axial.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

-- 8.4. Alternador Original Hilux 12V 100A (ACC-1002)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000004-0000-0000-0000-000000000004', 'ACC-1002', 3, 2, 1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Estante B1', 'Galpón 1', 'PAL-04', 160000, 130000, 180000,
    'Alternador Denso original verificado en banco de carga.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

-- 8.5. Motor de Partida Hilux 2.4 (ACC-1003)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000005-0000-0000-0000-000000000005', 'ACC-1003', 3, 2, 1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Estante B2', 'Galpón 1', 'PAL-05', 140000, 110000, 160000,
    'Motor de arranque probado, piñón y bendix operativos.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

-- 8.6. Motor Completo Hyundai Tucson 2.0 CRDi (MOT-1002)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000006-0000-0000-0000-000000000006', 'MOT-1002', 1, 2, 1, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Pasillo C', 'Galpón 2', 'PAL-06', 2200000, 1950000, 2400000,
    'Motor D4HA 2.0 litros diésel common rail con bomba de inyección.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

INSERT INTO "Detalle_Motor" (id_activo, numero_motor, cilindrada, combustible, transmision_tipo)
VALUES ('a0000006-0000-0000-0000-000000000006', 'D4HA-123456', '2000', 'Diesel', 'Automatica')
ON CONFLICT (id_activo) DO NOTHING;

-- 8.7. Caja de Cambios Hyundai Tucson Automática (CAJ-1002)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000007-0000-0000-0000-000000000007', 'CAJ-1002', 2, 2, 1, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Pasillo C', 'Galpón 2', 'PAL-07', 790000, 690000, 890000,
    'Transmisión automática de 6 velocidades con convertidor de par.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

INSERT INTO "Detalle_Caja_Cambio" (id_activo, transmision_tipo)
VALUES ('a0000007-0000-0000-0000-000000000007', 'Automatica')
ON CONFLICT (id_activo) DO NOTHING;

-- 8.8. Compresor de Aire Acondicionado Tucson (ACC-1004)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000008-0000-0000-0000-000000000008', 'ACC-1004', 3, 2, 1, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Estante D1', 'Galpón 2', 'PAL-08', 190000, 160000, 220000,
    'Compresor de A/C original Doowon probado sin fugas con embrague magnético operativo.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

-- 8.9. Bomba de Dirección Hidráulica Tucson (ACC-1005)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000009-0000-0000-0000-000000000009', 'ACC-1005', 3, 2, 1, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Estante D2', 'Galpón 2', 'PAL-09', 120000, 95000, 140000,
    'Bomba hidráulica de dirección probada en banco de presión.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;

-- 8.10. Riel de Inyección Common Rail Hyundai (ACC-1006)
INSERT INTO "Activo_Inventariado" (
    id_activo, sku_qr_fisico, id_categoria, id_estado, id_sucursal_actual, id_vehiculo,
    ubicacion_pasillo, ubicacion_galpon, ubicacion_pallet, precio_referencia, precio_minimo, precio_maximo,
    observacion_estado, qr_impreso, estado
) VALUES (
    'a0000010-0000-0000-0000-000000000010', 'ACC-1006', 3, 2, 1, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Estante D3', 'Galpón 2', 'PAL-10', 210000, 175000, 240000,
    'Riel de combustible de alta presión Bosch con sensor y válvula reguladora incluidos.', TRUE, 'Activo'
) ON CONFLICT (sku_qr_fisico) DO NOTHING;
