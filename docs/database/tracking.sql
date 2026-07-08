-- ============================================================================
-- EXTENSIONES NECESARIAS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- FUNCIÓN PARA ACTUALIZAR updated_at AUTOMÁTICAMENTE
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- ============================================================================
-- MÓDULO: CORE
-- ============================================================================

-- Tabla: empresas
CREATE TABLE core_empresas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre VARCHAR(255) NOT NULL,
    ruc VARCHAR(20) UNIQUE,
    telefono VARCHAR(20),
    email VARCHAR(255),
    logo TEXT,
    estado VARCHAR(20) DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo', 'suspendido')),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_empresas_ruc ON core_empresas(ruc) WHERE deleted_at IS NULL;
CREATE INDEX idx_empresas_estado ON core_empresas(estado) WHERE deleted_at IS NULL;

CREATE TRIGGER update_empresas_updated_at BEFORE UPDATE ON core_empresas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: sucursales
CREATE TABLE core_sucursales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    nombre VARCHAR(255) NOT NULL,
    direccion TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    telefono VARCHAR(20),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_sucursales_empresa ON core_sucursales(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_sucursales_ubicacion ON core_sucursales USING GIST(ubicacion);

CREATE TRIGGER update_sucursales_updated_at BEFORE UPDATE ON core_sucursales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: roles
CREATE TABLE core_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    es_sistema BOOLEAN DEFAULT FALSE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    CONSTRAINT unique_rol_empresa UNIQUE (empresa_id, nombre)
);

