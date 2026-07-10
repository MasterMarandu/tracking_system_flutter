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

-- Tabla: checklists (pre-viaje / post-viaje)
CREATE TABLE fleet_checklists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID,
    vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
    conductor_id UUID REFERENCES fleet_conductores(id),
    tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('pre_viaje', 'post_viaje', 'mantenimiento')),
    estado VARCHAR(20) DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'en_proceso', 'completado', 'con_observaciones')),
    fecha_inicio TIMESTAMP WITH TIME ZONE,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    observaciones TEXT,
    kilometraje INTEGER,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_checklists_empresa ON fleet_checklists(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_checklists_viaje ON fleet_checklists(viaje_id);
CREATE INDEX idx_checklists_vehiculo ON fleet_checklists(vehiculo_id);
CREATE INDEX idx_checklists_estado ON fleet_checklists(estado);

CREATE TRIGGER update_checklists_updated_at BEFORE UPDATE ON fleet_checklists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: checklists_items (items del checklist)
CREATE TABLE fleet_checklists_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    checklist_id UUID NOT NULL REFERENCES fleet_checklists(id) ON DELETE CASCADE,
    nombre VARCHAR(255) NOT NULL,
    categoria VARCHAR(100),
    orden INTEGER DEFAULT 0,
    estado VARCHAR(20) DEFAULT 'ok' CHECK (estado IN ('ok', 'observacion', 'fallo')),
    observacion TEXT,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_checklist_items_checklist ON fleet_checklists_items(checklist_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_checklist_items_estado ON fleet_checklists_items(estado);

CREATE TRIGGER update_checklist_items_updated_at BEFORE UPDATE ON fleet_checklists_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: plantillas de checklist (items predefinidos por tipo)
CREATE TABLE fleet_checklists_plantillas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
    tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('pre_viaje', 'post_viaje', 'mantenimiento')),
    nombre VARCHAR(255) NOT NULL,
    categoria VARCHAR(100),
    orden INTEGER DEFAULT 0,
    es_sistema BOOLEAN DEFAULT FALSE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_plantillas_empresa_tipo ON fleet_checklists_plantillas(empresa_id, tipo) WHERE deleted_at IS NULL;

CREATE TRIGGER update_plantillas_updated_at BEFORE UPDATE ON fleet_checklists_plantillas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Seed: plantillas predefinidas por tipo (empresa_id NULL = global, es_sistema = TRUE)
INSERT INTO fleet_checklists_plantillas (empresa_id, tipo, nombre, categoria, orden, es_sistema) VALUES
-- Pre-Viaje
(NULL, 'pre_viaje', 'Luces', 'Carrocería', 1, TRUE),
(NULL, 'pre_viaje', 'Frenos', 'Carrocería', 2, TRUE),
(NULL, 'pre_viaje', 'Espejos', 'Carrocería', 3, TRUE),
(NULL, 'pre_viaje', 'Documentación', 'Documentos', 4, TRUE),
(NULL, 'pre_viaje', 'Licencia de conducir', 'Documentos', 5, TRUE),
(NULL, 'pre_viaje', 'Seguro del vehículo', 'Documentos', 6, TRUE),
(NULL, 'pre_viaje', 'Fotos del vehículo', 'Evidencia', 7, TRUE),
(NULL, 'pre_viaje', 'Carga asegurada', 'Carga', 8, TRUE),
(NULL, 'pre_viaje', 'Sellos verificados', 'Carga', 9, TRUE),
(NULL, 'pre_viaje', 'Temperatura de carga', 'Carga', 10, TRUE),
(NULL, 'pre_viaje', 'Neumáticos', 'Carrocería', 11, TRUE),
(NULL, 'pre_viaje', 'Kilometraje actual', 'Carrocería', 12, TRUE),
-- Post-Viaje
(NULL, 'post_viaje', 'Kilometraje final', 'Carrocería', 1, TRUE),
(NULL, 'post_viaje', 'Estado de neumáticos', 'Carrocería', 2, TRUE),
(NULL, 'post_viaje', 'Combustible restante', 'Carrocería', 3, TRUE),
(NULL, 'post_viaje', 'Daños en carrocería', 'Carrocería', 4, TRUE),
(NULL, 'post_viaje', 'Carga entregada completa', 'Carga', 5, TRUE),
(NULL, 'post_viaje', 'Sellos retirados', 'Carga', 6, TRUE),
(NULL, 'post_viaje', 'Documentos de entrega', 'Documentos', 7, TRUE),
(NULL, 'post_viaje', 'Fotos de entrega', 'Evidencia', 8, TRUE),
-- Mantenimiento
(NULL, 'mantenimiento', 'Aceite y filtros', 'Motor', 1, TRUE),
(NULL, 'mantenimiento', 'Frenos', 'Frenos', 2, TRUE),
(NULL, 'mantenimiento', 'Neumáticos', 'Neumáticos', 3, TRUE),
(NULL, 'mantenimiento', 'Luces', 'Luces', 4, TRUE),
(NULL, 'mantenimiento', 'Suspensión', 'Motor', 5, TRUE),
(NULL, 'mantenimiento', 'Transmisión', 'Motor', 6, TRUE),
(NULL, 'mantenimiento', 'Refrigeración', 'Motor', 7, TRUE),
(NULL, 'mantenimiento', 'Fugas de líquidos', 'Motor', 8, TRUE),
(NULL, 'mantenimiento', 'Estado de batería', 'Seguridad', 9, TRUE),
(NULL, 'mantenimiento', 'Documentación al día', 'Documentos', 10, TRUE);

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

-- Tabla: geocercas_vinculos (vincular geocercas a clientes, direcciones, sucursales)
CREATE TABLE operations_geocercas_vinculos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    geocerca_id UUID NOT NULL REFERENCES operations_geocercas(id) ON DELETE CASCADE,
    referencia_tipo VARCHAR(50) NOT NULL CHECK (referencia_tipo IN (
        'cliente', 'direccion', 'sucursal', 'otra'
    )),
    referencia_id UUID NOT NULL,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    CONSTRAINT unique_geocerca_vinculo UNIQUE (geocerca_id, referencia_tipo, referencia_id)
);

CREATE INDEX idx_geocercas_vinc_geocerca ON operations_geocercas_vinculos(geocerca_id);
CREATE INDEX idx_geocercas_vinc_referencia ON operations_geocercas_vinculos(referencia_tipo, referencia_id);

CREATE TRIGGER update_geocercas_vinculos_updated_at BEFORE UPDATE ON operations_geocercas_vinculos
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

-- Tabla: rutas_optimizadas (guardar ruta calculada por proveedor de mapas)
CREATE TABLE operations_rutas_optimizadas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    ruta_id UUID NOT NULL REFERENCES operations_rutas(id) ON DELETE CASCADE,
    proveedor VARCHAR(50) NOT NULL CHECK (proveedor IN ('google', 'osrm', 'mapbox', 'here', 'otro')),
    distancia_km DECIMAL(10, 2),
    tiempo_estimado_min INTEGER,
    polyline TEXT,
    waypoints JSONB,
    algoritmo VARCHAR(50),
    fecha_calculo TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    es_activa BOOLEAN DEFAULT TRUE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_rutas_opt_empresa ON operations_rutas_optimizadas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_opt_ruta ON operations_rutas_optimizadas(ruta_id);
CREATE INDEX idx_rutas_opt_activa ON operations_rutas_optimizadas(es_activa) WHERE es_activa = TRUE AND deleted_at IS NULL;

CREATE TRIGGER update_rutas_optimizadas_updated_at BEFORE UPDATE ON operations_rutas_optimizadas
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