CREATE INDEX idx_roles_empresa ON core_roles(empresa_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_roles_updated_at BEFORE UPDATE ON core_roles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insertar roles del sistema
INSERT INTO core_roles (nombre, es_sistema) VALUES
    ('Administrador', true),
    ('Supervisor', true),
    ('Operador', true),
    ('Chofer', true),
    ('Cliente', true),
    ('Auditor', true);

-- Tabla: permisos
CREATE TABLE core_permisos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rol_id UUID NOT NULL REFERENCES core_roles(id) ON DELETE CASCADE,
    modulo VARCHAR(100) NOT NULL,
    crear BOOLEAN DEFAULT FALSE,
    editar BOOLEAN DEFAULT FALSE,
    eliminar BOOLEAN DEFAULT FALSE,
    leer BOOLEAN DEFAULT FALSE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_permisos_rol ON core_permisos(rol_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_permisos_modulo ON core_permisos(modulo);

CREATE TRIGGER update_permisos_updated_at BEFORE UPDATE ON core_permisos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: usuarios (relación Auth con empresa)
CREATE TABLE core_usuarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    rol_id UUID REFERENCES core_roles(id),
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    activo BOOLEAN DEFAULT TRUE,
    ultimo_login TIMESTAMP WITH TIME ZONE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_usuarios_auth ON core_usuarios(auth_user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_empresa ON core_usuarios(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_email ON core_usuarios(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_rol ON core_usuarios(rol_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_usuarios_updated_at BEFORE UPDATE ON core_usuarios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: configuraciones
CREATE TABLE core_configuraciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    clave VARCHAR(100) NOT NULL,
    valor JSONB NOT NULL,
    descripcion TEXT,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    CONSTRAINT unique_config_empresa UNIQUE (empresa_id, clave)
);

CREATE INDEX idx_configuraciones_empresa ON core_configuraciones(empresa_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_configuraciones_updated_at BEFORE UPDATE ON core_configuraciones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: FLEET
-- ============================================================================

-- Tabla: dispositivos_gps
CREATE TABLE fleet_dispositivos_gps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    imei VARCHAR(50) UNIQUE NOT NULL,
    modelo VARCHAR(100),
    serial VARCHAR(100),
    estado VARCHAR(20) DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo', 'mantenimiento')),
    ultima_conexion TIMESTAMP WITH TIME ZONE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_gps_empresa ON fleet_dispositivos_gps(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_gps_imei ON fleet_dispositivos_gps(imei);
CREATE INDEX idx_gps_estado ON fleet_dispositivos_gps(estado);

CREATE TRIGGER update_gps_updated_at BEFORE UPDATE ON fleet_dispositivos_gps
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: vehiculos
CREATE TABLE fleet_vehiculos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    matricula VARCHAR(20) NOT NULL,
    marca VARCHAR(100),
    modelo VARCHAR(100),
    anio INTEGER CHECK (anio >= 1900 AND anio <= 2100),
    capacidad_kg DECIMAL(10, 2),
    capacidad_m3 DECIMAL(10, 2),
    estado VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN ('disponible', 'en_ruta', 'mantenimiento', 'fuera_servicio')),
    gps_id UUID REFERENCES fleet_dispositivos_gps(id),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_vehiculos_empresa ON fleet_vehiculos(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_matricula ON fleet_vehiculos(matricula);
CREATE INDEX idx_vehiculos_estado ON fleet_vehiculos(estado);
CREATE INDEX idx_vehiculos_gps ON fleet_vehiculos(gps_id);

CREATE TRIGGER update_vehiculos_updated_at BEFORE UPDATE ON fleet_vehiculos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: remolques
CREATE TABLE fleet_remolques (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    vehiculo_id UUID REFERENCES fleet_vehiculos(id),
    tipo VARCHAR(50),
    capacidad_kg DECIMAL(10, 2),
    capacidad_m3 DECIMAL(10, 2),
    matricula VARCHAR(20),
    estado VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN ('disponible', 'asignado', 'mantenimiento')),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_remolques_empresa ON fleet_remolques(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_remolques_vehiculo ON fleet_remolques(vehiculo_id);

CREATE TRIGGER update_remolques_updated_at BEFORE UPDATE ON fleet_remolques
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: conductores
CREATE TABLE fleet_conductores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    usuario_id UUID REFERENCES core_usuarios(id),
    vehiculo_actual UUID REFERENCES fleet_vehiculos(id),
    licencia VARCHAR(50) NOT NULL,
    tipo_licencia VARCHAR(20),
    vencimiento_licencia DATE,
    telefono VARCHAR(20),
    foto TEXT,
    estado VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN ('disponible', 'en_ruta', 'descanso', 'inactivo')),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_conductores_empresa ON fleet_conductores(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_conductores_usuario ON fleet_conductores(usuario_id);
CREATE INDEX idx_conductores_licencia ON fleet_conductores(licencia);
CREATE INDEX idx_conductores_estado ON fleet_conductores(estado);

CREATE TRIGGER update_conductores_updated_at BEFORE UPDATE ON fleet_conductores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: mantenimientos
CREATE TABLE fleet_mantenimientos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
    tipo VARCHAR(50) NOT NULL,
    descripcion TEXT,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,
    costo DECIMAL(12, 2),
    kilometraje INTEGER,
    estado VARCHAR(20) DEFAULT 'programado' CHECK (estado IN ('programado', 'en_proceso', 'completado', 'cancelado')),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_mantenimientos_empresa ON fleet_mantenimientos(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_mantenimientos_vehiculo ON fleet_mantenimientos(vehiculo_id);
CREATE INDEX idx_mantenimientos_estado ON fleet_mantenimientos(estado);

CREATE TRIGGER update_mantenimientos_updated_at BEFORE UPDATE ON fleet_mantenimientos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: CUSTOMERS
-- ============================================================================

-- Tabla: clientes
CREATE TABLE customers_clientes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    nombre VARCHAR(255) NOT NULL,
    ruc VARCHAR(20),
    telefono VARCHAR(20),
    email VARCHAR(255),
    tipo VARCHAR(20) DEFAULT 'regular' CHECK (tipo IN ('regular', 'vip', 'corporativo')),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_clientes_empresa ON customers_clientes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_clientes_ruc ON customers_clientes(ruc) WHERE deleted_at IS NULL;
CREATE INDEX idx_clientes_email ON customers_clientes(email) WHERE deleted_at IS NULL;

CREATE TRIGGER update_clientes_updated_at BEFORE UPDATE ON customers_clientes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: direcciones
CREATE TABLE customers_direcciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
    tipo VARCHAR(20) DEFAULT 'principal' CHECK (tipo IN ('principal', 'envio', 'facturacion', 'otra')),
    direccion TEXT NOT NULL,
    ciudad VARCHAR(100),
    provincia VARCHAR(100),
    pais VARCHAR(100) DEFAULT 'Perú',
    codigo_postal VARCHAR(20),
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    referencia TEXT,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_direcciones_cliente ON customers_direcciones(cliente_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_direcciones_ubicacion ON customers_direcciones USING GIST(ubicacion);

CREATE TRIGGER update_direcciones_updated_at BEFORE UPDATE ON customers_direcciones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: remitentes
CREATE TABLE customers_remitentes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
    direccion_id UUID REFERENCES customers_direcciones(id),
    nombre VARCHAR(255) NOT NULL,
    documento VARCHAR(20),
    telefono VARCHAR(20),
    email VARCHAR(255),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_remitentes_cliente ON customers_remitentes(cliente_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_remitentes_updated_at BEFORE UPDATE ON customers_remitentes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: destinatarios
CREATE TABLE customers_destinatarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
    direccion_id UUID REFERENCES customers_direcciones(id),
    nombre VARCHAR(255) NOT NULL,
    documento VARCHAR(20),
    telefono VARCHAR(20),
    email VARCHAR(255),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_destinatarios_cliente ON customers_destinatarios(cliente_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_destinatarios_updated_at BEFORE UPDATE ON customers_destinatarios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: OPERATIONS
-- ============================================================================

-- Tabla: geocercas
CREATE TABLE operations_geocercas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    nombre VARCHAR(255) NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('circulo', 'poligono')),
    radio INTEGER, -- solo si tipo = circulo
    poligono GEOMETRY(POLYGON, 4326), -- solo si tipo = poligono
    centro GEOGRAPHY(POINT, 4326),
    color VARCHAR(20),
    activa BOOLEAN DEFAULT TRUE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_geocercas_empresa ON operations_geocercas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_geocercas_centro ON operations_geocercas USING GIST(centro);
CREATE INDEX idx_geocercas_poligono ON operations_geocercas USING GIST(poligono);

CREATE TRIGGER update_geocercas_updated_at BEFORE UPDATE ON operations_geocercas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: rutas
CREATE TABLE operations_rutas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    codigo VARCHAR(50) UNIQUE,
    nombre VARCHAR(255) NOT NULL,
    origen VARCHAR(255),
    destino VARCHAR(255),
    distancia_km DECIMAL(10, 2),
    tiempo_estimado_min INTEGER,
    activa BOOLEAN DEFAULT TRUE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_rutas_empresa ON operations_rutas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_codigo ON operations_rutas(codigo);

CREATE TRIGGER update_rutas_updated_at BEFORE UPDATE ON operations_rutas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: paradas
CREATE TABLE operations_paradas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ruta_id UUID NOT NULL REFERENCES operations_rutas(id) ON DELETE CASCADE,
    direccion_id UUID REFERENCES customers_direcciones(id),
    orden INTEGER NOT NULL,
    nombre VARCHAR(255),
    direccion TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    tipo VARCHAR(50) CHECK (tipo IN ('recogida', 'entrega', 'descanso', 'combustible', 'otra')),
    eta_minutos INTEGER,
    tiempo_estancia_min INTEGER,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_paradas_ruta ON operations_paradas(ruta_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_paradas_orden ON operations_paradas(ruta_id, orden);
CREATE INDEX idx_paradas_ubicacion ON operations_paradas USING GIST(ubicacion);

CREATE TRIGGER update_paradas_updated_at BEFORE UPDATE ON operations_paradas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: viajes
CREATE TABLE operations_viajes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    codigo VARCHAR(50) UNIQUE NOT NULL,
    conductor_id UUID REFERENCES fleet_conductores(id),
    vehiculo_id UUID REFERENCES fleet_vehiculos(id),
    ruta_id UUID REFERENCES operations_rutas(id),
    fecha_inicio TIMESTAMP WITH TIME ZONE,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    estado VARCHAR(30) DEFAULT 'programado' CHECK (estado IN (
        'programado', 'en_curso', 'pausado', 'completado', 'cancelado'
    )),
    km_estimados DECIMAL(10, 2),
    km_reales DECIMAL(10, 2),
    tiempo_estimado_min INTEGER,
    tiempo_real_min INTEGER,
    combustible_litros DECIMAL(10, 2),
    observaciones TEXT,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_viajes_empresa ON operations_viajes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_codigo ON operations_viajes(codigo);
CREATE INDEX idx_viajes_conductor ON operations_viajes(conductor_id);
CREATE INDEX idx_viajes_vehiculo ON operations_viajes(vehiculo_id);
CREATE INDEX idx_viajes_estado ON operations_viajes(estado);
CREATE INDEX idx_viajes_fecha ON operations_viajes(fecha_inicio);

CREATE TRIGGER update_viajes_updated_at BEFORE UPDATE ON operations_viajes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: checkpoints
CREATE TABLE operations_checkpoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    parada_id UUID REFERENCES operations_paradas(id),
    hora_llegada TIMESTAMP WITH TIME ZONE,
    hora_salida TIMESTAMP WITH TIME ZONE,
    estado VARCHAR(30) DEFAULT 'pendiente' CHECK (estado IN (
        'pendiente', 'llego', 'en_proceso', 'completado', 'omitido'
    )),
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    observaciones TEXT,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_checkpoints_viaje ON operations_checkpoints(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_checkpoints_parada ON operations_checkpoints(parada_id);
CREATE INDEX idx_checkpoints_estado ON operations_checkpoints(estado);

CREATE TRIGGER update_checkpoints_updated_at BEFORE UPDATE ON operations_checkpoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: SHIPPING
-- ============================================================================

-- Catálogo: estados_envio
CREATE TABLE shipping_estados_envio (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    codigo VARCHAR(50) UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    color VARCHAR(20),
    orden INTEGER,
    es_final BOOLEAN DEFAULT FALSE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

INSERT INTO shipping_estados_envio (codigo, nombre, color, orden, es_final) VALUES
    ('CREADO', 'Creado', '#9E9E9E', 1, false),
    ('PREPARANDO', 'Preparando', '#2196F3', 2, false),
    ('DESPACHADO', 'Despachado', '#03A9F4', 3, false),
    ('EN_RUTA', 'En Ruta', '#FF9800', 4, false),
    ('EN_CENTRO', 'En Centro', '#FFC107', 5, false),
    ('EN_REPARTO', 'En Reparto', '#FF5722', 6, false),
    ('ENTREGADO', 'Entregado', '#4CAF50', 7, true),
    ('DEVUELTO', 'Devuelto', '#F44336', 8, true),
    ('CANCELADO', 'Cancelado', '#795548', 9, true);

-- Tabla: paquetes
CREATE TABLE shipping_paquetes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    tracking_number VARCHAR(50) UNIQUE NOT NULL,
    codigo_qr TEXT,
    codigo_barras VARCHAR(100),
    cliente_id UUID NOT NULL REFERENCES customers_clientes(id),
    remitente_id UUID REFERENCES customers_remitentes(id),
    destinatario_id UUID REFERENCES customers_destinatarios(id),
    direccion_origen UUID REFERENCES customers_direcciones(id),
    direccion_destino UUID REFERENCES customers_direcciones(id),
    
    -- Dimensiones y peso
    peso DECIMAL(10, 3),
    volumen DECIMAL(10, 3),
    alto_cm DECIMAL(10, 2),
    ancho_cm DECIMAL(10, 2),
    largo_cm DECIMAL(10, 2),
    
    -- Información comercial
    valor_declarado DECIMAL(12, 2),
    costo_envio DECIMAL(12, 2),
    tipo VARCHAR(50) DEFAULT 'paquete' CHECK (tipo IN ('paquete', 'sobre', 'carga', 'documento')),
    prioridad VARCHAR(20) DEFAULT 'normal' CHECK (prioridad IN ('baja', 'normal', 'alta', 'urgente')),
    contenido TEXT,
    
    -- Estado y fechas
    estado_actual UUID REFERENCES shipping_estados_envio(id),
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    fecha_entrega_estimada TIMESTAMP WITH TIME ZONE,
    fecha_entrega_real TIMESTAMP WITH TIME ZONE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_paquetes_empresa ON shipping_paquetes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_paquetes_tracking ON shipping_paquetes(tracking_number);
CREATE INDEX idx_paquetes_qr ON shipping_paquetes(codigo_qr);
CREATE INDEX idx_paquetes_barras ON shipping_paquetes(codigo_barras);
CREATE INDEX idx_paquetes_cliente ON shipping_paquetes(cliente_id);
CREATE INDEX idx_paquetes_estado ON shipping_paquetes(estado_actual);
CREATE INDEX idx_paquetes_fecha ON shipping_paquetes(fecha_creacion);
CREATE INDEX idx_paquetes_prioridad ON shipping_paquetes(prioridad);

CREATE TRIGGER update_paquetes_updated_at BEFORE UPDATE ON shipping_paquetes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: cargas
CREATE TABLE shipping_cargas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID REFERENCES operations_viajes(id),
    codigo VARCHAR(50) UNIQUE NOT NULL,
    descripcion TEXT,
    peso_total DECIMAL(10, 2),
    volumen_total DECIMAL(10, 2),
    cantidad_paquetes INTEGER DEFAULT 0,
    estado VARCHAR(30) DEFAULT 'creada' CHECK (estado IN (
        'creada', 'cargando', 'completa', 'en_transito', 'descargada', 'cancelada'
    )),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_cargas_empresa ON shipping_cargas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_cargas_viaje ON shipping_cargas(viaje_id);
CREATE INDEX idx_cargas_codigo ON shipping_cargas(codigo);
CREATE INDEX idx_cargas_estado ON shipping_cargas(estado);

CREATE TRIGGER update_cargas_updated_at BEFORE UPDATE ON shipping_cargas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: paquetes_cargas (relación muchos a muchos)
CREATE TABLE shipping_paquetes_cargas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
    carga_id UUID NOT NULL REFERENCES shipping_cargas(id) ON DELETE CASCADE,
    orden_carga INTEGER,
    fecha_asignacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    CONSTRAINT unique_paquete_carga UNIQUE (paquete_id, carga_id)
);

CREATE INDEX idx_paquetes_cargas_paquete ON shipping_paquetes_cargas(paquete_id);
CREATE INDEX idx_paquetes_cargas_carga ON shipping_paquetes_cargas(carga_id);

CREATE TRIGGER update_paquetes_cargas_updated_at BEFORE UPDATE ON shipping_paquetes_cargas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: historial_estados
CREATE TABLE shipping_historial_estados (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
    estado_id UUID NOT NULL REFERENCES shipping_estados_envio(id),
    usuario_id UUID REFERENCES core_usuarios(id),
    comentario TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    fecha TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
) PARTITION BY RANGE (fecha);

-- Crear particiones mensuales (ejemplo para 2026)
CREATE TABLE shipping_historial_estados_2026_01 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE shipping_historial_estados_2026_02 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE shipping_historial_estados_2026_03 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE shipping_historial_estados_2026_04 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE shipping_historial_estados_2026_05 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE shipping_historial_estados_2026_06 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE shipping_historial_estados_2026_07 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE shipping_historial_estados_2026_08 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE shipping_historial_estados_2026_09 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE shipping_historial_estados_2026_10 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE shipping_historial_estados_2026_11 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE shipping_historial_estados_2026_12 PARTITION OF shipping_historial_estados
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX idx_historial_paquete ON shipping_historial_estados(paquete_id);
CREATE INDEX idx_historial_estado ON shipping_historial_estados(estado_id);
CREATE INDEX idx_historial_fecha ON shipping_historial_estados(fecha);
CREATE INDEX idx_historial_ubicacion ON shipping_historial_estados USING GIST(ubicacion);

-- ============================================================================
-- MÓDULO: TRACKING
-- ============================================================================

-- Tabla: tracking_gps (PARTICIONADA - tabla más grande)
CREATE TABLE tracking_gps (
    id UUID DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL,
    viaje_id UUID,
    vehiculo_id UUID,
    conductor_id UUID,
    dispositivo_id UUID,
    latitud DECIMAL(10, 8) NOT NULL,
    longitud DECIMAL(11, 8) NOT NULL,
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    precision_m DECIMAL(5, 2),
    altitud DECIMAL(8, 2),
    velocidad_kmh DECIMAL(6, 2),
    rumbo DECIMAL(5, 2),
    bateria INTEGER CHECK (bateria >= 0 AND bateria <= 100),
    internet BOOLEAN,
    gps BOOLEAN,
    satelites INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Particiones mensuales para tracking_gps (alto volumen)
CREATE TABLE tracking_gps_2026_01 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE tracking_gps_2026_02 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE tracking_gps_2026_03 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE tracking_gps_2026_04 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE tracking_gps_2026_05 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE tracking_gps_2026_06 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE tracking_gps_2026_07 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE tracking_gps_2026_08 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE tracking_gps_2026_09 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE tracking_gps_2026_10 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE tracking_gps_2026_11 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE tracking_gps_2026_12 PARTITION OF tracking_gps
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

-- Índices para tracking_gps
CREATE INDEX idx_gps_viaje ON tracking_gps(viaje_id);
CREATE INDEX idx_gps_vehiculo ON tracking_gps(vehiculo_id);
CREATE INDEX idx_gps_conductor ON tracking_gps(conductor_id);
CREATE INDEX idx_gps_empresa ON tracking_gps(empresa_id);
CREATE INDEX idx_gps_fecha ON tracking_gps(created_at);
CREATE INDEX idx_gps_ubicacion ON tracking_gps USING GIST(ubicacion);
CREATE INDEX idx_gps_vehiculo_fecha ON tracking_gps(vehiculo_id, created_at DESC);

-- Tabla: tracking_eventos (PARTICIONADA)
CREATE TABLE tracking_eventos (
    id UUID DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL,
    viaje_id UUID,
    vehiculo_id UUID,
    conductor_id UUID,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
        'inicio_viaje', 'fin_viaje', 'entrada_geocerca', 'salida_geocerca',
        'detenido', 'exceso_velocidad', 'frenada_brusca', 'aceleracion_brusca',
        'desvio_ruta', 'incidente', 'entrega', 'recogida', 'parada_no_programada'
    )),
    descripcion TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Particiones mensuales
CREATE TABLE tracking_eventos_2026_01 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE tracking_eventos_2026_02 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE tracking_eventos_2026_03 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE tracking_eventos_2026_04 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE tracking_eventos_2026_05 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE tracking_eventos_2026_06 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE tracking_eventos_2026_07 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE tracking_eventos_2026_08 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE tracking_eventos_2026_09 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE tracking_eventos_2026_10 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE tracking_eventos_2026_11 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE tracking_eventos_2026_12 PARTITION OF tracking_eventos
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX idx_eventos_viaje ON tracking_eventos(viaje_id);
CREATE INDEX idx_eventos_vehiculo ON tracking_eventos(vehiculo_id);
CREATE INDEX idx_eventos_tipo ON tracking_eventos(tipo);
CREATE INDEX idx_eventos_empresa ON tracking_eventos(empresa_id);
CREATE INDEX idx_eventos_fecha ON tracking_eventos(created_at);
CREATE INDEX idx_eventos_ubicacion ON tracking_eventos USING GIST(ubicacion);
CREATE INDEX idx_eventos_metadata ON tracking_eventos USING GIN(metadata);

-- Tabla: tracking_alertas
CREATE TABLE tracking_alertas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID REFERENCES operations_viajes(id),
    vehiculo_id UUID REFERENCES fleet_vehiculos(id),
    conductor_id UUID REFERENCES fleet_conductores(id),
    tipo VARCHAR(50) NOT NULL,
    nivel VARCHAR(20) NOT NULL CHECK (nivel IN ('info', 'warning', 'critical')),
    titulo VARCHAR(255) NOT NULL,
    mensaje TEXT,
    metadata JSONB,
    leido BOOLEAN DEFAULT FALSE,
    leido_por UUID REFERENCES core_usuarios(id),
    fecha_leido TIMESTAMP WITH TIME ZONE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_alertas_empresa ON tracking_alertas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_alertas_viaje ON tracking_alertas(viaje_id);
CREATE INDEX idx_alertas_nivel ON tracking_alertas(nivel);
CREATE INDEX idx_alertas_leido ON tracking_alertas(leido) WHERE leido = FALSE;
CREATE INDEX idx_alertas_fecha ON tracking_alertas(created_at DESC);

CREATE TRIGGER update_alertas_updated_at BEFORE UPDATE ON tracking_alertas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: tracking_sesiones
CREATE TABLE tracking_sesiones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID REFERENCES operations_viajes(id),
    vehiculo_id UUID REFERENCES fleet_vehiculos(id),
    conductor_id UUID REFERENCES fleet_conductores(id),
    dispositivo_id UUID REFERENCES fleet_dispositivos_gps(id),
    fecha_inicio TIMESTAMP WITH TIME ZONE NOT NULL,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    distancia_km DECIMAL(10, 2),
    puntos_gps INTEGER DEFAULT 0,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_sesiones_empresa ON tracking_sesiones(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_sesiones_viaje ON tracking_sesiones(viaje_id);
CREATE INDEX idx_sesiones_vehiculo ON tracking_sesiones(vehiculo_id);

CREATE TRIGGER update_sesiones_updated_at BEFORE UPDATE ON tracking_sesiones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: DELIVERY
-- ============================================================================

-- Tabla: firmas
CREATE TABLE delivery_firmas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    imagen_url TEXT NOT NULL,
    formato VARCHAR(10) DEFAULT 'png',
    tamano_bytes INTEGER,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_firmas_empresa ON delivery_firmas(empresa_id) WHERE deleted_at IS NULL;

CREATE TRIGGER update_firmas_updated_at BEFORE UPDATE ON delivery_firmas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: entregas
CREATE TABLE delivery_entregas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id),
    viaje_id UUID REFERENCES operations_viajes(id),
    receptor_nombre VARCHAR(255) NOT NULL,
    receptor_documento VARCHAR(20),
    receptor_relacion VARCHAR(50),
    firma_id UUID REFERENCES delivery_firmas(id),
    fecha TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    observacion TEXT,
    tipo_entrega VARCHAR(20) DEFAULT 'normal' CHECK (tipo_entrega IN (
        'normal', 'dejado_en_puerta', 'vecino', 'punto_acuerdo'
    )),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_entregas_empresa ON delivery_entregas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_entregas_paquete ON delivery_entregas(paquete_id);
CREATE INDEX idx_entregas_viaje ON delivery_entregas(viaje_id);
CREATE INDEX idx_entregas_fecha ON delivery_entregas(fecha);
CREATE INDEX idx_entregas_ubicacion ON delivery_entregas USING GIST(ubicacion);

CREATE TRIGGER update_entregas_updated_at BEFORE UPDATE ON delivery_entregas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: fotografias
CREATE TABLE delivery_fotografias (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    paquete_id UUID REFERENCES shipping_paquetes(id),
    entrega_id UUID REFERENCES delivery_entregas(id),
    incidencia_id UUID,
    url TEXT NOT NULL,
    tipo VARCHAR(50) CHECK (tipo IN (
        'entrega', 'incidencia', 'dano', 'paquete', 'documento', 'otra'
    )),
    descripcion TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    fecha TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_fotos_empresa ON delivery_fotografias(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_fotos_paquete ON delivery_fotografias(paquete_id);
CREATE INDEX idx_fotos_entrega ON delivery_fotografias(entrega_id);
CREATE INDEX idx_fotos_tipo ON delivery_fotografias(tipo);

CREATE TRIGGER update_fotos_updated_at BEFORE UPDATE ON delivery_fotografias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: incidencias
CREATE TABLE delivery_incidencias (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    paquete_id UUID REFERENCES shipping_paquetes(id),
    viaje_id UUID REFERENCES operations_viajes(id),
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
        'direccion_incorrecta', 'destinatario_ausente', 'rechazado',
        'dano_paquete', 'paquete_extraviado', 'retraso', 'acceso_restringido',
        'clima_adverso', 'averia_vehiculo', 'otra'
    )),
    descripcion TEXT NOT NULL,
    foto_url TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    estado VARCHAR(20) DEFAULT 'abierta' CHECK (estado IN (
        'abierta', 'en_proceso', 'resuelta', 'cerrada'
    )),
    resuelta_por UUID REFERENCES core_usuarios(id),
    fecha_resolucion TIMESTAMP WITH TIME ZONE,
    solucion TEXT,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_incidencias_empresa ON delivery_incidencias(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_incidencias_paquete ON delivery_incidencias(paquete_id);
CREATE INDEX idx_incidencias_viaje ON delivery_incidencias(viaje_id);
CREATE INDEX idx_incidencias_tipo ON delivery_incidencias(tipo);
CREATE INDEX idx_incidencias_estado ON delivery_incidencias(estado);
CREATE INDEX idx_incidencias_ubicacion ON delivery_incidencias USING GIST(ubicacion);

CREATE TRIGGER update_incidencias_updated_at BEFORE UPDATE ON delivery_incidencias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: COMMUNICATION
-- ============================================================================

-- Tabla: chats
CREATE TABLE communication_chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID REFERENCES operations_viajes(id),
    paquete_id UUID REFERENCES shipping_paquetes(id),
    tipo VARCHAR(20) DEFAULT 'viaje' CHECK (tipo IN ('viaje', 'paquete', 'soporte', 'grupo')),
    nombre VARCHAR(255),
    activo BOOLEAN DEFAULT TRUE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_chats_empresa ON communication_chats(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_chats_viaje ON communication_chats(viaje_id);
CREATE INDEX idx_chats_paquete ON communication_chats(paquete_id);

CREATE TRIGGER update_chats_updated_at BEFORE UPDATE ON communication_chats
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: chat_mensajes
CREATE TABLE communication_chat_mensajes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES communication_chats(id) ON DELETE CASCADE,
    usuario_id UUID REFERENCES core_usuarios(id),
    mensaje TEXT,
    tipo VARCHAR(20) DEFAULT 'texto' CHECK (tipo IN ('texto', 'imagen', 'audio', 'video', 'archivo', 'ubicacion')),
    archivo_url TEXT,
    archivo_nombre VARCHAR(255),
    archivo_tamano INTEGER,
    leido BOOLEAN DEFAULT FALSE,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_mensajes_chat ON communication_chat_mensajes(chat_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_mensajes_usuario ON communication_chat_mensajes(usuario_id);
CREATE INDEX idx_mensajes_fecha ON communication_chat_mensajes(created_at DESC);
CREATE INDEX idx_mensajes_leido ON communication_chat_mensajes(leido) WHERE leido = FALSE;

CREATE TRIGGER update_mensajes_updated_at BEFORE UPDATE ON communication_chat_mensajes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: notificaciones
CREATE TABLE communication_notificaciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    usuario_id UUID NOT NULL REFERENCES core_usuarios(id) ON DELETE CASCADE,
    titulo VARCHAR(255) NOT NULL,
    mensaje TEXT NOT NULL,
    tipo VARCHAR(50) CHECK (tipo IN (
        'info', 'success', 'warning', 'error', 'tracking', 'entrega', 'incidencia', 'sistema'
    )),
    referencia_tipo VARCHAR(50),
    referencia_id UUID,
    leido BOOLEAN DEFAULT FALSE,
    fecha_leido TIMESTAMP WITH TIME ZONE,
    datos_adicionales JSONB,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_notificaciones_empresa ON communication_notificaciones(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notificaciones_usuario ON communication_notificaciones(usuario_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notificaciones_leido ON communication_notificaciones(leido) WHERE leido = FALSE;
CREATE INDEX idx_notificaciones_fecha ON communication_notificaciones(created_at DESC);
CREATE INDEX idx_notificaciones_tipo ON communication_notificaciones(tipo);
CREATE INDEX idx_notificaciones_datos ON communication_notificaciones USING GIN(datos_adicionales);

CREATE TRIGGER update_notificaciones_updated_at BEFORE UPDATE ON communication_notificaciones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MÓDULO: AUDIT
-- ============================================================================

-- Tabla: auditoria (PARTICIONADA)
CREATE TABLE audit_auditoria (
    id UUID DEFAULT uuid_generate_v4(),
    empresa_id UUID,
    usuario_id UUID,
    usuario_nombre VARCHAR(255),
    accion VARCHAR(50) NOT NULL CHECK (accion IN (
        'INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'LOGOUT', 'EXPORT', 'IMPORT'
    )),
    tabla_afectada VARCHAR(100) NOT NULL,
    registro_id UUID,
    datos_antes JSONB,
    datos_despues JSONB,
    ip_address INET,
    user_agent TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Particiones mensuales
CREATE TABLE audit_auditoria_2026_01 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_auditoria_2026_02 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_auditoria_2026_03 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE audit_auditoria_2026_04 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE audit_auditoria_2026_05 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE audit_auditoria_2026_06 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit_auditoria_2026_07 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE audit_auditoria_2026_08 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit_auditoria_2026_09 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit_auditoria_2026_10 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit_auditoria_2026_11 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE audit_auditoria_2026_12 PARTITION OF audit_auditoria
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX idx_auditoria_empresa ON audit_auditoria(empresa_id);
CREATE INDEX idx_auditoria_usuario ON audit_auditoria(usuario_id);
CREATE INDEX idx_auditoria_tabla ON audit_auditoria(tabla_afectada);
CREATE INDEX idx_auditoria_accion ON audit_auditoria(accion);
CREATE INDEX idx_auditoria_fecha ON audit_auditoria(created_at DESC);
CREATE INDEX idx_auditoria_antes ON audit_auditoria USING GIN(datos_antes);
CREATE INDEX idx_auditoria_despues ON audit_auditoria USING GIN(datos_despues);

-- ============================================================================
-- MÓDULO: STORAGE
-- ============================================================================

-- Tabla: documentos
CREATE TABLE storage_documentos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    bucket VARCHAR(100) NOT NULL,
    ruta_archivo TEXT NOT NULL,
    url_publica TEXT,
    nombre_original VARCHAR(255),
    mime_type VARCHAR(100),
    tamano_bytes BIGINT,
    referencia_tipo VARCHAR(50),
    referencia_id UUID,
    metadata JSONB,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_documentos_empresa ON storage_documentos(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_documentos_bucket ON storage_documentos(bucket);
CREATE INDEX idx_documentos_referencia ON storage_documentos(referencia_tipo, referencia_id);
CREATE INDEX idx_documentos_metadata ON storage_documentos USING GIN(metadata);

CREATE TRIGGER update_documentos_updated_at BEFORE UPDATE ON storage_documentos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VISTAS ÚTILES
-- ============================================================================

-- Vista: paquetes con toda la información
CREATE VIEW v_paquetes_completo AS
SELECT 
    p.*,
    c.nombre AS cliente_nombre,
    e.nombre AS estado_nombre,
    e.color AS estado_color,
    r.nombre AS remitente_nombre,
    d.nombre AS destinatario_nombre
FROM shipping_paquetes p
LEFT JOIN customers_clientes c ON p.cliente_id = c.id
LEFT JOIN shipping_estados_envio e ON p.estado_actual = e.id
LEFT JOIN customers_remitentes r ON p.remitente_id = r.id
LEFT JOIN customers_destinatarios d ON p.destinatario_id = d.id
WHERE p.deleted_at IS NULL;

-- Vista: viajes activos con información del conductor y vehículo
CREATE VIEW v_viajes_activos AS
SELECT 
    v.*,
    cond.nombre || ' ' || cond.apellido AS conductor_nombre,
    cond.telefono AS conductor_telefono,
    veh.matricula,
    veh.marca || ' ' || veh.modelo AS vehiculo_descripcion,
    r.nombre AS ruta_nombre
FROM operations_viajes v
LEFT JOIN fleet_conductores fc ON v.conductor_id = fc.id
LEFT JOIN core_usuarios cond ON fc.usuario_id = cond.id
LEFT JOIN fleet_vehiculos veh ON v.vehiculo_id = veh.id
LEFT JOIN operations_rutas r ON v.ruta_id = r.id
WHERE v.deleted_at IS NULL
    AND v.estado IN ('programado', 'en_curso');

-- Vista: última posición GPS de cada vehículo
CREATE VIEW v_ultima_posicion_gps AS
SELECT DISTINCT ON (vehiculo_id)
    vehiculo_id,
    latitud,
    longitud,
    velocidad_kmh,
    created_at
FROM tracking_gps
WHERE deleted_at IS NULL
ORDER BY vehiculo_id, created_at DESC;

-- ============================================================================
-- FUNCIONES AUXILIARES
-- ============================================================================

-- Función: generar tracking number único
CREATE OR REPLACE FUNCTION generar_tracking_number()
RETURNS TEXT AS $$
DECLARE
    nuevo_tracking TEXT;
    existe BOOLEAN;
BEGIN
    LOOP
        nuevo_tracking := 'TRK' || TO_CHAR(NOW(), 'YYYYMMDD') || 
                         LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
        
        SELECT EXISTS(
            SELECT 1 FROM shipping_paquetes WHERE tracking_number = nuevo_tracking
        ) INTO existe;
        
        EXIT WHEN NOT existe;
    END LOOP;
    
    RETURN nuevo_tracking;
END;
$$ LANGUAGE plpgsql;

-- Función: calcular distancia entre dos puntos geográficos
CREATE OR REPLACE FUNCTION calcular_distancia_km(
    lat1 DECIMAL, lon1 DECIMAL,
    lat2 DECIMAL, lon2 DECIMAL
) RETURNS DECIMAL AS $$
BEGIN
    RETURN ST_Distance(
        ST_MakePoint(lon1, lat1)::GEOGRAPHY,
        ST_MakePoint(lon2, lat2)::GEOGRAPHY
    ) / 1000;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS PARA AUDITORÍA AUTOMÁTICA
-- ============================================================================

-- Función genérica de auditoría
CREATE OR REPLACE FUNCTION fn_auditoria_general()
RETURNS TRIGGER AS $$
DECLARE
    accion VARCHAR(50);
    datos_ant JSONB;
    datos_nuevos JSONB;
    registro UUID;
BEGIN
    IF TG_OP = 'INSERT' THEN
        accion := 'INSERT';
        datos_ant := NULL;
        datos_nuevos := to_jsonb(NEW);
        registro := NEW.id;
    ELSIF TG_OP = 'UPDATE' THEN
        accion := 'UPDATE';
        datos_ant := to_jsonb(OLD);
        datos_nuevos := to_jsonb(NEW);
        registro := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        accion := 'DELETE';
        datos_ant := to_jsonb(OLD);
        datos_nuevos := NULL;
        registro := OLD.id;
    END IF;
    
    INSERT INTO audit_auditoria (
        empresa_id,
        usuario_id,
        accion,
        tabla_afectada,
        registro_id,
        datos_antes,
        datos_despues
    ) VALUES (
        COALESCE(NEW.empresa_id, OLD.empresa_id),
        COALESCE(NEW.created_by, NEW.updated_by, OLD.updated_by),
        accion,
        TG_TABLE_NAME,
        registro,
        datos_ant,
        datos_nuevos
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger a tablas principales (ejemplos)
CREATE TRIGGER trg_auditoria_paquetes
    AFTER INSERT OR UPDATE OR DELETE ON shipping_paquetes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_viajes
    AFTER INSERT OR UPDATE OR DELETE ON operations_viajes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_entregas
    AFTER INSERT OR UPDATE OR DELETE ON delivery_entregas
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

-- ============================================================================
-- COMENTARIOS DOCUMENTALES
-- ============================================================================

COMMENT ON TABLE core_empresas IS 'Tabla maestra de empresas (multi-tenant)';
COMMENT ON TABLE shipping_paquetes IS 'Tabla principal de paquetes - corazón del sistema';
COMMENT ON TABLE tracking_gps IS 'Tabla particionada de tracking GPS - alto volumen';
COMMENT ON TABLE operations_viajes IS 'Tabla principal de operaciones de transporte';
COMMENT ON TABLE audit_auditoria IS 'Tabla particionada de auditoría del sistema';

COMMENT ON COLUMN shipping_paquetes.tracking_number IS 'Código único de seguimiento visible al cliente';
COMMENT ON COLUMN tracking_gps.ubicacion IS 'Punto geográfico calculado automáticamente desde lat/lon';
COMMENT ON COLUMN operations_geocercas.poligono IS 'Geometría PostGIS para geocercas poligonales';

-- ============================================================================
-- POLÍTICAS RLS (EJEMPLO BÁSICO)
-- ============================================================================

-- Habilitar RLS en tablas principales
ALTER TABLE core_empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipping_paquetes ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_viajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_gps ENABLE ROW LEVEL SECURITY;

-- Política ejemplo: usuarios solo ven datos de su empresa
CREATE POLICY "Usuarios ven solo su empresa" ON core_empresas
    FOR ALL
    USING (id IN (
        SELECT empresa_id FROM core_usuarios 
        WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
    ));

CREATE POLICY "Paquetes de la empresa" ON shipping_paquetes
    FOR ALL
    USING (empresa_id IN (
        SELECT empresa_id FROM core_usuarios 
        WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
    ));

-- Nota: Crear políticas específicas para cada tabla según roles y permisos