-- Tabla: ETA (estimacion de llegada por parada)
CREATE TABLE operations_eta (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID NOT NULL,
    parada_id UUID NOT NULL REFERENCES operations_paradas(id) ON DELETE CASCADE,
    eta_original TIMESTAMP WITH TIME ZONE,
    eta_actual TIMESTAMP WITH TIME ZONE,
    retraso_min INTEGER DEFAULT 0,
    distancia_restante_km DECIMAL(10, 2),
    ultima_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_eta_empresa ON operations_eta(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_eta_viaje ON operations_eta(viaje_id);
CREATE INDEX idx_eta_parada ON operations_eta(parada_id);

CREATE TRIGGER update_eta_updated_at BEFORE UPDATE ON operations_eta
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: viajes
CREATE TABLE operations_viajes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    codigo VARCHAR(50) UNIQUE NOT NULL,
    ruta_id UUID REFERENCES operations_rutas(id),
    fecha_inicio TIMESTAMP WITH TIME ZONE,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    hora_programada_salida TIMESTAMP WITH TIME ZONE,
    hora_real_salida TIMESTAMP WITH TIME ZONE,
    hora_programada_llegada TIMESTAMP WITH TIME ZONE,
    hora_real_llegada TIMESTAMP WITH TIME ZONE,
    estado VARCHAR(30) DEFAULT 'programado' CHECK (estado IN (
        'programado', 'en_curso', 'pausado', 'completado', 'cancelado'
    )),
    km_estimados DECIMAL(10, 2),
    km_reales DECIMAL(10, 2),
    distancia_real_km DECIMAL(10, 2),
    tiempo_estimado_min INTEGER,
    tiempo_real_min INTEGER,
    tiempo_detenido_seg INTEGER DEFAULT 0,
    tiempo_movimiento_seg INTEGER DEFAULT 0,
    combustible_litros DECIMAL(10, 2),
    consumo_combustible DECIMAL(10, 2),
    peajes DECIMAL(12, 2),
    costo_total DECIMAL(12, 2),
    observaciones TEXT,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_viajes_empresa ON operations_viajes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_codigo ON operations_viajes(codigo);
CREATE INDEX idx_viajes_estado ON operations_viajes(estado);
CREATE INDEX idx_viajes_fecha ON operations_viajes(fecha_inicio);

CREATE TRIGGER update_viajes_updated_at BEFORE UPDATE ON operations_viajes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Foreign keys agregadas después de crear operations_viajes (resuelve dependencias circulares)
ALTER TABLE fleet_checklists
    ADD CONSTRAINT fk_checklists_viaje FOREIGN KEY (viaje_id) REFERENCES operations_viajes(id);

ALTER TABLE operations_eta
    ADD CONSTRAINT fk_eta_viaje FOREIGN KEY (viaje_id) REFERENCES operations_viajes(id) ON DELETE CASCADE;

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

-- Tabla: viajes_conductores (puente viaje - conductor, soporta relevos)
CREATE TABLE operations_viajes_conductores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    conductor_id UUID NOT NULL REFERENCES fleet_conductores(id),
    principal BOOLEAN DEFAULT TRUE,
    estado VARCHAR(20) DEFAULT 'asignado' CHECK (estado IN (
        'asignado', 'aceptado', 'en Curso', 'completado', 'rechazado', 'cancelado'
    )),
    fecha_asignacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    fecha_aceptacion TIMESTAMP WITH TIME ZONE,
    fecha_inicio TIMESTAMP WITH TIME ZONE,
    fecha_fin TIMESTAMP WITH TIME ZONE,
    observaciones TEXT,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_viajes_conductores_viaje ON operations_viajes_conductores(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_conductores_conductor ON operations_viajes_conductores(conductor_id);
CREATE INDEX idx_viajes_conductores_estado ON operations_viajes_conductores(estado);

CREATE TRIGGER update_viajes_conductores_updated_at BEFORE UPDATE ON operations_viajes_conductores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: viajes_vehiculos (puente viaje - vehiculo, soporta camion + remolque)
CREATE TABLE operations_viajes_vehiculos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
    tipo VARCHAR(30) DEFAULT 'principal' CHECK (tipo IN ('principal', 'remolque', 'semirremolque', 'acoplado')),
    principal BOOLEAN DEFAULT TRUE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_viajes_vehiculos_viaje ON operations_viajes_vehiculos(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_vehiculos_vehiculo ON operations_viajes_vehiculos(vehiculo_id);

CREATE TRIGGER update_viajes_vehiculos_updated_at BEFORE UPDATE ON operations_viajes_vehiculos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: viajes_paquetes (puente viaje - paquete, soporta cambio de viaje)
CREATE TABLE operations_viajes_paquetes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    paquete_id UUID NOT NULL,
    parada_id UUID REFERENCES operations_paradas(id),
    orden_entrega INTEGER,
    estado VARCHAR(30) DEFAULT 'asignado' CHECK (estado IN (
        'asignado', 'cargado', 'en_transito', 'descargado', 'entregado', 'reasignado'
    )),
    hora_asignacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    hora_carga TIMESTAMP WITH TIME ZONE,
    hora_descarga TIMESTAMP WITH TIME ZONE,
    hora_entrega TIMESTAMP WITH TIME ZONE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

-- Un paquete solo puede estar asignado activamente a UN viaje
CREATE UNIQUE INDEX uq_viaje_paquete_activo
    ON operations_viajes_paquetes(viaje_id, paquete_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_viajes_paquetes_viaje ON operations_viajes_paquetes(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_paquetes_paquete ON operations_viajes_paquetes(paquete_id);
CREATE INDEX idx_viajes_paquetes_parada ON operations_viajes_paquetes(parada_id);
CREATE INDEX idx_viajes_paquetes_estado ON operations_viajes_paquetes(estado);

CREATE TRIGGER update_viajes_paquetes_updated_at BEFORE UPDATE ON operations_viajes_paquetes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: viajes_eventos (eventos operativos del viaje)
CREATE TABLE operations_viajes_eventos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
        'viaje_aceptado', 'checklist_completado', 'carga_iniciada', 'carga_finalizada',
        'viaje_iniciado', 'viaje_pausado', 'viaje_reanudado', 'parada_programada',
        'parada_no_programada', 'incidente', 'viaje_cerrado'
    )),
    usuario_id UUID REFERENCES core_usuarios(id),
    descripcion TEXT,
    metadata JSONB,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_viajes_eventos_viaje ON operations_viajes_eventos(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_eventos_tipo ON operations_viajes_eventos(tipo);
CREATE INDEX idx_viajes_eventos_fecha ON operations_viajes_eventos(created_at DESC);

CREATE TRIGGER update_viajes_eventos_updated_at BEFORE UPDATE ON operations_viajes_eventos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: asignaciones (registro de quién asignó el viaje)
CREATE TABLE operations_asignaciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
    usuario_id UUID NOT NULL REFERENCES core_usuarios(id),
    tipo VARCHAR(30) NOT NULL CHECK (tipo IN (
        'viaje', 'conductor', 'vehiculo', 'paquete', 'reasignacion'
    )),
    referencia_tipo VARCHAR(50),
    referencia_id UUID,
    observacion TEXT,
    metadata JSONB,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_asignaciones_empresa ON operations_asignaciones(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_asignaciones_viaje ON operations_asignaciones(viaje_id);
CREATE INDEX idx_asignaciones_usuario ON operations_asignaciones(usuario_id);
CREATE INDEX idx_asignaciones_tipo ON operations_asignaciones(tipo);
CREATE INDEX idx_asignaciones_fecha ON operations_asignaciones(created_at DESC);

CREATE TRIGGER update_asignaciones_updated_at BEFORE UPDATE ON operations_asignaciones
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

-- Catalogo: tipos_paquete
CREATE TABLE shipping_tipos_paquete (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
    codigo VARCHAR(50) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    es_sistema BOOLEAN DEFAULT FALSE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    CONSTRAINT unique_tipo_paquete_empresa UNIQUE (empresa_id, codigo)
);

CREATE INDEX idx_tipos_paquete_empresa ON shipping_tipos_paquete(empresa_id) WHERE deleted_at IS NULL;

-- Tipos del sistema (empresa_id = NULL)
INSERT INTO shipping_tipos_paquete (codigo, nombre, es_sistema) VALUES
    ('paquete', 'Paquete', true),
    ('sobre', 'Sobre', true),
    ('carga', 'Carga', true),
    ('documento', 'Documento', true),
    ('pallet', 'Pallet', true),
    ('contenedor', 'Contenedor', true);

CREATE TRIGGER update_tipos_paquete_updated_at BEFORE UPDATE ON shipping_tipos_paquete
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: envios (movimiento fisico de mercancia)
CREATE TABLE shipping_envios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    cliente_id UUID NOT NULL REFERENCES customers_clientes(id),
    codigo VARCHAR(50) NOT NULL,
    referencia_cliente VARCHAR(100),
    origen_id UUID REFERENCES customers_direcciones(id),
    destino_id UUID REFERENCES customers_direcciones(id),
    remitente_id UUID REFERENCES customers_remitentes(id),
    destinatario_id UUID REFERENCES customers_destinatarios(id),
    estado VARCHAR(30) DEFAULT 'creado' CHECK (estado IN (
        'creado', 'preparando', 'despachado', 'en_ruta', 'entregado', 'cancelado'
    )),
    fecha_programada TIMESTAMP WITH TIME ZONE,
    fecha_despacho TIMESTAMP WITH TIME ZONE,
    fecha_entrega TIMESTAMP WITH TIME ZONE,
    observaciones TEXT,
    valor_total DECIMAL(12, 2),
    costo_total DECIMAL(12, 2),
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_envios_empresa ON shipping_envios(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_envios_cliente ON shipping_envios(cliente_id);
CREATE INDEX idx_envios_codigo ON shipping_envios(codigo);
CREATE INDEX idx_envios_estado ON shipping_envios(estado);
CREATE INDEX idx_envios_origen ON shipping_envios(origen_id);
CREATE INDEX idx_envios_destino ON shipping_envios(destino_id);

CREATE TRIGGER update_envios_updated_at BEFORE UPDATE ON shipping_envios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: paquetes
CREATE TABLE shipping_paquetes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    envio_id UUID REFERENCES shipping_envios(id),
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
    
    -- Informacion comercial
    valor_declarado DECIMAL(12, 2),
    costo_envio DECIMAL(12, 2),
    tipo VARCHAR(50) DEFAULT 'paquete',
    tipo_id UUID REFERENCES shipping_tipos_paquete(id),
    prioridad VARCHAR(20) DEFAULT 'normal' CHECK (prioridad IN ('baja', 'normal', 'alta', 'urgente')),
    contenido TEXT,
    
    -- Atributos logisticos
    fragil BOOLEAN DEFAULT FALSE,
    apilable BOOLEAN DEFAULT TRUE,
    requiere_refrigeracion BOOLEAN DEFAULT FALSE,
    temperatura_min DECIMAL(5, 2),
    temperatura_max DECIMAL(5, 2),
    mercancia_peligrosa BOOLEAN DEFAULT FALSE,
    imo_class VARCHAR(20),
    un_number VARCHAR(30),
    numero_sello VARCHAR(50),
    requiere_firma BOOLEAN DEFAULT TRUE,
    requiere_otp BOOLEAN DEFAULT FALSE,
    requiere_documento BOOLEAN DEFAULT FALSE,
    custodia BOOLEAN DEFAULT FALSE,
    codigo_cliente VARCHAR(100),
    
    -- Estado y fechas
    estado_actual UUID REFERENCES shipping_estados_envio(id),
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    fecha_entrega_estimada TIMESTAMP WITH TIME ZONE,
    fecha_entrega_real TIMESTAMP WITH TIME ZONE,
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_paquetes_empresa ON shipping_paquetes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_paquetes_envio ON shipping_paquetes(envio_id);
CREATE INDEX idx_paquetes_tracking ON shipping_paquetes(tracking_number);
CREATE INDEX idx_paquetes_qr ON shipping_paquetes(codigo_qr);
CREATE INDEX idx_paquetes_barras ON shipping_paquetes(codigo_barras);
CREATE INDEX idx_paquetes_cliente ON shipping_paquetes(cliente_id);
CREATE INDEX idx_paquetes_estado ON shipping_paquetes(estado_actual);
CREATE INDEX idx_paquetes_fecha ON shipping_paquetes(fecha_creacion);
CREATE INDEX idx_paquetes_prioridad ON shipping_paquetes(prioridad);

CREATE TRIGGER update_paquetes_updated_at BEFORE UPDATE ON shipping_paquetes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Foreign key agregada después de crear shipping_paquetes (resuelve dependencia circular)
ALTER TABLE operations_viajes_paquetes
    ADD CONSTRAINT fk_viajes_paquetes_paquete FOREIGN KEY (paquete_id) REFERENCES shipping_paquetes(id) ON DELETE CASCADE;

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

-- Tabla: evidencias de carga (fotos de camion cargado, pallets, sellos, documentos)
CREATE TABLE shipping_carga_evidencias (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    carga_id UUID NOT NULL REFERENCES shipping_cargas(id) ON DELETE CASCADE,
    viaje_id UUID REFERENCES operations_viajes(id),
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
        'camion_cargado', 'pallet', 'sello', 'documento', 'photo_galga', 'otra'
    )),
    url TEXT NOT NULL,
    descripcion TEXT,
    numero_sello VARCHAR(50),
    usuario_id UUID REFERENCES core_usuarios(id),
    fecha TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Campos estandar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX idx_carga_evidencias_empresa ON shipping_carga_evidencias(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_carga_evidencias_carga ON shipping_carga_evidencias(carga_id);
CREATE INDEX idx_carga_evidencias_viaje ON shipping_carga_evidencias(viaje_id);
CREATE INDEX idx_carga_evidencias_tipo ON shipping_carga_evidencias(tipo);

CREATE TRIGGER update_carga_evidencias_updated_at BEFORE UPDATE ON shipping_carga_evidencias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Tabla: historial_estados
CREATE TABLE shipping_historial_estados (
    id UUID DEFAULT uuid_generate_v4(),
    paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
    estado_id UUID NOT NULL REFERENCES shipping_estados_envio(id),
    usuario_id UUID REFERENCES core_usuarios(id),
    comentario TEXT,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    ubicacion GEOGRAPHY(POINT, 4326),
    fecha TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    -- Campos estándar
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID,
    
    PRIMARY KEY (id, fecha)
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
CREATE INDEX idx_gps_tracking_empresa ON tracking_gps(empresa_id);
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

-- Deshabilitar RLS en audit_auditoria (es una tabla de logs del sistema, no necesita RLS)
ALTER TABLE audit_auditoria DISABLE ROW LEVEL SECURITY;

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
LEFT JOIN operations_viajes_conductores vjc ON v.id = vjc.viaje_id AND vjc.principal = TRUE AND vjc.deleted_at IS NULL
LEFT JOIN fleet_conductores fc ON vjc.conductor_id = fc.id
LEFT JOIN core_usuarios cond ON fc.usuario_id = cond.id
LEFT JOIN operations_viajes_vehiculos vjv ON v.id = vjv.viaje_id AND vjv.principal = TRUE AND vjv.deleted_at IS NULL
LEFT JOIN fleet_vehiculos veh ON vjv.vehiculo_id = veh.id
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
ALTER TABLE tracking_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_alertas ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_sesiones ENABLE ROW LEVEL SECURITY;

-- Política ELIMINADA - se reemplaza por políticas separadas más adelante

CREATE POLICY "Paquetes de la empresa" ON shipping_paquetes
    FOR ALL
    USING (empresa_id IN (
        SELECT empresa_id FROM core_usuarios 
        WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
    ));

-- Nota: Crear políticas específicas para cada tabla según roles y permisos

-- Habilitar RLS en customers_clientes (si no está ya habilitado)
ALTER TABLE customers_clientes ENABLE ROW LEVEL SECURITY;

-- Política: usuarios ven y gestionan solo los clientes de su empresa
CREATE POLICY "Clientes de la empresa" ON customers_clientes
    FOR ALL
    USING (empresa_id IN (
        SELECT empresa_id FROM core_usuarios 
        WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
    ))
    WITH CHECK (empresa_id IN (
        SELECT empresa_id FROM core_usuarios 
        WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
    ));

-- ============================================================================
-- POLÍTICAS RLS PARA REGISTRO
-- Permitir que usuarios autenticados creen su empresa y perfil
-- ============================================================================

-- Helper: función reutilizable para obtener empresa del usuario actual
CREATE OR REPLACE FUNCTION public.user_empresa_id()
RETURNS UUID AS $$
    SELECT empresa_id FROM core_usuarios
    WHERE auth_user_id = auth.uid() AND deleted_at IS NULL AND activo = TRUE
    LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: función reutilizable para verificar si usuario es admin
CREATE OR REPLACE FUNCTION public.user_is_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM core_usuarios u
        JOIN core_roles r ON u.rol_id = r.id
        WHERE u.auth_user_id = auth.uid()
          AND r.nombre = 'Administrador'
          AND u.deleted_at IS NULL
          AND u.activo = TRUE
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- core_empresas: políticas separadas para INSERT y SELECT/UPDATE/DELETE
-- Limpiar TODAS las políticas existentes primero
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN SELECT polname FROM pg_policy WHERE polrelid = 'core_empresas'::regclass LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(pol.polname) || ' ON core_empresas';
    END LOOP;
END $$;

-- INSERT: permitir crear empresa durante registro
CREATE POLICY "Empresas INSERT registro" ON core_empresas
    FOR INSERT
    WITH CHECK (true);

-- SELECT: solo ver empresas propias
CREATE POLICY "Empresas SELECT propia" ON core_empresas
    FOR SELECT
    USING (
        id = public.user_empresa_id()
    );

-- UPDATE: solo editar empresas propias
CREATE POLICY "Empresas UPDATE propia" ON core_empresas
    FOR UPDATE
    USING (
        id = public.user_empresa_id()
    )
    WITH CHECK (
        id = public.user_empresa_id()
    );

-- DELETE: solo eliminar empresas propias
CREATE POLICY "Empresas DELETE propia" ON core_empresas
    FOR DELETE
    USING (
        id = public.user_empresa_id()
    );

-- core_usuarios: políticas separadas para evitar recursión infinita
-- Limpiar TODAS las políticas existentes primero
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN SELECT polname FROM pg_policy WHERE polrelid = 'core_usuarios'::regclass LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(pol.polname) || ' ON core_usuarios';
    END LOOP;
END $$;

-- INSERT: permitir crear perfil propio (sin consultar la misma tabla)
CREATE POLICY "Usuarios INSERT propio perfil" ON core_usuarios
    FOR INSERT
    WITH CHECK (auth_user_id = auth.uid());

-- SELECT/UPDATE/DELETE: solo ver datos de su empresa
CREATE POLICY "Usuarios SELECT propia" ON core_usuarios
    FOR SELECT
    USING (
        empresa_id = public.user_empresa_id()
        OR auth_user_id = auth.uid()
    );

CREATE POLICY "Usuarios UPDATE propia" ON core_usuarios
    FOR UPDATE
    USING (
        empresa_id = public.user_empresa_id()
        OR auth_user_id = auth.uid()
    )
    WITH CHECK (
        empresa_id = public.user_empresa_id()
        OR auth_user_id = auth.uid()
    );

CREATE POLICY "Usuarios DELETE propia" ON core_usuarios
    FOR DELETE
    USING (
        empresa_id = public.user_empresa_id()
        OR auth_user_id = auth.uid()
    );

-- core_roles: lectura para todos los autenticados (catálogo de roles del sistema)
ALTER TABLE core_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Roles del sistema: lectura" ON core_roles;
CREATE POLICY "Roles del sistema: lectura" ON core_roles
    FOR SELECT USING (true);


-- ============================================================================
-- MEJORAS CRÍTICAS PARA PRODUCCIÓN
-- Ejecutar estas sentencias después del esquema base
-- ============================================================================

-- ============================================================================
-- 1. PARTICIONES DEFAULT (evita error al insertar fuera de rango)
-- ============================================================================

-- Partición default para tracking_gps
CREATE TABLE tracking_gps_default PARTITION OF tracking_gps DEFAULT;

-- Partición default para tracking_eventos
CREATE TABLE tracking_eventos_default PARTITION OF tracking_eventos DEFAULT;

-- Partición default para shipping_historial_estados
CREATE TABLE shipping_historial_estados_default PARTITION OF shipping_historial_estados DEFAULT;

-- Partición default para audit_auditoria
CREATE TABLE audit_auditoria_default PARTITION OF audit_auditoria DEFAULT;


-- ============================================================================
-- 2. TRIGGERS PARA CALCULAR ubicacion DESDE latitud/longitud
-- ============================================================================

-- Función genérica para calcular ubicación desde lat/lon
CREATE OR REPLACE FUNCTION fn_set_ubicacion_from_latlon()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.latitud IS NOT NULL AND NEW.longitud IS NOT NULL THEN
        NEW.ubicacion := ST_SetSRID(
            ST_MakePoint(NEW.longitud::double precision, NEW.latitud::double precision),
            4326
        )::geography;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar a todas las tablas con latitud/longitud/ubicacion
CREATE TRIGGER trg_set_sucursales_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON core_sucursales
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_direcciones_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON customers_direcciones
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_paradas_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_paradas
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_checkpoints_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_checkpoints
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_entregas_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON delivery_entregas
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_incidencias_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON delivery_incidencias
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_historial_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON shipping_historial_estados
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

CREATE TRIGGER trg_set_eventos_ubicacion
    BEFORE INSERT OR UPDATE OF latitud, longitud ON tracking_eventos
    FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();


-- ============================================================================
-- 3. VALIDACIONES DE LATITUD Y LONGITUD
-- ============================================================================

-- tracking_gps
ALTER TABLE tracking_gps
    ADD CONSTRAINT chk_gps_latitud CHECK (latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_gps_longitud CHECK (longitud BETWEEN -180 AND 180);

-- tracking_eventos
ALTER TABLE tracking_eventos
    ADD CONSTRAINT chk_eventos_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_eventos_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- operations_paradas
ALTER TABLE operations_paradas
    ADD CONSTRAINT chk_paradas_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_paradas_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- operations_checkpoints
ALTER TABLE operations_checkpoints
    ADD CONSTRAINT chk_checkpoints_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_checkpoints_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- delivery_entregas
ALTER TABLE delivery_entregas
    ADD CONSTRAINT chk_entregas_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_entregas_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- delivery_incidencias
ALTER TABLE delivery_incidencias
    ADD CONSTRAINT chk_incidencias_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_incidencias_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- core_sucursales
ALTER TABLE core_sucursales
    ADD CONSTRAINT chk_sucursales_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_sucursales_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- customers_direcciones
ALTER TABLE customers_direcciones
    ADD CONSTRAINT chk_direcciones_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_direcciones_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);

-- shipping_historial_estados
ALTER TABLE shipping_historial_estados
    ADD CONSTRAINT chk_historial_latitud CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
    ADD CONSTRAINT chk_historial_longitud CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180);


-- ============================================================================
-- 4. FUNCIÓN DE AUDITORÍA CORREGIDA (maneja DELETE correctamente)
-- ============================================================================

-- Eliminar trigger existente si lo hay
DROP TRIGGER IF EXISTS trg_auditoria_paquetes ON shipping_paquetes;
DROP TRIGGER IF EXISTS trg_auditoria_viajes ON operations_viajes;
DROP TRIGGER IF EXISTS trg_auditoria_entregas ON delivery_entregas;

-- Reemplazar la función de auditoría con una versión corregida
CREATE OR REPLACE FUNCTION fn_auditoria_general()
RETURNS TRIGGER AS $$
DECLARE
    v_empresa_id UUID;
    v_usuario_id UUID;
    v_registro_id UUID;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_empresa_id := NEW.empresa_id;
        v_usuario_id := NEW.created_by;
        v_registro_id := NEW.id;

        INSERT INTO audit_auditoria (
            empresa_id, usuario_id, accion, tabla_afectada,
            registro_id, datos_antes, datos_despues
        ) VALUES (
            v_empresa_id, v_usuario_id, 'INSERT', TG_TABLE_NAME,
            v_registro_id, NULL, to_jsonb(NEW)
        );

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        v_empresa_id := COALESCE(NEW.empresa_id, OLD.empresa_id);
        v_usuario_id := COALESCE(NEW.updated_by, OLD.updated_by);
        v_registro_id := NEW.id;

        INSERT INTO audit_auditoria (
            empresa_id, usuario_id, accion, tabla_afectada,
            registro_id, datos_antes, datos_despues
        ) VALUES (
            v_empresa_id, v_usuario_id, 'UPDATE', TG_TABLE_NAME,
            v_registro_id, to_jsonb(OLD), to_jsonb(NEW)
        );

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        v_empresa_id := OLD.empresa_id;
        v_usuario_id := OLD.updated_by;
        v_registro_id := OLD.id;

        INSERT INTO audit_auditoria (
            empresa_id, usuario_id, accion, tabla_afectada,
            registro_id, datos_antes, datos_despues
        ) VALUES (
            v_empresa_id, v_usuario_id, 'DELETE', TG_TABLE_NAME,
            v_registro_id, to_jsonb(OLD), NULL
        );

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-crear triggers de auditoría
CREATE TRIGGER trg_auditoria_paquetes
    AFTER INSERT OR UPDATE OR DELETE ON shipping_paquetes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_viajes
    AFTER INSERT OR UPDATE OR DELETE ON operations_viajes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_entregas
    AFTER INSERT OR UPDATE OR DELETE ON delivery_entregas
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_envios
    AFTER INSERT OR UPDATE OR DELETE ON shipping_envios
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_viajes_paquetes
    AFTER INSERT OR UPDATE OR DELETE ON operations_viajes_paquetes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_asignaciones
    AFTER INSERT OR UPDATE OR DELETE ON operations_asignaciones
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();

CREATE TRIGGER trg_auditoria_tipos_paquete
    AFTER INSERT OR UPDATE OR DELETE ON shipping_tipos_paquete
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general();


-- ============================================================================
-- 5. POLÍTICAS RLS COMPLETAS PARA TODAS LAS TABLAS PRINCIPALES
-- ============================================================================

-- Habilitar RLS en tablas principales que no lo tienen
ALTER TABLE customers_direcciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers_remitentes ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers_destinatarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE fleet_vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE fleet_conductores ENABLE ROW LEVEL SECURITY;
ALTER TABLE fleet_dispositivos_gps ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_rutas ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_paradas ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_geocercas ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipping_cargas ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipping_estados_envio ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_incidencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_firmas ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_fotografias ENABLE ROW LEVEL SECURITY;
ALTER TABLE communication_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE communication_chat_mensajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE communication_notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_documentos ENABLE ROW LEVEL SECURITY;

-- Direcciones: solo empresa del usuario
CREATE POLICY "Direcciones de la empresa" ON customers_direcciones
    FOR ALL USING (
        cliente_id IN (
            SELECT id FROM customers_clientes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Remitentes: solo empresa del usuario
CREATE POLICY "Remitentes de la empresa" ON customers_remitentes
    FOR ALL USING (
        cliente_id IN (
            SELECT id FROM customers_clientes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Destinatarios: solo empresa del usuario
CREATE POLICY "Destinatarios de la empresa" ON customers_destinatarios
    FOR ALL USING (
        cliente_id IN (
            SELECT id FROM customers_clientes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Vehículos: empresa del usuario
CREATE POLICY "Vehículos de la empresa" ON fleet_vehiculos
    FOR ALL USING (empresa_id = public.user_empresa_id())
    WITH CHECK (empresa_id = public.user_empresa_id() OR empresa_id IS NULL);

-- Conductores: empresa del usuario
CREATE POLICY "Conductores de la empresa" ON fleet_conductores
    FOR ALL USING (empresa_id = public.user_empresa_id())
    WITH CHECK (empresa_id = public.user_empresa_id() OR empresa_id IS NULL);

-- Remolques: empresa del usuario
DROP POLICY IF EXISTS "Remolques de la empresa" ON fleet_remolques;
CREATE POLICY "Remolques de la empresa" ON fleet_remolques
    FOR ALL USING (empresa_id = public.user_empresa_id())
    WITH CHECK (empresa_id = public.user_empresa_id() OR empresa_id IS NULL);

-- Habilitar RLS en fleet_remolques
ALTER TABLE fleet_remolques ENABLE ROW LEVEL SECURITY;

-- Dispositivos GPS: empresa del usuario
CREATE POLICY "Dispositivos GPS de la empresa" ON fleet_dispositivos_gps
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Rutas: empresa del usuario
CREATE POLICY "Rutas de la empresa" ON operations_rutas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Paradas: empresa del usuario (a través de ruta)
CREATE POLICY "Paradas de la empresa" ON operations_paradas
    FOR ALL USING (
        ruta_id IN (
            SELECT id FROM operations_rutas WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Geocercas: empresa del usuario
CREATE POLICY "Geocercas de la empresa" ON operations_geocercas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Checkpoints: empresa del usuario (a través de viaje)
CREATE POLICY "Checkpoints de la empresa" ON operations_checkpoints
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Viajes: empresa del usuario
CREATE POLICY "Viajes de la empresa" ON operations_viajes
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Cargas: empresa del usuario
CREATE POLICY "Cargas de la empresa" ON shipping_cargas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Estados de envío: lectura para todos los autenticados (catálogo global)
CREATE POLICY "Estados de envío: lectura" ON shipping_estados_envio
    FOR SELECT USING (TRUE);

-- GPS: empresa del usuario (solo SELECT para no sobrecargar)
CREATE POLICY "GPS de la empresa" ON tracking_gps
    FOR SELECT USING (empresa_id = public.user_empresa_id());

-- Eventos: empresa del usuario
CREATE POLICY "Eventos de la empresa" ON tracking_eventos
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Alertas: empresa del usuario
CREATE POLICY "Alertas de la empresa" ON tracking_alertas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Sesiones: empresa del usuario
CREATE POLICY "Sesiones de la empresa" ON tracking_sesiones
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Entregas: empresa del usuario
CREATE POLICY "Entregas de la empresa" ON delivery_entregas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Incidencias: empresa del usuario
CREATE POLICY "Incidencias de la empresa" ON delivery_incidencias
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Firmas: empresa del usuario
CREATE POLICY "Firmas de la empresa" ON delivery_firmas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Fotografías: empresa del usuario
CREATE POLICY "Fotografías de la empresa" ON delivery_fotografias
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Chats: empresa del usuario
CREATE POLICY "Chats de la empresa" ON communication_chats
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Mensajes: empresa del usuario (a través de chat)
CREATE POLICY "Mensajes de la empresa" ON communication_chat_mensajes
    FOR ALL USING (
        chat_id IN (
            SELECT id FROM communication_chats WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Notificaciones: solo el propio usuario
CREATE POLICY "Mis notificaciones" ON communication_notificaciones
    FOR ALL USING (usuario_id IN (
        SELECT id FROM core_usuarios WHERE auth_user_id = auth.uid()
    ));

-- Documentos: empresa del usuario
CREATE POLICY "Documentos de la empresa" ON storage_documentos
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Envios: empresa del usuario
ALTER TABLE shipping_envios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Envios de la empresa" ON shipping_envios
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Viajes-Conductores: empresa del usuario (a traves de viaje)
ALTER TABLE operations_viajes_conductores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viajes-Conductores de la empresa" ON operations_viajes_conductores
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Viajes-Vehiculos: empresa del usuario (a traves de viaje)
ALTER TABLE operations_viajes_vehiculos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viajes-Vehiculos de la empresa" ON operations_viajes_vehiculos
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Viajes-Paquetes: empresa del usuario (a traves de viaje)
ALTER TABLE operations_viajes_paquetes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viajes-Paquetes de la empresa" ON operations_viajes_paquetes
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Viajes-Eventos: empresa del usuario (a traves de viaje)
ALTER TABLE operations_viajes_eventos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viajes-Eventos de la empresa" ON operations_viajes_eventos
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Checklists: empresa del usuario
ALTER TABLE fleet_checklists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Checklists de la empresa" ON fleet_checklists
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Checklists Items: empresa del usuario (a traves de checklist)
ALTER TABLE fleet_checklists_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Checklists Items de la empresa" ON fleet_checklists_items
    FOR ALL USING (
        checklist_id IN (
            SELECT id FROM fleet_checklists WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Checklists Plantillas: empresa del usuario
ALTER TABLE fleet_checklists_plantillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Checklists Plantillas de la empresa" ON fleet_checklists_plantillas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Asignaciones: empresa del usuario
ALTER TABLE operations_asignaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Asignaciones de la empresa" ON operations_asignaciones
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Tipos de paquete: empresa del usuario (catalogo)
ALTER TABLE shipping_tipos_paquete ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tipos paquete de la empresa" ON shipping_tipos_paquete
    FOR ALL USING (empresa_id = public.user_empresa_id() OR empresa_id IS NULL);

-- Rutas optimizadas: empresa del usuario
ALTER TABLE operations_rutas_optimizadas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Rutas optimizadas de la empresa" ON operations_rutas_optimizadas
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- ETA: empresa del usuario (a traves de viaje)
ALTER TABLE operations_eta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ETA de la empresa" ON operations_eta
    FOR ALL USING (
        viaje_id IN (
            SELECT id FROM operations_viajes WHERE empresa_id = public.user_empresa_id()
        )
    );

-- Carga evidencias: empresa del usuario
ALTER TABLE shipping_carga_evidencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Carga evidencias de la empresa" ON shipping_carga_evidencias
    FOR ALL USING (empresa_id = public.user_empresa_id());

-- Geocercas vinculos: empresa del usuario
ALTER TABLE operations_geocercas_vinculos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Geocercas vinculos de la empresa" ON operations_geocercas_vinculos
    FOR ALL USING (empresa_id = public.user_empresa_id());


-- ============================================================================
-- 6. CONSTRAINT LÓGICA PARA GEOCERCAS (circulo vs poligono)
-- ============================================================================

ALTER TABLE operations_geocercas
    ADD CONSTRAINT chk_geocerca_tipo_geometry
    CHECK (
        (
            tipo = 'circulo'
            AND centro IS NOT NULL
            AND radio IS NOT NULL
            AND radio > 0
            AND poligono IS NULL
        )
        OR
        (
            tipo = 'poligono'
            AND poligono IS NOT NULL
            AND centro IS NULL
            AND radio IS NULL
        )
    );


-- ============================================================================
-- 7. TABLA DE ÚLTIMA POSICIÓN GPS (rendimiento para mapa en vivo)
-- ============================================================================

CREATE TABLE IF NOT EXISTS tracking_ultima_posicion (
    vehiculo_id UUID PRIMARY KEY,
    empresa_id UUID NOT NULL,
    viaje_id UUID,
    conductor_id UUID,
    dispositivo_id UUID,
    latitud DECIMAL(10, 8) NOT NULL,
    longitud DECIMAL(11, 8) NOT NULL,
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    precision_m DECIMAL(5, 2),
    velocidad_kmh DECIMAL(6, 2),
    rumbo DECIMAL(5, 2),
    bateria INTEGER CHECK (bateria >= 0 AND bateria <= 100),
    internet BOOLEAN,
    gps BOOLEAN,
    satelites INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ultima_posicion_empresa ON tracking_ultima_posicion(empresa_id);
CREATE INDEX idx_ultima_posicion_ubicacion ON tracking_ultima_posicion USING GIST(ubicacion);

-- Deshabilitar RLS (tabla de cache del sistema, el trigger la actualiza)
ALTER TABLE tracking_ultima_posicion DISABLE ROW LEVEL SECURITY;

-- Trigger para mantener actualizada la última posición GPS
CREATE OR REPLACE FUNCTION fn_update_ultima_posicion()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.vehiculo_id IS NOT NULL THEN
        INSERT INTO tracking_ultima_posicion (
            vehiculo_id, empresa_id, viaje_id, conductor_id, dispositivo_id,
            latitud, longitud, ubicacion, precision_m, velocidad_kmh, rumbo,
            bateria, internet, gps, satelites, created_at, updated_at
        ) VALUES (
            NEW.vehiculo_id, NEW.empresa_id, NEW.viaje_id, NEW.conductor_id, NEW.dispositivo_id,
            NEW.latitud, NEW.longitud, NEW.ubicacion, NEW.precision_m, NEW.velocidad_kmh, NEW.rumbo,
            NEW.bateria, NEW.internet, NEW.gps, NEW.satelites, NEW.created_at, NOW()
        )
        ON CONFLICT (vehiculo_id) DO UPDATE SET
            viaje_id = EXCLUDED.viaje_id,
            conductor_id = EXCLUDED.conductor_id,
            dispositivo_id = EXCLUDED.dispositivo_id,
            latitud = EXCLUDED.latitud,
            longitud = EXCLUDED.longitud,
            ubicacion = EXCLUDED.ubicacion,
            precision_m = EXCLUDED.precision_m,
            velocidad_kmh = EXCLUDED.velocidad_kmh,
            rumbo = EXCLUDED.rumbo,
            bateria = EXCLUDED.bateria,
            internet = EXCLUDED.internet,
            gps = EXCLUDED.gps,
            satelites = EXCLUDED.satelites,
            created_at = EXCLUDED.created_at,
            updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_update_ultima_posicion
    AFTER INSERT ON tracking_gps
    FOR EACH ROW EXECUTE FUNCTION fn_update_ultima_posicion();


-- ============================================================================
-- 8. RESTRICCIONES UNIQUE POR EMPRESA (soft delete safe)
-- ============================================================================

-- Eliminar constraints UNIQUE globales problemáticos y reemplazar con índices parciales
-- Nota: Ejecutar solo si los constraints UNIQUE actuales causan problemas con soft delete

-- fleet_vehiculos: matrícula única por empresa (solo activos)
DROP INDEX IF EXISTS idx_vehiculos_matricula;
CREATE UNIQUE INDEX uq_vehiculos_empresa_matricula_activa
    ON fleet_vehiculos(empresa_id, matricula)
    WHERE deleted_at IS NULL;

-- operations_rutas: código único por empresa (solo activas)
DROP INDEX IF EXISTS idx_rutas_codigo;
CREATE UNIQUE INDEX uq_rutas_empresa_codigo_activa
    ON operations_rutas(empresa_id, codigo)
    WHERE deleted_at IS NULL AND codigo IS NOT NULL;

-- operations_viajes: código único por empresa (solo activos)
DROP INDEX IF EXISTS idx_viajes_codigo;
CREATE UNIQUE INDEX uq_viajes_empresa_codigo_activo
    ON operations_viajes(empresa_id, codigo)
    WHERE deleted_at IS NULL;

-- shipping_cargas: código único por empresa (solo activas)
DROP INDEX IF EXISTS idx_cargas_codigo;
CREATE UNIQUE INDEX uq_cargas_empresa_codigo_activa
    ON shipping_cargas(empresa_id, codigo)
    WHERE deleted_at IS NULL;

-- shipping_envios: código único por empresa (solo activos)
CREATE UNIQUE INDEX uq_envios_empresa_codigo_activo
    ON shipping_envios(empresa_id, codigo)
    WHERE deleted_at IS NULL;

-- fleet_dispositivos_gps: IMEI único global (nunca se reutiliza)
-- Se mantiene UNIQUE global porque un IMEI no debería existir en dos empresas


-- ============================================================================
-- 9. VISTAS CON SECURITY INVOKER (respetan RLS)
-- ============================================================================

-- Eliminar vistas existentes y recrearlas con security_invoker
DROP VIEW IF EXISTS v_paquetes_completo;
DROP VIEW IF EXISTS v_viajes_activos;
DROP VIEW IF EXISTS v_ultima_posicion_gps;

-- Vista: paquetes con toda la información
CREATE VIEW v_paquetes_completo
WITH (security_invoker = true)
AS
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
CREATE VIEW v_viajes_activos
WITH (security_invoker = true)
AS
SELECT 
    v.*,
    cond.nombre || ' ' || cond.apellido AS conductor_nombre,
    cond.telefono AS conductor_telefono,
    veh.matricula,
    veh.marca || ' ' || veh.modelo AS vehiculo_descripcion,
    r.nombre AS ruta_nombre
FROM operations_viajes v
LEFT JOIN operations_viajes_conductores vjc ON v.id = vjc.viaje_id AND vjc.principal = TRUE AND vjc.deleted_at IS NULL
LEFT JOIN fleet_conductores fc ON vjc.conductor_id = fc.id
LEFT JOIN core_usuarios cond ON fc.usuario_id = cond.id
LEFT JOIN operations_viajes_vehiculos vjv ON v.id = vjv.viaje_id AND vjv.principal = TRUE AND vjv.deleted_at IS NULL
LEFT JOIN fleet_vehiculos veh ON vjv.vehiculo_id = veh.id
LEFT JOIN operations_rutas r ON v.ruta_id = r.id
WHERE v.deleted_at IS NULL
    AND v.estado IN ('programado', 'en_curso');

-- Vista: última posición GPS de cada vehículo (ahora usa la tabla materializada)
CREATE VIEW v_ultima_posicion_gps
WITH (security_invoker = true)
AS
SELECT
    vehiculo_id,
    empresa_id,
    viaje_id,
    conductor_id,
    latitud,
    longitud,
    velocidad_kmh,
    bateria,
    internet,
    gps,
    created_at
FROM tracking_ultima_posicion;


-- ============================================================================
-- 10. FUNCIÓN PARA AUTO-GENERAR CÓDIGOS POR EMPRESA
-- ============================================================================

CREATE OR REPLACE FUNCTION generar_codigo_empresa(
    p_tabla TEXT,
    p_empresa_id UUID,
    p_prefijo TEXT DEFAULT ''
) RETURNS TEXT AS $$
DECLARE
    v_codigo TEXT;
    v_existe BOOLEAN;
    v_counter INTEGER := 1;
BEGIN
    LOOP
        v_codigo := p_prefijo || LPAD(v_counter::TEXT, 4, '0');

        IF p_tabla = 'operations_rutas' THEN
            SELECT EXISTS(SELECT 1 FROM operations_rutas WHERE empresa_id = p_empresa_id AND codigo = v_codigo AND deleted_at IS NULL) INTO v_existe;
        ELSIF p_tabla = 'operations_viajes' THEN
            SELECT EXISTS(SELECT 1 FROM operations_viajes WHERE empresa_id = p_empresa_id AND codigo = v_codigo AND deleted_at IS NULL) INTO v_existe;
        ELSIF p_tabla = 'shipping_cargas' THEN
            SELECT EXISTS(SELECT 1 FROM shipping_cargas WHERE empresa_id = p_empresa_id AND codigo = v_codigo AND deleted_at IS NULL) INTO v_existe;
        ELSIF p_tabla = 'shipping_envios' THEN
            SELECT EXISTS(SELECT 1 FROM shipping_envios WHERE empresa_id = p_empresa_id AND codigo = v_codigo AND deleted_at IS NULL) INTO v_existe;
        ELSE
            v_existe := FALSE;
        END IF;

        EXIT WHEN NOT v_existe;
        v_counter := v_counter + 1;
    END LOOP;

    RETURN v_codigo;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FIN DE MEJORAS CRÍTICAS
-- ============================================================================


-- ============================================================================
-- FUNCIÓN: REGISTRO COMPLETO DE EMPRESA + USUARIO
-- ============================================================================

CREATE OR REPLACE FUNCTION public.registrar_empresa_usuario(
    p_auth_user_id UUID,
    p_email VARCHAR,
    p_nombre VARCHAR,
    p_apellido VARCHAR,
    p_telefono VARCHAR DEFAULT NULL,
    p_rol_nombre VARCHAR DEFAULT 'Administrador',
    p_mode VARCHAR DEFAULT 'new_company',
    p_company_name VARCHAR DEFAULT NULL,
    p_company_ruc VARCHAR DEFAULT NULL,
    p_invite_code VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    empresa_id UUID,
    usuario_id UUID,
    message TEXT
) AS $$
DECLARE
    v_empresa_id UUID;
    v_usuario_id UUID;
    v_rol_id UUID;
    v_existe_empresa BOOLEAN;
BEGIN
    -- Validar parámetros básicos
    IF p_auth_user_id IS NULL OR p_email IS NULL OR p_nombre IS NULL OR p_apellido IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Faltan campos obligatorios';
        RETURN;
    END IF;

    -- Obtener el rol
    SELECT id INTO v_rol_id
    FROM core_roles
    WHERE nombre = p_rol_nombre AND es_sistema = TRUE
    LIMIT 1;

    -- Manejar según el modo
    IF p_mode = 'new_company' THEN
        IF p_company_name IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Nombre de empresa es obligatorio';
            RETURN;
        END IF;

        -- Crear empresa
        INSERT INTO core_empresas (nombre, ruc, email, estado)
        VALUES (p_company_name, p_company_ruc, p_email, 'activo')
        RETURNING id INTO v_empresa_id;

    ELSIF p_mode = 'join_company' THEN
        IF p_invite_code IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Código de invitación requerido';
            RETURN;
        END IF;

        -- Buscar empresa por RUC
        SELECT id INTO v_empresa_id
        FROM core_empresas
        WHERE ruc = p_invite_code
          AND estado = 'activo'
          AND deleted_at IS NULL
        LIMIT 1;

        IF v_empresa_id IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Código de invitación no válido';
            RETURN;
        END IF;
    ELSE
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Modo inválido';
        RETURN;
    END IF;

    -- Crear usuario
    INSERT INTO core_usuarios (
        auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo
    )
    VALUES (
        p_auth_user_id, v_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE
    )
    RETURNING id INTO v_usuario_id;

    RETURN QUERY SELECT TRUE, v_empresa_id, v_usuario_id, 'Registro exitoso';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Otorgar permisos de ejecución
GRANT EXECUTE ON FUNCTION public.registrar_empresa_usuario TO anon, authenticated, service_role;


-- ============================================================================
-- FUNCIÓN: REGISTRO DE CONDUCTOR CON CUENTA DE USUARIO
-- Crea un conductor en fleet_conductores y su cuenta de usuario en core_usuarios
-- ============================================================================

CREATE OR REPLACE FUNCTION public.registrar_conductor(
    p_empresa_id UUID,
    p_nombre VARCHAR,
    p_apellido VARCHAR,
    p_email VARCHAR,
    p_password VARCHAR,
    p_licencia VARCHAR,
    p_telefono VARCHAR DEFAULT NULL,
    p_tipo_licencia VARCHAR DEFAULT NULL,
    p_vencimiento_licencia DATE DEFAULT NULL,
    p_auth_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    conductor_id UUID,
    usuario_id UUID,
    auth_user_id UUID,
    message TEXT
) AS $$
DECLARE
    v_conductor_id UUID;
    v_usuario_id UUID;
    v_auth_user_id UUID;
    v_rol_id UUID;
    v_existe_conductor BOOLEAN;
    v_existe_usuario BOOLEAN;
BEGIN
    -- Validar parámetros básicos
    IF p_empresa_id IS NULL OR p_nombre IS NULL OR p_apellido IS NULL OR p_email IS NULL OR p_licencia IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Faltan campos obligatorios';
        RETURN;
    END IF;

    -- Verificar si el conductor ya existe (por licencia y empresa)
    SELECT EXISTS(
        SELECT 1 FROM fleet_conductores
        WHERE empresa_id = p_empresa_id AND licencia = p_licencia AND deleted_at IS NULL
    ) INTO v_existe_conductor;

    IF v_existe_conductor THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Ya existe un conductor con esa licencia';
        RETURN;
    END IF;

    -- Obtener el rol de Chofer
    SELECT id INTO v_rol_id
    FROM core_roles
    WHERE nombre = 'Chofer' AND es_sistema = TRUE
    LIMIT 1;

    -- Verificar si el email ya existe en core_usuarios
    SELECT EXISTS(
        SELECT 1 FROM core_usuarios WHERE email = p_email AND deleted_at IS NULL
    ) INTO v_existe_usuario;

    IF v_existe_usuario THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Ya existe un usuario con ese email';
        RETURN;
    END IF;

    -- Si no se proporcionó auth_user_id, retornar error (el cliente debe crear el auth user primero)
    IF p_auth_user_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Se requiere auth_user_id (crear usuario en auth.users primero)';
        RETURN;
    END IF;

    v_auth_user_id := p_auth_user_id;

    -- Crear conductor
    INSERT INTO fleet_conductores (
        empresa_id, licencia, tipo_licencia, vencimiento_licencia, telefono, estado
    )
    VALUES (
        p_empresa_id, p_licencia, p_tipo_licencia, p_vencimiento_licencia, p_telefono, 'disponible'
    )
    RETURNING id INTO v_conductor_id;

    -- Crear usuario
    INSERT INTO core_usuarios (
        auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo
    )
    VALUES (
        v_auth_user_id, p_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE
    )
    RETURNING id INTO v_usuario_id;

    -- Asociar el usuario al conductor
    UPDATE fleet_conductores
    SET usuario_id = v_usuario_id
    WHERE id = v_conductor_id;

    RETURN QUERY SELECT TRUE, v_conductor_id, v_usuario_id, v_auth_user_id, 'Conductor registrado exitosamente';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.registrar_conductor TO anon, authenticated, service_role;


-- ============================================================================
-- FUNCIÓN: CREAR/ACTUALIZAR GEOCERCA
-- Maneja la conversión de coordenadas a geography/geometry PostGIS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guardar_geocerca(
    p_id UUID DEFAULT NULL,
    p_empresa_id UUID DEFAULT NULL,
    p_nombre VARCHAR DEFAULT NULL,
    p_tipo VARCHAR DEFAULT 'circulo',
    p_latitud DOUBLE PRECISION DEFAULT NULL,
    p_longitud DOUBLE PRECISION DEFAULT NULL,
    p_radio INTEGER DEFAULT NULL,
    p_color VARCHAR DEFAULT '#3B82F6',
    p_activa BOOLEAN DEFAULT TRUE,
    p_poligono JSONB DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    geocerca_id UUID,
    message TEXT
) AS $$
DECLARE
    v_geocerca_id UUID;
    v_centro GEOGRAPHY;
    v_poligono_geom GEOMETRY(POLYGON, 4326);
BEGIN
    -- Validar parámetros
    IF p_nombre IS NULL OR p_nombre = '' THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'El nombre es obligatorio';
        RETURN;
    END IF;

    IF p_tipo NOT IN ('circulo', 'poligono') THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'Tipo de geocerca inválido';
        RETURN;
    END IF;

    -- Crear el punto geográfico desde latitud/longitud
    IF p_latitud IS NOT NULL AND p_longitud IS NOT NULL THEN
        v_centro := ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography;
    END IF;

    -- Crear el polígono si se proporcionó
    IF p_tipo = 'poligono' AND p_poligono IS NOT NULL THEN
        -- p_poligono debe ser un array de coordenadas [[lng, lat], [lng, lat], ...]
        v_poligono_geom := ST_SetSRID(
            ST_GeomFromText(
                'POLYGON((' || (
                    SELECT string_agg(lng || ' ' || lat, ', ')
                    FROM jsonb_array_elements(p_poligono->'coordinates'->0) AS coord
                    CROSS JOIN LATERAL (
                        SELECT (coord->>0)::double precision AS lng,
                               (coord->>1)::double precision AS lat
                    ) AS p
                ) || ', ' || (
                    SELECT (coord->>0)::double precision || ' ' || (coord->>1)::double precision
                    FROM jsonb_array_elements(p_poligono->'coordinates'->0) AS coord
                    LIMIT 1
                ) || '))'
            ),
            4326
        );
    END IF;

    -- Si es UPDATE
    IF p_id IS NOT NULL THEN
        UPDATE operations_geocercas
        SET
            nombre = p_nombre,
            tipo = p_tipo,
            radio = CASE WHEN p_tipo = 'circulo' THEN p_radio ELSE NULL END,
            poligono = CASE WHEN p_tipo = 'poligono' THEN v_poligono_geom ELSE NULL END,
            centro = COALESCE(v_centro, centro),
            color = p_color,
            activa = p_activa,
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_geocerca_id;

        IF v_geocerca_id IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, 'Geocerca no encontrada';
            RETURN;
        END IF;

        RETURN QUERY SELECT TRUE, v_geocerca_id, 'Geocerca actualizada correctamente';
        RETURN;
    END IF;

    -- Si es INSERT
    IF p_empresa_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'empresa_id es obligatorio para crear';
        RETURN;
    END IF;

    INSERT INTO operations_geocercas (
        empresa_id, nombre, tipo, radio, poligono, centro, color, activa
    )
    VALUES (
        p_empresa_id, p_nombre, p_tipo,
        CASE WHEN p_tipo = 'circulo' THEN p_radio ELSE NULL END,
        CASE WHEN p_tipo = 'poligono' THEN v_poligono_geom ELSE NULL END,
        v_centro, p_color, p_activa
    )
    RETURNING id INTO v_geocerca_id;

    RETURN QUERY SELECT TRUE, v_geocerca_id, 'Geocerca creada correctamente';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.guardar_geocerca TO anon, authenticated, service_role;