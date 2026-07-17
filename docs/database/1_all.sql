-- ============================================================================
-- 0. EXTENSIONES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ============================================================================
-- 1. FUNCIONES GENÉRICAS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_set_ubicacion_from_latlon()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.latitud IS NOT NULL AND NEW.longitud IS NOT NULL THEN
    NEW.ubicacion := ST_SetSRID(
      ST_MakePoint(NEW.longitud::double precision, NEW.latitud::double precision), 4326
    )::geography;
  END IF;
  RETURN NEW;
END $$;

-- Generador de particiones mensuales (mejora: reemplaza 48 CREATE TABLE manuales)
CREATE OR REPLACE FUNCTION public.crear_particiones_mensuales(
  p_tabla TEXT, p_desde DATE, p_meses INT
) RETURNS VOID LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE i INT; d DATE;
BEGIN
  FOR i IN 0..p_meses-1 LOOP
    d := (date_trunc('month', p_desde) + make_interval(months => i))::date;
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
      p_tabla || '_' || to_char(d, 'YYYY_MM'), p_tabla,
      d, (d + interval '1 month')::date
    );
  END LOOP;
END $$;

-- ============================================================================
-- 2. MÓDULO CORE
-- ============================================================================
CREATE TABLE core_empresas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre VARCHAR(255) NOT NULL,
  ruc VARCHAR(20),
  telefono VARCHAR(20),
  email VARCHAR(255),
  logo TEXT,
  estado VARCHAR(20) DEFAULT 'activo' CHECK (estado IN ('activo','inactivo','suspendido')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- RUC único solo entre activas (soft-delete safe)
CREATE UNIQUE INDEX uq_empresas_ruc_activa ON core_empresas(ruc)
  WHERE deleted_at IS NULL AND ruc IS NOT NULL;
CREATE INDEX idx_empresas_estado ON core_empresas(estado) WHERE deleted_at IS NULL;

CREATE TABLE core_sucursales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  nombre VARCHAR(255) NOT NULL,
  direccion TEXT,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  telefono VARCHAR(20),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_sucursales_empresa ON core_sucursales(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_sucursales_ubicacion ON core_sucursales USING GIST(ubicacion);

CREATE TABLE core_roles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  es_sistema BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- Unicidad correcta con empresa_id NULL (catálogo global vs por empresa)
CREATE UNIQUE INDEX uq_roles_sistema_nombre ON core_roles(nombre)
  WHERE empresa_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_roles_empresa_nombre ON core_roles(empresa_id, nombre)
  WHERE empresa_id IS NOT NULL AND deleted_at IS NULL;

INSERT INTO core_roles (nombre, es_sistema) VALUES
  ('Administrador', true), ('Supervisor', true), ('Operador', true),
  ('Chofer', true), ('Cliente', true), ('Auditor', true);

CREATE TABLE core_permisos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rol_id UUID NOT NULL REFERENCES core_roles(id) ON DELETE CASCADE,
  modulo VARCHAR(100) NOT NULL,
  crear BOOLEAN DEFAULT FALSE, editar BOOLEAN DEFAULT FALSE,
  eliminar BOOLEAN DEFAULT FALSE, leer BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_permisos_rol ON core_permisos(rol_id) WHERE deleted_at IS NULL;

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
  ultimo_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_usuarios_auth ON core_usuarios(auth_user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_empresa ON core_usuarios(empresa_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_usuarios_email_activo ON core_usuarios(email) WHERE deleted_at IS NULL;

CREATE TABLE core_configuraciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  clave VARCHAR(100) NOT NULL,
  valor JSONB NOT NULL,
  descripcion TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE UNIQUE INDEX uq_config_empresa_clave ON core_configuraciones(empresa_id, clave)
  WHERE deleted_at IS NULL;

-- ============================================================================
-- 3. HELPERS DE SEGURIDAD (endurecidos con search_path)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.user_empresa_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT empresa_id FROM core_usuarios
  WHERE auth_user_id = auth.uid() AND deleted_at IS NULL AND activo = TRUE
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.user_is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM core_usuarios u
    JOIN core_roles r ON u.rol_id = r.id
    WHERE u.auth_user_id = auth.uid()
      AND r.nombre = 'Administrador'
      AND u.deleted_at IS NULL AND u.activo = TRUE
  );
$$;

-- ============================================================================
-- 4. MÓDULO FLEET
-- ============================================================================
CREATE TABLE fleet_dispositivos_gps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  imei VARCHAR(50) UNIQUE NOT NULL,   -- IMEI sí es único global (hardware físico)
  modelo VARCHAR(100),
  serial VARCHAR(100),
  estado VARCHAR(20) DEFAULT 'activo' CHECK (estado IN ('activo','inactivo','mantenimiento')),
  ultima_conexion TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_gps_empresa ON fleet_dispositivos_gps(empresa_id) WHERE deleted_at IS NULL;

CREATE TABLE fleet_vehiculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  matricula VARCHAR(20) NOT NULL,
  marca VARCHAR(100), modelo VARCHAR(100),
  anio INTEGER CHECK (anio BETWEEN 1900 AND 2100),
  capacidad_kg DECIMAL(10,2), capacidad_m3 DECIMAL(10,2),
  estado VARCHAR(20) DEFAULT 'disponible'
    CHECK (estado IN ('disponible','en_ruta','mantenimiento','fuera_servicio')),
  gps_id UUID REFERENCES fleet_dispositivos_gps(id),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- Matrícula única POR EMPRESA (no global) y solo activos
CREATE UNIQUE INDEX uq_vehiculos_empresa_matricula ON fleet_vehiculos(empresa_id, matricula)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_empresa ON fleet_vehiculos(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_estado ON fleet_vehiculos(estado);

CREATE TABLE fleet_remolques (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  vehiculo_id UUID REFERENCES fleet_vehiculos(id),
  tipo VARCHAR(50),
  capacidad_kg DECIMAL(10,2), capacidad_m3 DECIMAL(10,2),
  matricula VARCHAR(20),
  estado VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN ('disponible','asignado','mantenimiento')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_remolques_empresa ON fleet_remolques(empresa_id) WHERE deleted_at IS NULL;

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
  estado VARCHAR(20) DEFAULT 'disponible'
    CHECK (estado IN ('disponible','en_ruta','descanso','inactivo')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE UNIQUE INDEX uq_conductores_empresa_licencia ON fleet_conductores(empresa_id, licencia)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_conductores_empresa ON fleet_conductores(empresa_id) WHERE deleted_at IS NULL;

CREATE TABLE fleet_mantenimientos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
  tipo VARCHAR(50) NOT NULL,
  descripcion TEXT,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE,
  costo DECIMAL(12,2),
  kilometraje INTEGER,
  estado VARCHAR(20) DEFAULT 'programado'
    CHECK (estado IN ('programado','en_proceso','completado','cancelado')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_mantenimientos_vehiculo ON fleet_mantenimientos(vehiculo_id);

CREATE TABLE fleet_checklists (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID, -- FK diferida (dependencia circular con operations_viajes)
  vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
  conductor_id UUID REFERENCES fleet_conductores(id),
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('pre_viaje','post_viaje','mantenimiento')),
  estado VARCHAR(20) DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente','en_proceso','completado','con_observaciones')),
  fecha_inicio TIMESTAMPTZ, fecha_fin TIMESTAMPTZ,
  observaciones TEXT, kilometraje INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_checklists_empresa ON fleet_checklists(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_checklists_viaje ON fleet_checklists(viaje_id);

CREATE TABLE fleet_checklists_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  checklist_id UUID NOT NULL REFERENCES fleet_checklists(id) ON DELETE CASCADE,
  nombre VARCHAR(255) NOT NULL,
  categoria VARCHAR(100),
  orden INTEGER DEFAULT 0,
  estado VARCHAR(20) DEFAULT 'ok' CHECK (estado IN ('ok','observacion','fallo')),
  observacion TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_checklist_items_checklist ON fleet_checklists_items(checklist_id) WHERE deleted_at IS NULL;

CREATE TABLE fleet_checklists_plantillas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('pre_viaje','post_viaje','mantenimiento')),
  nombre VARCHAR(255) NOT NULL,
  categoria VARCHAR(100),
  orden INTEGER DEFAULT 0,
  es_sistema BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_plantillas_empresa_tipo ON fleet_checklists_plantillas(empresa_id, tipo)
  WHERE deleted_at IS NULL;

INSERT INTO fleet_checklists_plantillas (empresa_id, tipo, nombre, categoria, orden, es_sistema) VALUES
(NULL,'pre_viaje','Luces','Carrocería',1,TRUE),
(NULL,'pre_viaje','Frenos','Carrocería',2,TRUE),
(NULL,'pre_viaje','Espejos','Carrocería',3,TRUE),
(NULL,'pre_viaje','Documentación','Documentos',4,TRUE),
(NULL,'pre_viaje','Licencia de conducir','Documentos',5,TRUE),
(NULL,'pre_viaje','Seguro del vehículo','Documentos',6,TRUE),
(NULL,'pre_viaje','Fotos del vehículo','Evidencia',7,TRUE),
(NULL,'pre_viaje','Carga asegurada','Carga',8,TRUE),
(NULL,'pre_viaje','Sellos verificados','Carga',9,TRUE),
(NULL,'pre_viaje','Temperatura de carga','Carga',10,TRUE),
(NULL,'pre_viaje','Neumáticos','Carrocería',11,TRUE),
(NULL,'pre_viaje','Kilometraje actual','Carrocería',12,TRUE),
(NULL,'post_viaje','Kilometraje final','Carrocería',1,TRUE),
(NULL,'post_viaje','Estado de neumáticos','Carrocería',2,TRUE),
(NULL,'post_viaje','Combustible restante','Carrocería',3,TRUE),
(NULL,'post_viaje','Daños en carrocería','Carrocería',4,TRUE),
(NULL,'post_viaje','Carga entregada completa','Carga',5,TRUE),
(NULL,'post_viaje','Sellos retirados','Carga',6,TRUE),
(NULL,'post_viaje','Documentos de entrega','Documentos',7,TRUE),
(NULL,'post_viaje','Fotos de entrega','Evidencia',8,TRUE),
(NULL,'mantenimiento','Aceite y filtros','Motor',1,TRUE),
(NULL,'mantenimiento','Frenos','Frenos',2,TRUE),
(NULL,'mantenimiento','Neumáticos','Neumáticos',3,TRUE),
(NULL,'mantenimiento','Luces','Luces',4,TRUE),
(NULL,'mantenimiento','Suspensión','Motor',5,TRUE),
(NULL,'mantenimiento','Transmisión','Motor',6,TRUE),
(NULL,'mantenimiento','Refrigeración','Motor',7,TRUE),
(NULL,'mantenimiento','Fugas de líquidos','Motor',8,TRUE),
(NULL,'mantenimiento','Estado de batería','Seguridad',9,TRUE),
(NULL,'mantenimiento','Documentación al día','Documentos',10,TRUE);

CREATE TABLE fleet_capacidades (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id) ON DELETE CASCADE,
  peso_max_kg DECIMAL(10,2), volumen_max_m3 DECIMAL(10,2),
  pallets_max INTEGER, metros_lineales_max DECIMAL(8,2), bultos_max INTEGER,
  espacios_adr INTEGER,
  tiene_refrigeracion BOOLEAN DEFAULT FALSE,
  temperatura_min DECIMAL(5,2), temperatura_max DECIMAL(5,2),
  zonas_temperatura INTEGER DEFAULT 1,
  vigente_desde DATE DEFAULT CURRENT_DATE, vigente_hasta DATE,
  activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_capacidades_vehiculo ON fleet_capacidades(vehiculo_id) WHERE activa = TRUE;

-- ============================================================================
-- 5. MÓDULO CUSTOMERS
-- ============================================================================
CREATE TABLE customers_clientes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  nombre VARCHAR(255) NOT NULL,
  ruc VARCHAR(20), telefono VARCHAR(20), email VARCHAR(255),
  tipo VARCHAR(20) DEFAULT 'regular' CHECK (tipo IN ('regular','vip','corporativo')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_clientes_empresa ON customers_clientes(empresa_id) WHERE deleted_at IS NULL;

CREATE TABLE customers_direcciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
  tipo VARCHAR(20) DEFAULT 'principal' CHECK (tipo IN ('principal','envio','facturacion','otra')),
  direccion TEXT NOT NULL,
  ciudad VARCHAR(100), provincia VARCHAR(100),
  pais VARCHAR(100) DEFAULT 'Perú',
  codigo_postal VARCHAR(20),
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  referencia TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_direcciones_cliente ON customers_direcciones(cliente_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_direcciones_ubicacion ON customers_direcciones USING GIST(ubicacion);

CREATE TABLE customers_remitentes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
  direccion_id UUID REFERENCES customers_direcciones(id),
  nombre VARCHAR(255) NOT NULL,
  documento VARCHAR(20), telefono VARCHAR(20), email VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_remitentes_cliente ON customers_remitentes(cliente_id) WHERE deleted_at IS NULL;

CREATE TABLE customers_destinatarios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  cliente_id UUID NOT NULL REFERENCES customers_clientes(id) ON DELETE CASCADE,
  direccion_id UUID REFERENCES customers_direcciones(id),
  nombre VARCHAR(255) NOT NULL,
  documento VARCHAR(20), telefono VARCHAR(20), email VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_destinatarios_cliente ON customers_destinatarios(cliente_id) WHERE deleted_at IS NULL;

-- ============================================================================
-- 6. MÓDULO OPERATIONS (base)
-- ============================================================================
CREATE TABLE operations_geocercas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  nombre VARCHAR(255) NOT NULL,
  tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('circulo','poligono')),
  radio INTEGER,
  poligono GEOMETRY(POLYGON, 4326),
  centro GEOGRAPHY(POINT, 4326),
  color VARCHAR(20),
  activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID,
  CONSTRAINT chk_geocerca_tipo_geometry CHECK (
    (tipo = 'circulo'  AND centro IS NOT NULL AND radio IS NOT NULL AND radio > 0 AND poligono IS NULL)
    OR
    (tipo = 'poligono' AND poligono IS NOT NULL AND centro IS NULL AND radio IS NULL)
  )
);
CREATE INDEX idx_geocercas_empresa ON operations_geocercas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_geocercas_centro ON operations_geocercas USING GIST(centro);
CREATE INDEX idx_geocercas_poligono ON operations_geocercas USING GIST(poligono);

CREATE TABLE operations_geocercas_vinculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  geocerca_id UUID NOT NULL REFERENCES operations_geocercas(id) ON DELETE CASCADE,
  referencia_tipo VARCHAR(50) NOT NULL CHECK (referencia_tipo IN ('cliente','direccion','sucursal','otra')),
  referencia_id UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID,
  CONSTRAINT uq_geocerca_vinculo UNIQUE (geocerca_id, referencia_tipo, referencia_id)
);

CREATE TABLE operations_rutas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  codigo VARCHAR(50),
  nombre VARCHAR(255) NOT NULL,
  origen VARCHAR(255), destino VARCHAR(255),
  distancia_km DECIMAL(10,2),
  tiempo_estimado_min INTEGER,
  activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- Código único por empresa (no global)
CREATE UNIQUE INDEX uq_rutas_empresa_codigo ON operations_rutas(empresa_id, codigo)
  WHERE deleted_at IS NULL AND codigo IS NOT NULL;
CREATE INDEX idx_rutas_empresa ON operations_rutas(empresa_id) WHERE deleted_at IS NULL;

CREATE TABLE operations_rutas_optimizadas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  ruta_id UUID NOT NULL REFERENCES operations_rutas(id) ON DELETE CASCADE,
  proveedor VARCHAR(50) NOT NULL CHECK (proveedor IN ('google','osrm','mapbox','here','otro')),
  distancia_km DECIMAL(10,2), tiempo_estimado_min INTEGER,
  polyline TEXT, waypoints JSONB, algoritmo VARCHAR(50),
  fecha_calculo TIMESTAMPTZ DEFAULT NOW(),
  es_activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_rutas_opt_ruta ON operations_rutas_optimizadas(ruta_id);

CREATE TABLE operations_paradas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ruta_id UUID NOT NULL REFERENCES operations_rutas(id) ON DELETE CASCADE,
  direccion_id UUID REFERENCES customers_direcciones(id),
  orden INTEGER NOT NULL,
  nombre VARCHAR(255), direccion TEXT,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  tipo VARCHAR(50) CHECK (tipo IN ('recogida','entrega','descanso','combustible','otra')),
  eta_minutos INTEGER, tiempo_estancia_min INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_paradas_ruta ON operations_paradas(ruta_id, orden) WHERE deleted_at IS NULL;
CREATE INDEX idx_paradas_ubicacion ON operations_paradas USING GIST(ubicacion);

CREATE TABLE operations_viajes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  codigo VARCHAR(50) NOT NULL,
  ruta_id UUID REFERENCES operations_rutas(id),
  fecha_inicio TIMESTAMPTZ, fecha_fin TIMESTAMPTZ,
  hora_programada_salida TIMESTAMPTZ, hora_real_salida TIMESTAMPTZ,
  hora_programada_llegada TIMESTAMPTZ, hora_real_llegada TIMESTAMPTZ,
  estado VARCHAR(30) DEFAULT 'programado'
    CHECK (estado IN ('programado','en_curso','pausado','completado','cancelado')),
  km_estimados DECIMAL(10,2), km_reales DECIMAL(10,2), distancia_real_km DECIMAL(10,2),
  tiempo_estimado_min INTEGER, tiempo_real_min INTEGER,
  tiempo_detenido_seg INTEGER DEFAULT 0, tiempo_movimiento_seg INTEGER DEFAULT 0,
  combustible_litros DECIMAL(10,2), consumo_combustible DECIMAL(10,2),
  peajes DECIMAL(12,2), costo_total DECIMAL(12,2),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE UNIQUE INDEX uq_viajes_empresa_codigo ON operations_viajes(empresa_id, codigo)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_empresa ON operations_viajes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_viajes_estado ON operations_viajes(estado);
CREATE INDEX idx_viajes_fecha ON operations_viajes(fecha_inicio);

-- FK diferida de checklists (dependencia circular)
ALTER TABLE fleet_checklists
  ADD CONSTRAINT fk_checklists_viaje FOREIGN KEY (viaje_id) REFERENCES operations_viajes(id);

CREATE TABLE operations_eta (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  parada_id UUID NOT NULL REFERENCES operations_paradas(id) ON DELETE CASCADE,
  eta_original TIMESTAMPTZ, eta_actual TIMESTAMPTZ,
  retraso_min INTEGER DEFAULT 0,
  distancia_restante_km DECIMAL(10,2),
  ultima_actualizacion TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_eta_viaje ON operations_eta(viaje_id);

CREATE TABLE operations_checkpoints (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  parada_id UUID REFERENCES operations_paradas(id),
  hora_llegada TIMESTAMPTZ, hora_salida TIMESTAMPTZ,
  estado VARCHAR(30) DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente','llego','en_proceso','completado','omitido')),
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_checkpoints_viaje ON operations_checkpoints(viaje_id) WHERE deleted_at IS NULL;

CREATE TABLE operations_viajes_conductores (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  conductor_id UUID NOT NULL REFERENCES fleet_conductores(id),
  principal BOOLEAN DEFAULT TRUE,
  estado VARCHAR(20) DEFAULT 'asignado'
    CHECK (estado IN ('asignado','aceptado','en_curso','completado','rechazado','cancelado')),
  fecha_asignacion TIMESTAMPTZ DEFAULT NOW(),
  fecha_aceptacion TIMESTAMPTZ, fecha_inicio TIMESTAMPTZ, fecha_fin TIMESTAMPTZ,
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_vc_viaje ON operations_viajes_conductores(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_vc_conductor ON operations_viajes_conductores(conductor_id);

CREATE TABLE operations_viajes_vehiculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id),
  tipo VARCHAR(30) DEFAULT 'principal'
    CHECK (tipo IN ('principal','remolque','semirremolque','acoplado')),
  principal BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_vv_viaje ON operations_viajes_vehiculos(viaje_id) WHERE deleted_at IS NULL;

CREATE TABLE operations_viajes_paquetes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  paquete_id UUID NOT NULL, -- FK diferida a shipping_paquetes
  parada_id UUID REFERENCES operations_paradas(id),
  orden_entrega INTEGER,
  estado VARCHAR(30) DEFAULT 'asignado'
    CHECK (estado IN ('asignado','cargado','en_transito','descargado','entregado','reasignado')),
  hora_asignacion TIMESTAMPTZ DEFAULT NOW(),
  hora_carga TIMESTAMPTZ, hora_descarga TIMESTAMPTZ, hora_entrega TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- CORREGIDO: un paquete solo puede tener UNA asignación activa (en cualquier viaje)
CREATE UNIQUE INDEX uq_paquete_asignacion_activa
  ON operations_viajes_paquetes(paquete_id)
  WHERE deleted_at IS NULL AND estado NOT IN ('entregado','reasignado');
CREATE INDEX idx_vp_viaje ON operations_viajes_paquetes(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_vp_paquete ON operations_viajes_paquetes(paquete_id);

CREATE TABLE operations_viajes_eventos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
    'viaje_aceptado','checklist_completado','carga_iniciada','carga_finalizada',
    'viaje_iniciado','viaje_pausado','viaje_reanudado','parada_programada',
    'parada_no_programada','incidente','viaje_cerrado'
  )),
  usuario_id UUID REFERENCES core_usuarios(id),
  descripcion TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_ve_viaje ON operations_viajes_eventos(viaje_id) WHERE deleted_at IS NULL;

CREATE TABLE operations_asignaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  usuario_id UUID NOT NULL REFERENCES core_usuarios(id),
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN ('viaje','conductor','vehiculo','paquete','reasignacion')),
  referencia_tipo VARCHAR(50), referencia_id UUID,
  observacion TEXT, metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_asignaciones_viaje ON operations_asignaciones(viaje_id);

-- ============================================================================
-- 7. MÓDULO SHIPPING
-- ============================================================================
CREATE TABLE shipping_estados_envio (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo VARCHAR(50) UNIQUE NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT, color VARCHAR(20), orden INTEGER,
  es_final BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
INSERT INTO shipping_estados_envio (codigo, nombre, color, orden, es_final) VALUES
('CREADO','Creado','#9E9E9E',1,false), ('PREPARANDO','Preparando','#2196F3',2,false),
('DESPACHADO','Despachado','#03A9F4',3,false), ('EN_RUTA','En Ruta','#FF9800',4,false),
('EN_CENTRO','En Centro','#FFC107',5,false), ('EN_REPARTO','En Reparto','#FF5722',6,false),
('ENTREGADO','Entregado','#4CAF50',7,true), ('DEVUELTO','Devuelto','#F44336',8,true),
('CANCELADO','Cancelado','#795548',9,true);

CREATE TABLE shipping_tipos_paquete (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
  codigo VARCHAR(50) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  es_sistema BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
-- Unicidad correcta separando catálogo global de por-empresa
CREATE UNIQUE INDEX uq_tipos_paquete_sistema ON shipping_tipos_paquete(codigo)
  WHERE empresa_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_tipos_paquete_empresa ON shipping_tipos_paquete(empresa_id, codigo)
  WHERE empresa_id IS NOT NULL AND deleted_at IS NULL;

INSERT INTO shipping_tipos_paquete (codigo, nombre, es_sistema) VALUES
('paquete','Paquete',true), ('sobre','Sobre',true), ('carga','Carga',true),
('documento','Documento',true), ('pallet','Pallet',true), ('contenedor','Contenedor',true);

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
  estado VARCHAR(30) DEFAULT 'creado'
    CHECK (estado IN ('creado','preparando','despachado','en_ruta','entregado','cancelado')),
  fecha_programada TIMESTAMPTZ, fecha_despacho TIMESTAMPTZ, fecha_entrega TIMESTAMPTZ,
  observaciones TEXT,
  valor_total DECIMAL(12,2), costo_total DECIMAL(12,2),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE UNIQUE INDEX uq_envios_empresa_codigo ON shipping_envios(empresa_id, codigo)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_envios_empresa ON shipping_envios(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_envios_cliente ON shipping_envios(cliente_id);

CREATE TABLE shipping_paquetes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  envio_id UUID REFERENCES shipping_envios(id),
  tracking_number VARCHAR(50) UNIQUE NOT NULL, -- global: visible al cliente final
  codigo_qr TEXT,
  codigo_barras VARCHAR(100),
  cliente_id UUID NOT NULL REFERENCES customers_clientes(id),
  remitente_id UUID REFERENCES customers_remitentes(id),
  destinatario_id UUID REFERENCES customers_destinatarios(id),
  direccion_origen UUID REFERENCES customers_direcciones(id),
  direccion_destino UUID REFERENCES customers_direcciones(id),
  peso DECIMAL(10,3), volumen DECIMAL(10,3),
  alto_cm DECIMAL(10,2), ancho_cm DECIMAL(10,2), largo_cm DECIMAL(10,2),
  valor_declarado DECIMAL(12,2), costo_envio DECIMAL(12,2),
  tipo VARCHAR(50) DEFAULT 'paquete',
  tipo_id UUID REFERENCES shipping_tipos_paquete(id),
  prioridad VARCHAR(20) DEFAULT 'normal' CHECK (prioridad IN ('baja','normal','alta','urgente')),
  contenido TEXT,
  fragil BOOLEAN DEFAULT FALSE, apilable BOOLEAN DEFAULT TRUE,
  requiere_refrigeracion BOOLEAN DEFAULT FALSE,
  temperatura_min DECIMAL(5,2), temperatura_max DECIMAL(5,2),
  mercancia_peligrosa BOOLEAN DEFAULT FALSE,
  imo_class VARCHAR(20), un_number VARCHAR(30), numero_sello VARCHAR(50),
  requiere_firma BOOLEAN DEFAULT TRUE, requiere_otp BOOLEAN DEFAULT FALSE,
  requiere_documento BOOLEAN DEFAULT FALSE, custodia BOOLEAN DEFAULT FALSE,
  codigo_cliente VARCHAR(100),
  estado_actual UUID REFERENCES shipping_estados_envio(id),
  fecha_creacion TIMESTAMPTZ DEFAULT NOW(),
  fecha_entrega_estimada TIMESTAMPTZ, fecha_entrega_real TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_paquetes_empresa ON shipping_paquetes(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_paquetes_envio ON shipping_paquetes(envio_id);
CREATE INDEX idx_paquetes_cliente ON shipping_paquetes(cliente_id);
CREATE INDEX idx_paquetes_estado ON shipping_paquetes(estado_actual);
CREATE INDEX idx_paquetes_barras ON shipping_paquetes(codigo_barras);

-- FK diferida (dependencia circular)
ALTER TABLE operations_viajes_paquetes
  ADD CONSTRAINT fk_vp_paquete FOREIGN KEY (paquete_id)
  REFERENCES shipping_paquetes(id) ON DELETE CASCADE;

CREATE TABLE shipping_cargas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  codigo VARCHAR(50) NOT NULL,
  descripcion TEXT,
  peso_total DECIMAL(10,2), volumen_total DECIMAL(10,2),
  cantidad_paquetes INTEGER DEFAULT 0,
  estado VARCHAR(30) DEFAULT 'creada'
    CHECK (estado IN ('creada','cargando','completa','en_transito','descargada','cancelada')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE UNIQUE INDEX uq_cargas_empresa_codigo ON shipping_cargas(empresa_id, codigo)
  WHERE deleted_at IS NULL;
CREATE INDEX idx_cargas_viaje ON shipping_cargas(viaje_id);

CREATE TABLE shipping_paquetes_cargas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
  carga_id UUID NOT NULL REFERENCES shipping_cargas(id) ON DELETE CASCADE,
  orden_carga INTEGER,
  fecha_asignacion TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID,
  CONSTRAINT uq_paquete_carga UNIQUE (paquete_id, carga_id)
);

CREATE TABLE shipping_carga_evidencias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  carga_id UUID NOT NULL REFERENCES shipping_cargas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  tipo VARCHAR(50) NOT NULL
    CHECK (tipo IN ('camion_cargado','pallet','sello','documento','photo_galga','otra')),
  url TEXT NOT NULL,
  descripcion TEXT, numero_sello VARCHAR(50),
  usuario_id UUID REFERENCES core_usuarios(id),
  fecha TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_carga_evid_carga ON shipping_carga_evidencias(carga_id);

-- Historial de estados (particionada)
CREATE TABLE shipping_historial_estados (
  id UUID DEFAULT uuid_generate_v4(),
  paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
  estado_id UUID NOT NULL REFERENCES shipping_estados_envio(id),
  usuario_id UUID REFERENCES core_usuarios(id),
  comentario TEXT,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID,
  PRIMARY KEY (id, fecha)
) PARTITION BY RANGE (fecha);
CREATE TABLE shipping_historial_estados_default PARTITION OF shipping_historial_estados DEFAULT;
SELECT crear_particiones_mensuales('shipping_historial_estados', CURRENT_DATE, 12);
CREATE INDEX idx_historial_paquete ON shipping_historial_estados(paquete_id);
CREATE INDEX idx_historial_fecha ON shipping_historial_estados(fecha);

-- ============================================================================
-- 8. MÓDULO TRACKING
-- ============================================================================
CREATE TABLE tracking_gps (
  id UUID DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL,
  viaje_id UUID, vehiculo_id UUID, conductor_id UUID, dispositivo_id UUID,
  latitud DECIMAL(10,8) NOT NULL CHECK (latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
  precision_m DECIMAL(5,2), altitud DECIMAL(8,2),
  velocidad_kmh DECIMAL(6,2), rumbo DECIMAL(5,2),
  bateria INTEGER CHECK (bateria BETWEEN 0 AND 100),
  internet BOOLEAN, gps BOOLEAN, satelites INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE tracking_gps_default PARTITION OF tracking_gps DEFAULT;
SELECT crear_particiones_mensuales('tracking_gps', CURRENT_DATE, 12);
CREATE INDEX idx_tgps_vehiculo_fecha ON tracking_gps(vehiculo_id, created_at DESC);
CREATE INDEX idx_tgps_viaje ON tracking_gps(viaje_id);
CREATE INDEX idx_tgps_empresa ON tracking_gps(empresa_id);
CREATE INDEX idx_tgps_ubicacion ON tracking_gps USING GIST(ubicacion);

CREATE TABLE tracking_eventos (
  id UUID DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL,
  viaje_id UUID, vehiculo_id UUID, conductor_id UUID,
  tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
    'inicio_viaje','fin_viaje','entrada_geocerca','salida_geocerca',
    'detenido','exceso_velocidad','frenada_brusca','aceleracion_brusca',
    'desvio_ruta','incidente','entrega','recogida','parada_no_programada'
  )),
  descripcion TEXT,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE tracking_eventos_default PARTITION OF tracking_eventos DEFAULT;
SELECT crear_particiones_mensuales('tracking_eventos', CURRENT_DATE, 12);
CREATE INDEX idx_tev_viaje ON tracking_eventos(viaje_id);
CREATE INDEX idx_tev_tipo ON tracking_eventos(tipo);
CREATE INDEX idx_tev_empresa ON tracking_eventos(empresa_id);
CREATE INDEX idx_tev_metadata ON tracking_eventos USING GIN(metadata);

CREATE TABLE tracking_alertas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  vehiculo_id UUID REFERENCES fleet_vehiculos(id),
  conductor_id UUID REFERENCES fleet_conductores(id),
  tipo VARCHAR(50) NOT NULL,
  nivel VARCHAR(20) NOT NULL CHECK (nivel IN ('info','warning','critical')),
  titulo VARCHAR(255) NOT NULL,
  mensaje TEXT, metadata JSONB,
  leido BOOLEAN DEFAULT FALSE,
  leido_por UUID REFERENCES core_usuarios(id),
  fecha_leido TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_alertas_empresa ON tracking_alertas(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_alertas_leido ON tracking_alertas(leido) WHERE leido = FALSE;

CREATE TABLE tracking_sesiones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  vehiculo_id UUID REFERENCES fleet_vehiculos(id),
  conductor_id UUID REFERENCES fleet_conductores(id),
  dispositivo_id UUID REFERENCES fleet_dispositivos_gps(id),
  fecha_inicio TIMESTAMPTZ NOT NULL,
  fecha_fin TIMESTAMPTZ,
  distancia_km DECIMAL(10,2),
  puntos_gps INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_sesiones_viaje ON tracking_sesiones(viaje_id);

-- Cache de última posición (mejora de rendimiento para mapa en vivo)
CREATE TABLE tracking_ultima_posicion (
  vehiculo_id UUID PRIMARY KEY,
  empresa_id UUID NOT NULL,
  viaje_id UUID, conductor_id UUID, dispositivo_id UUID,
  latitud DECIMAL(10,8) NOT NULL, longitud DECIMAL(11,8) NOT NULL,
  ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
  precision_m DECIMAL(5,2), velocidad_kmh DECIMAL(6,2), rumbo DECIMAL(5,2),
  bateria INTEGER CHECK (bateria BETWEEN 0 AND 100),
  internet BOOLEAN, gps BOOLEAN, satelites INTEGER,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_ultpos_empresa ON tracking_ultima_posicion(empresa_id);
CREATE INDEX idx_ultpos_ubicacion ON tracking_ultima_posicion USING GIST(ubicacion);

CREATE OR REPLACE FUNCTION public.fn_update_ultima_posicion()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
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
      viaje_id = EXCLUDED.viaje_id, conductor_id = EXCLUDED.conductor_id,
      dispositivo_id = EXCLUDED.dispositivo_id,
      latitud = EXCLUDED.latitud, longitud = EXCLUDED.longitud,
      ubicacion = EXCLUDED.ubicacion, precision_m = EXCLUDED.precision_m,
      velocidad_kmh = EXCLUDED.velocidad_kmh, rumbo = EXCLUDED.rumbo,
      bateria = EXCLUDED.bateria, internet = EXCLUDED.internet,
      gps = EXCLUDED.gps, satelites = EXCLUDED.satelites,
      created_at = EXCLUDED.created_at, updated_at = NOW();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_update_ultima_posicion
  AFTER INSERT ON tracking_gps
  FOR EACH ROW EXECUTE FUNCTION fn_update_ultima_posicion();

-- ============================================================================
-- 9. MÓDULO DELIVERY
-- ============================================================================
CREATE TABLE delivery_firmas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  imagen_url TEXT NOT NULL,
  formato VARCHAR(10) DEFAULT 'png',
  tamano_bytes INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);

CREATE TABLE delivery_entregas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id),
  viaje_id UUID REFERENCES operations_viajes(id),
  receptor_nombre VARCHAR(255) NOT NULL,
  receptor_documento VARCHAR(20),
  receptor_relacion VARCHAR(50),
  firma_id UUID REFERENCES delivery_firmas(id),
  fecha TIMESTAMPTZ DEFAULT NOW(),
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  observacion TEXT,
  tipo_entrega VARCHAR(20) DEFAULT 'normal'
    CHECK (tipo_entrega IN ('normal','dejado_en_puerta','vecino','punto_acuerdo')),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_entregas_paquete ON delivery_entregas(paquete_id);
CREATE INDEX idx_entregas_viaje ON delivery_entregas(viaje_id);

CREATE TABLE delivery_incidencias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  paquete_id UUID REFERENCES shipping_paquetes(id),
  viaje_id UUID REFERENCES operations_viajes(id),
  tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
    'direccion_incorrecta','destinatario_ausente','rechazado','dano_paquete',
    'paquete_extraviado','retraso','acceso_restringido','clima_adverso',
    'averia_vehiculo','otra'
  )),
  descripcion TEXT NOT NULL,
  foto_url TEXT,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  estado VARCHAR(20) DEFAULT 'abierta'
    CHECK (estado IN ('abierta','en_proceso','resuelta','cerrada')),
  resuelta_por UUID REFERENCES core_usuarios(id),
  fecha_resolucion TIMESTAMPTZ,
  solucion TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_incidencias_paquete ON delivery_incidencias(paquete_id);

CREATE TABLE delivery_fotografias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  paquete_id UUID REFERENCES shipping_paquetes(id),
  entrega_id UUID REFERENCES delivery_entregas(id),
  incidencia_id UUID REFERENCES delivery_incidencias(id),
  url TEXT NOT NULL,
  tipo VARCHAR(50) CHECK (tipo IN ('entrega','incidencia','dano','paquete','documento','otra')),
  descripcion TEXT,
  latitud DECIMAL(10,8), longitud DECIMAL(11,8),
  fecha TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);

CREATE TABLE delivery_sesiones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id),
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id),
  parada_id UUID NOT NULL REFERENCES operations_paradas(id),
  conductor_id UUID NOT NULL REFERENCES fleet_conductores(id),
  paso_actual VARCHAR(30) NOT NULL DEFAULT 'confirm_arrival',
  paquetes_escaneados JSONB NOT NULL DEFAULT '[]'::jsonb,
  foto_completada BOOLEAN NOT NULL DEFAULT FALSE,
  firma_completada BOOLEAN NOT NULL DEFAULT FALSE,
  otp_verificado BOOLEAN NOT NULL DEFAULT FALSE,
  estado VARCHAR(20) NOT NULL DEFAULT 'en_proceso'
    CHECK (estado IN ('en_proceso','completada','cancelada')),
  client_operation_id UUID UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 10. MÓDULO COMMUNICATION
-- ============================================================================
CREATE TABLE communication_chats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  paquete_id UUID REFERENCES shipping_paquetes(id),
  tipo VARCHAR(20) DEFAULT 'viaje' CHECK (tipo IN ('viaje','paquete','soporte','grupo')),
  nombre VARCHAR(255),
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);

CREATE TABLE communication_chat_mensajes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chat_id UUID NOT NULL REFERENCES communication_chats(id) ON DELETE CASCADE,
  usuario_id UUID REFERENCES core_usuarios(id),
  mensaje TEXT,
  tipo VARCHAR(20) DEFAULT 'texto'
    CHECK (tipo IN ('texto','imagen','audio','video','archivo','ubicacion')),
  archivo_url TEXT, archivo_nombre VARCHAR(255), archivo_tamano INTEGER,
  leido BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_mensajes_chat ON communication_chat_mensajes(chat_id) WHERE deleted_at IS NULL;

CREATE TABLE communication_notificaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  usuario_id UUID NOT NULL REFERENCES core_usuarios(id) ON DELETE CASCADE,
  titulo VARCHAR(255) NOT NULL,
  mensaje TEXT NOT NULL,
  tipo VARCHAR(50) CHECK (tipo IN (
    'info','success','warning','error','tracking','entrega','incidencia','sistema'
  )),
  referencia_tipo VARCHAR(50), referencia_id UUID,
  leido BOOLEAN DEFAULT FALSE, fecha_leido TIMESTAMPTZ,
  datos_adicionales JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_notif_usuario ON communication_notificaciones(usuario_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notif_leido ON communication_notificaciones(leido) WHERE leido = FALSE;

-- ============================================================================
-- 11. MÓDULO AUDIT (particionada, sin RLS: log de sistema)
-- ============================================================================
CREATE TABLE audit_auditoria (
  id UUID DEFAULT uuid_generate_v4(),
  empresa_id UUID, usuario_id UUID, usuario_nombre VARCHAR(255),
  accion VARCHAR(50) NOT NULL
    CHECK (accion IN ('INSERT','UPDATE','DELETE','LOGIN','LOGOUT','EXPORT','IMPORT')),
  tabla_afectada VARCHAR(100) NOT NULL,
  registro_id UUID,
  datos_antes JSONB, datos_despues JSONB,
  ip_address INET, user_agent TEXT, metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE audit_auditoria_default PARTITION OF audit_auditoria DEFAULT;
SELECT crear_particiones_mensuales('audit_auditoria', CURRENT_DATE, 12);
CREATE INDEX idx_audit_tabla ON audit_auditoria(tabla_afectada);
CREATE INDEX idx_audit_registro ON audit_auditoria(registro_id);
CREATE INDEX idx_audit_fecha ON audit_auditoria(created_at DESC);
ALTER TABLE audit_auditoria DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON audit_auditoria FROM anon, authenticated;

-- ============================================================================
-- 12. MÓDULO STORAGE
-- ============================================================================
CREATE TABLE storage_documentos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  bucket VARCHAR(100) NOT NULL,
  ruta_archivo TEXT NOT NULL,
  url_publica TEXT,
  nombre_original VARCHAR(255),
  mime_type VARCHAR(100),
  tamano_bytes BIGINT,
  referencia_tipo VARCHAR(50), referencia_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_docs_referencia ON storage_documentos(referencia_tipo, referencia_id);

-- ============================================================================
-- 13. MODELO OPERACIÓN / EJECUCIÓN / CUSTODIA (Doc 2)
-- ============================================================================
CREATE TABLE operations_estados_operacion (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo VARCHAR(50) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  es_final BOOLEAN DEFAULT FALSE,
  es_sistema BOOLEAN DEFAULT FALSE,
  orden INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_estados_op_codigo ON operations_estados_operacion(codigo)
  WHERE es_sistema = TRUE;
INSERT INTO operations_estados_operacion (codigo, nombre, es_final, es_sistema, orden) VALUES
('pendiente','Pendiente',FALSE,TRUE,1), ('en_proceso','En proceso',FALSE,TRUE,2),
('completada','Completada',TRUE,TRUE,3), ('fallida','Fallida',TRUE,TRUE,4),
('cancelada','Cancelada',TRUE,TRUE,5), ('reasignada','Reasignada',TRUE,TRUE,6);

CREATE TABLE operations_tipos_operacion (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo VARCHAR(50) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  inventory_action VARCHAR(20) DEFAULT 'NONE' CHECK (inventory_action IN (
    'NONE','ADD','REMOVE','TRANSFER_IN','TRANSFER_OUT','PACK','UNPACK','MERGE','SPLIT'
  )),
  requiere_evidencia BOOLEAN DEFAULT FALSE,
  requiere_firma BOOLEAN DEFAULT FALSE,
  es_sistema BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_tipos_op_codigo ON operations_tipos_operacion(codigo)
  WHERE es_sistema = TRUE;
INSERT INTO operations_tipos_operacion (codigo, nombre, inventory_action, requiere_firma, es_sistema) VALUES
('recoger','Recoger','ADD',FALSE,TRUE), ('cargar','Cargar','ADD',FALSE,TRUE),
('entregar','Entregar','REMOVE',TRUE,TRUE), ('descargar','Descargar','REMOVE',FALSE,TRUE),
('transferir','Transferir','TRANSFER_OUT',FALSE,TRUE),
('inspeccionar','Inspeccionar','NONE',FALSE,TRUE),
('pesar','Pesar','NONE',FALSE,TRUE), ('retener','Retener','NONE',FALSE,TRUE);

CREATE TABLE operations_motivos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id) ON DELETE CASCADE,
  codigo VARCHAR(50) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  categoria VARCHAR(50) NOT NULL CHECK (categoria IN (
    'fallo_entrega','fallo_recogida','incidencia','cancelacion','devolucion'
  )),
  descripcion TEXT,
  permite_reintento BOOLEAN DEFAULT TRUE,
  requiere_evidencia BOOLEAN DEFAULT FALSE,
  genera_devolucion BOOLEAN DEFAULT FALSE,
  es_responsabilidad_cliente BOOLEAN DEFAULT FALSE,
  activo BOOLEAN DEFAULT TRUE,
  es_sistema BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_motivos_sistema ON operations_motivos(codigo) WHERE empresa_id IS NULL;
CREATE UNIQUE INDEX uq_motivos_empresa ON operations_motivos(empresa_id, codigo) WHERE empresa_id IS NOT NULL;
INSERT INTO operations_motivos (codigo, nombre, categoria, permite_reintento, es_responsabilidad_cliente, es_sistema) VALUES
('cliente_ausente','Cliente ausente','fallo_entrega',TRUE,TRUE,TRUE),
('direccion_incorrecta','Dirección incorrecta','fallo_entrega',TRUE,FALSE,TRUE),
('direccion_cerrada','Establecimiento cerrado','fallo_entrega',TRUE,TRUE,TRUE),
('rechazado_cliente','Rechazado por cliente','devolucion',FALSE,FALSE,TRUE),
('paquete_danado','Paquete dañado','incidencia',FALSE,FALSE,TRUE),
('acceso_restringido','Acceso restringido','fallo_entrega',TRUE,FALSE,TRUE),
('sin_pago','Falta de pago (COD)','fallo_entrega',TRUE,TRUE,TRUE),
('zona_peligrosa','Zona insegura','fallo_entrega',TRUE,FALSE,TRUE),
('fuera_horario','Fuera de ventana horaria','fallo_entrega',TRUE,FALSE,TRUE),
('documento_faltante','Documentación incompleta','fallo_recogida',TRUE,TRUE,TRUE);

CREATE TABLE operations_viaje_visitas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  parada_id UUID REFERENCES operations_paradas(id),
  orden INTEGER NOT NULL DEFAULT 0,
  estado VARCHAR(30) DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente','llego','en_proceso','completada','omitida')),
  hora_llegada TIMESTAMPTZ, hora_salida TIMESTAMPTZ,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_visitas_viaje ON operations_viaje_visitas(viaje_id, orden) WHERE deleted_at IS NULL;

CREATE TABLE operations_visita_operaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  visita_id UUID NOT NULL REFERENCES operations_viaje_visitas(id) ON DELETE CASCADE,
  paquete_id UUID REFERENCES shipping_paquetes(id),
  tipo_id UUID REFERENCES operations_tipos_operacion(id),
  estado_id UUID REFERENCES operations_estados_operacion(id),
  orden INTEGER DEFAULT 0,
  total_intentos INTEGER DEFAULT 0,
  max_intentos INTEGER DEFAULT 3,
  ejecucion_exitosa_id UUID, -- FK diferida abajo
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID, deleted_at TIMESTAMPTZ, deleted_by UUID
);
CREATE INDEX idx_operaciones_visita ON operations_visita_operaciones(visita_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_operaciones_paquete ON operations_visita_operaciones(paquete_id);
COMMENT ON TABLE operations_visita_operaciones IS
  'OPERACIÓN: QUÉ debe hacerse con un paquete en una visita. Inmutable en intención.';

CREATE TABLE operations_operacion_ejecuciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  operacion_id UUID NOT NULL REFERENCES operations_visita_operaciones(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id),
  visita_id UUID NOT NULL REFERENCES operations_viaje_visitas(id),
  paquete_id UUID REFERENCES shipping_paquetes(id),
  numero_intento INTEGER NOT NULL DEFAULT 1,
  resultado VARCHAR(30) NOT NULL DEFAULT 'en_proceso'
    CHECK (resultado IN ('en_proceso','exitosa','fallida','parcial','cancelada')),
  motivo_id UUID REFERENCES operations_motivos(id),
  iniciada_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalizada_en TIMESTAMPTZ,
  duracion_segundos INTEGER GENERATED ALWAYS AS (
    CASE WHEN finalizada_en IS NOT NULL
      THEN EXTRACT(EPOCH FROM (finalizada_en - iniciada_en))::INTEGER
      ELSE NULL END
  ) STORED,
  conductor_id UUID REFERENCES fleet_conductores(id),
  usuario_id UUID REFERENCES core_usuarios(id),
  dispositivo_id UUID REFERENCES fleet_dispositivos_gps(id),
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  precision_gps_m DECIMAL(5,2),
  offline BOOLEAN DEFAULT FALSE,
  sincronizada_en TIMESTAMPTZ,
  client_operation_id UUID,
  firma_verificada BOOLEAN DEFAULT FALSE,
  otp_verificado BOOLEAN DEFAULT FALSE,
  escaneo_verificado BOOLEAN DEFAULT FALSE,
  receptor_nombre VARCHAR(255), receptor_documento VARCHAR(20), receptor_relacion VARCHAR(50),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, updated_by UUID,
  CONSTRAINT uq_ejecucion_operacion_intento UNIQUE (operacion_id, numero_intento),
  CONSTRAINT uq_ejecucion_client_op UNIQUE (client_operation_id)
);
CREATE INDEX idx_ejec_operacion ON operations_operacion_ejecuciones(operacion_id);
CREATE INDEX idx_ejec_offline ON operations_operacion_ejecuciones(offline)
  WHERE offline = TRUE AND sincronizada_en IS NULL;
COMMENT ON TABLE operations_operacion_ejecuciones IS
  'EJECUCIÓN: cada intento real. Append-only tras finalizar.';

-- FK circular segura
ALTER TABLE operations_visita_operaciones
  ADD CONSTRAINT fk_op_ejecucion_exitosa
  FOREIGN KEY (ejecucion_exitosa_id) REFERENCES operations_operacion_ejecuciones(id)
  ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Anti-mutación de ejecuciones finalizadas
CREATE OR REPLACE FUNCTION public.fn_prevent_ejecucion_final_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.finalizada_en IS NOT NULL THEN
    IF NEW.resultado        IS DISTINCT FROM OLD.resultado
    OR NEW.motivo_id        IS DISTINCT FROM OLD.motivo_id
    OR NEW.finalizada_en    IS DISTINCT FROM OLD.finalizada_en
    OR NEW.latitud          IS DISTINCT FROM OLD.latitud
    OR NEW.longitud         IS DISTINCT FROM OLD.longitud
    OR NEW.receptor_nombre  IS DISTINCT FROM OLD.receptor_nombre THEN
      RAISE EXCEPTION 'No se puede modificar una ejecución ya finalizada';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_prevent_ejecucion_final_mutation
  BEFORE UPDATE ON operations_operacion_ejecuciones
  FOR EACH ROW EXECUTE FUNCTION fn_prevent_ejecucion_final_mutation();

CREATE TABLE operations_evidencias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  ejecucion_id UUID REFERENCES operations_operacion_ejecuciones(id) ON DELETE CASCADE,
  operacion_id UUID REFERENCES operations_visita_operaciones(id),
  viaje_id UUID REFERENCES operations_viajes(id),
  paquete_id UUID REFERENCES shipping_paquetes(id),
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN (
    'foto','firma','audio','video','pdf','scan','documento','otp_log','temperatura','ubicacion'
  )),
  url TEXT,
  valor JSONB DEFAULT '{}'::jsonb,
  bucket VARCHAR(100), ruta_archivo TEXT,
  mime_type VARCHAR(100), tamano_bytes BIGINT, hash_sha256 VARCHAR(64),
  descripcion TEXT, orden INTEGER DEFAULT 0,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  capturada_en TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(), created_by UUID, deleted_at TIMESTAMPTZ,
  CONSTRAINT chk_evidencia_contenido CHECK (url IS NOT NULL OR valor <> '{}'::jsonb)
);
CREATE INDEX idx_evidencias_ejecucion ON operations_evidencias(ejecucion_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_evidencias_paquete ON operations_evidencias(paquete_id) WHERE deleted_at IS NULL;

CREATE TABLE operations_custodia (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  paquete_id UUID NOT NULL REFERENCES shipping_paquetes(id) ON DELETE CASCADE,
  secuencia INTEGER NOT NULL,
  custodio_tipo VARCHAR(30) NOT NULL CHECK (custodio_tipo IN (
    'almacen','conductor','hub','cliente','tercero','punto_recogida'
  )),
  custodio_id UUID,
  custodio_nombre VARCHAR(255),
  viaje_id UUID REFERENCES operations_viajes(id),
  ejecucion_id UUID REFERENCES operations_operacion_ejecuciones(id),
  recibido_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  entregado_en TIMESTAMPTZ,
  latitud DECIMAL(10,8) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud DECIMAL(11,8) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  ubicacion GEOGRAPHY(POINT, 4326),
  estado_fisico VARCHAR(30) DEFAULT 'integro'
    CHECK (estado_fisico IN ('integro','dañado','mojado','abierto','incompleto')),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(), created_by UUID,
  CONSTRAINT uq_custodia_paquete_secuencia UNIQUE (paquete_id, secuencia),
  CONSTRAINT chk_custodia_periodo CHECK (entregado_en IS NULL OR entregado_en > recibido_en),
  CONSTRAINT ex_custodia_no_overlap EXCLUDE USING gist (
    paquete_id WITH =,
    tstzrange(recibido_en, COALESCE(entregado_en, 'infinity'::timestamptz), '[)') WITH &&
  )
);
-- Una sola custodia actual por paquete
CREATE UNIQUE INDEX uq_custodia_actual_paquete ON operations_custodia(paquete_id)
  WHERE entregado_en IS NULL;

CREATE TABLE operations_restricciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  referencia_tipo VARCHAR(30) NOT NULL
    CHECK (referencia_tipo IN ('paquete','direccion','cliente','visita','vehiculo')),
  referencia_id UUID NOT NULL,
  tipo VARCHAR(50) NOT NULL CHECK (tipo IN (
    'temperatura','adr','fragil','ventana_horaria','acceso_restringido',
    'requiere_grua','no_escaleras','peso_maximo','tipo_vehiculo',
    'requiere_hidraulica','zona_peaton','altura_maxima'
  )),
  valor JSONB NOT NULL DEFAULT '{}'::jsonb,
  es_dura BOOLEAN DEFAULT TRUE,
  penalizacion INTEGER DEFAULT 0,
  activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_restricciones_ref ON operations_restricciones(referencia_tipo, referencia_id)
  WHERE activa = TRUE;

CREATE TABLE planning_optimizaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  algoritmo VARCHAR(50) NOT NULL CHECK (algoritmo IN (
    'manual','google_or_tools','ortools_vrp','vroom','osrm',
    'ia_propietaria','nearest_neighbor','clarke_wright'
  )),
  version_algoritmo VARCHAR(20),
  version_plan INTEGER NOT NULL DEFAULT 1,
  parametros JSONB, input_snapshot JSONB,
  distancia_total_km DECIMAL(10,2), tiempo_total_min INTEGER,
  costo_estimado DECIMAL(12,2), paradas_reordenadas INTEGER,
  score_calidad DECIMAL(5,2), mejora_vs_anterior_pct DECIMAL(5,2),
  duracion_computo_ms INTEGER,
  aplicada BOOLEAN DEFAULT FALSE, aplicada_en TIMESTAMPTZ,
  aplicada_por UUID REFERENCES core_usuarios(id),
  created_at TIMESTAMPTZ DEFAULT NOW(), created_by UUID
);
CREATE INDEX idx_optim_viaje ON planning_optimizaciones(viaje_id, version_plan);

-- ============================================================================
-- 14. OUTBOX / INBOX (solo service_role)
-- ============================================================================
CREATE TABLE integration_outbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  aggregate_type VARCHAR(50) NOT NULL,
  aggregate_id UUID NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  destino VARCHAR(50),
  status VARCHAR(20) NOT NULL DEFAULT 'pendiente'
    CHECK (status IN ('pendiente','publicando','publicado','fallido','descartado')),
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 5,
  next_retry_at TIMESTAMPTZ,
  last_error TEXT,
  idempotency_key VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  CONSTRAINT uq_outbox_idempotency UNIQUE (idempotency_key)
);
CREATE INDEX idx_outbox_pendientes ON integration_outbox(created_at)
  WHERE status IN ('pendiente','fallido');

CREATE TABLE integration_inbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id),
  origen VARCHAR(50) NOT NULL,
  external_id VARCHAR(255) NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) DEFAULT 'recibido'
    CHECK (status IN ('recibido','procesando','procesado','fallido','duplicado')),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_inbox_origen_external UNIQUE (origen, external_id)
);

ALTER TABLE integration_outbox DISABLE ROW LEVEL SECURITY;
ALTER TABLE integration_inbox  DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON integration_outbox FROM anon, authenticated;
REVOKE ALL ON integration_inbox  FROM anon, authenticated;

-- ============================================================================
-- 15. TRIGGERS AUTOMÁTICOS (mejora: bloques DO en lugar de 40 declaraciones)
-- ============================================================================
-- 15.1 updated_at en toda tabla que tenga la columna
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_name = c.table_name AND t.table_schema = 'public'
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public' AND c.column_name = 'updated_at'
    GROUP BY c.table_name
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_updated_at ON %I', r.table_name);
    EXECUTE format(
      'CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()', r.table_name);
  END LOOP;
END $$;

-- 15.2 ubicacion desde lat/lon en toda tabla con las tres columnas
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name IN ('latitud','longitud','ubicacion')
    GROUP BY table_name HAVING COUNT(DISTINCT column_name) = 3
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_set_ubicacion ON %I', r.table_name);
    EXECUTE format(
      'CREATE TRIGGER trg_set_ubicacion BEFORE INSERT OR UPDATE OF latitud, longitud ON %I
       FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon()', r.table_name);
  END LOOP;
END $$;

-- ============================================================================
-- 16. AUDITORÍA AUTOMÁTICA (versión corregida: maneja DELETE)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_auditoria_general()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit_auditoria (empresa_id, usuario_id, accion, tabla_afectada, registro_id, datos_antes, datos_despues)
    VALUES (NEW.empresa_id, NEW.created_by, 'INSERT', TG_TABLE_NAME, NEW.id, NULL, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_auditoria (empresa_id, usuario_id, accion, tabla_afectada, registro_id, datos_antes, datos_despues)
    VALUES (COALESCE(NEW.empresa_id, OLD.empresa_id), COALESCE(NEW.updated_by, OLD.updated_by),
            'UPDATE', TG_TABLE_NAME, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO audit_auditoria (empresa_id, usuario_id, accion, tabla_afectada, registro_id, datos_antes, datos_despues)
    VALUES (OLD.empresa_id, OLD.updated_by, 'DELETE', TG_TABLE_NAME, OLD.id, to_jsonb(OLD), NULL);
    RETURN OLD;
  END IF;
  RETURN NULL;
END $$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'shipping_paquetes','shipping_envios','shipping_tipos_paquete',
    'operations_viajes','operations_viajes_paquetes','operations_asignaciones',
    'operations_operacion_ejecuciones','delivery_entregas'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_auditoria ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
       FOR EACH ROW EXECUTE FUNCTION fn_auditoria_general()', t);
  END LOOP;
END $$;

-- ============================================================================
-- 17. TRIGGERS DE NEGOCIO
-- ============================================================================
-- Auto-generar checkpoints al asignar ruta al viaje
CREATE OR REPLACE FUNCTION public.fn_auto_generate_checkpoints()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.ruta_id IS NULL THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM operations_checkpoints WHERE viaje_id = NEW.id AND deleted_at IS NULL) THEN
    RETURN NEW;
  END IF;
  INSERT INTO operations_checkpoints (empresa_id, viaje_id, parada_id, estado, latitud, longitud)
  SELECT NEW.empresa_id, NEW.id, p.id, 'pendiente', p.latitud, p.longitud
  FROM operations_paradas p
  WHERE p.ruta_id = NEW.ruta_id AND p.deleted_at IS NULL
  ORDER BY p.orden;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_auto_generate_checkpoints
  AFTER INSERT OR UPDATE OF ruta_id ON operations_viajes
  FOR EACH ROW
  WHEN (NEW.ruta_id IS NOT NULL AND NEW.deleted_at IS NULL)
  EXECUTE FUNCTION fn_auto_generate_checkpoints();

-- Auto-generar visitas (nuevo modelo)
CREATE OR REPLACE FUNCTION public.fn_generar_visitas_operaciones()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.ruta_id IS NULL THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM operations_viaje_visitas WHERE viaje_id = NEW.id AND deleted_at IS NULL) THEN
    RETURN NEW;
  END IF;
  INSERT INTO operations_viaje_visitas (empresa_id, viaje_id, parada_id, orden, latitud, longitud)
  SELECT NEW.empresa_id, NEW.id, p.id, p.orden, p.latitud, p.longitud
  FROM operations_paradas p
  WHERE p.ruta_id = NEW.ruta_id AND p.deleted_at IS NULL
  ORDER BY p.orden;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_generar_visitas_operaciones
  AFTER INSERT OR UPDATE OF ruta_id ON operations_viajes
  FOR EACH ROW
  WHEN (NEW.ruta_id IS NOT NULL AND NEW.deleted_at IS NULL)
  EXECUTE FUNCTION fn_generar_visitas_operaciones();

-- ============================================================================
-- 18. FUNCIONES DE NEGOCIO (todas con search_path + autorización)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.generar_tracking_number()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_trk TEXT; v_existe BOOLEAN;
BEGIN
  LOOP
    v_trk := 'TRK' || TO_CHAR(NOW(), 'YYYYMMDD') ||
             LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    SELECT EXISTS(SELECT 1 FROM shipping_paquetes WHERE tracking_number = v_trk) INTO v_existe;
    EXIT WHEN NOT v_existe;
  END LOOP;
  RETURN v_trk;
END $$;

CREATE OR REPLACE FUNCTION public.calcular_distancia_km(
  lat1 DECIMAL, lon1 DECIMAL, lat2 DECIMAL, lon2 DECIMAL
) RETURNS DECIMAL LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp AS $$
  SELECT ST_Distance(
    ST_SetSRID(ST_MakePoint(lon1, lat1), 4326)::geography,
    ST_SetSRID(ST_MakePoint(lon2, lat2), 4326)::geography
  ) / 1000;
$$;

-- Registro empresa + usuario (única función accesible por anon)
CREATE OR REPLACE FUNCTION public.registrar_empresa_usuario(
  p_auth_user_id UUID, p_email VARCHAR, p_nombre VARCHAR, p_apellido VARCHAR,
  p_telefono VARCHAR DEFAULT NULL, p_rol_nombre VARCHAR DEFAULT 'Administrador',
  p_mode VARCHAR DEFAULT 'new_company', p_company_name VARCHAR DEFAULT NULL,
  p_company_ruc VARCHAR DEFAULT NULL, p_invite_code VARCHAR DEFAULT NULL
) RETURNS TABLE (success BOOLEAN, empresa_id UUID, usuario_id UUID, message TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_empresa_id UUID; v_usuario_id UUID; v_rol_id UUID;
BEGIN
  IF p_auth_user_id IS NULL OR p_email IS NULL OR p_nombre IS NULL OR p_apellido IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Faltan campos obligatorios'; RETURN;
  END IF;

  SELECT id INTO v_rol_id FROM core_roles
  WHERE nombre = p_rol_nombre AND es_sistema = TRUE LIMIT 1;

  IF p_mode = 'new_company' THEN
    IF p_company_name IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Nombre de empresa es obligatorio'; RETURN;
    END IF;
    INSERT INTO core_empresas (nombre, ruc, email, estado)
    VALUES (p_company_name, p_company_ruc, p_email, 'activo')
    RETURNING id INTO v_empresa_id;
  ELSIF p_mode = 'join_company' THEN
    IF p_invite_code IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Código de invitación requerido'; RETURN;
    END IF;
    SELECT id INTO v_empresa_id FROM core_empresas
    WHERE ruc = p_invite_code AND estado = 'activo' AND deleted_at IS NULL LIMIT 1;
    IF v_empresa_id IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Código de invitación no válido'; RETURN;
    END IF;
  ELSE
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Modo inválido'; RETURN;
  END IF;

  INSERT INTO core_usuarios (auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo)
  VALUES (p_auth_user_id, v_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE)
  RETURNING id INTO v_usuario_id;

  RETURN QUERY SELECT TRUE, v_empresa_id, v_usuario_id, 'Registro exitoso';
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, SQLERRM;
END $$;

-- Registro de conductor (endurecida: valida empresa del solicitante)
CREATE OR REPLACE FUNCTION public.registrar_conductor(
  p_empresa_id UUID, p_nombre VARCHAR, p_apellido VARCHAR, p_email VARCHAR,
  p_password VARCHAR, p_licencia VARCHAR, p_telefono VARCHAR DEFAULT NULL,
  p_tipo_licencia VARCHAR DEFAULT NULL, p_vencimiento_licencia DATE DEFAULT NULL,
  p_auth_user_id UUID DEFAULT NULL
) RETURNS TABLE (success BOOLEAN, conductor_id UUID, usuario_id UUID, auth_user_id UUID, message TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_conductor_id UUID; v_usuario_id UUID; v_rol_id UUID;
BEGIN
  -- Autorización: solo usuarios de esa empresa
  IF auth.uid() IS NOT NULL
     AND public.user_empresa_id() IS DISTINCT FROM p_empresa_id THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'No autorizado para registrar conductores en esta empresa'::TEXT; RETURN;
  END IF;

  IF p_empresa_id IS NULL OR p_nombre IS NULL OR p_apellido IS NULL
     OR p_email IS NULL OR p_licencia IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Faltan campos obligatorios'::TEXT; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM fleet_conductores
             WHERE empresa_id = p_empresa_id AND licencia = p_licencia AND deleted_at IS NULL) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Ya existe un conductor con esa licencia'::TEXT; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM core_usuarios WHERE email = p_email AND deleted_at IS NULL) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Ya existe un usuario con ese email'::TEXT; RETURN;
  END IF;

  IF p_auth_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'Se requiere auth_user_id (crear usuario en auth.users primero)'::TEXT; RETURN;
  END IF;

  SELECT id INTO v_rol_id FROM core_roles WHERE nombre = 'Chofer' AND es_sistema = TRUE LIMIT 1;

  INSERT INTO fleet_conductores (empresa_id, licencia, tipo_licencia, vencimiento_licencia, telefono, estado)
  VALUES (p_empresa_id, p_licencia, p_tipo_licencia, p_vencimiento_licencia, p_telefono, 'disponible')
  RETURNING id INTO v_conductor_id;

  INSERT INTO core_usuarios (auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo)
  VALUES (p_auth_user_id, p_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE)
  RETURNING id INTO v_usuario_id;

  UPDATE fleet_conductores SET usuario_id = v_usuario_id WHERE id = v_conductor_id;

  RETURN QUERY SELECT TRUE, v_conductor_id, v_usuario_id, p_auth_user_id, 'Conductor registrado exitosamente'::TEXT;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, SQLERRM::TEXT;
END $$;

-- Guardar geocerca (endurecida)
CREATE OR REPLACE FUNCTION public.guardar_geocerca(
  p_id UUID DEFAULT NULL, p_empresa_id UUID DEFAULT NULL,
  p_nombre VARCHAR DEFAULT NULL, p_tipo VARCHAR DEFAULT 'circulo',
  p_latitud DOUBLE PRECISION DEFAULT NULL, p_longitud DOUBLE PRECISION DEFAULT NULL,
  p_radio INTEGER DEFAULT NULL, p_color VARCHAR DEFAULT '#3B82F6',
  p_activa BOOLEAN DEFAULT TRUE, p_poligono JSONB DEFAULT NULL
) RETURNS TABLE (success BOOLEAN, geocerca_id UUID, message TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id UUID; v_centro GEOGRAPHY; v_poly GEOMETRY(POLYGON, 4326);
BEGIN
  IF auth.uid() IS NOT NULL AND p_empresa_id IS NOT NULL
     AND public.user_empresa_id() IS DISTINCT FROM p_empresa_id THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'No autorizado'::TEXT; RETURN;
  END IF;
  IF p_nombre IS NULL OR p_nombre = '' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'El nombre es obligatorio'; RETURN;
  END IF;
  IF p_tipo NOT IN ('circulo','poligono') THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'Tipo de geocerca inválido'; RETURN;
  END IF;

  IF p_latitud IS NOT NULL AND p_longitud IS NOT NULL THEN
    v_centro := ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography;
  END IF;

  IF p_tipo = 'poligono' AND p_poligono IS NOT NULL THEN
    v_poly := ST_SetSRID(ST_GeomFromText(
      'POLYGON((' || (
        SELECT string_agg(lng || ' ' || lat, ', ')
        FROM jsonb_array_elements(p_poligono->'coordinates'->0) AS coord
        CROSS JOIN LATERAL (
          SELECT (coord->>0)::double precision AS lng, (coord->>1)::double precision AS lat
        ) AS p
      ) || ', ' || (
        SELECT (coord->>0)::double precision || ' ' || (coord->>1)::double precision
        FROM jsonb_array_elements(p_poligono->'coordinates'->0) AS coord LIMIT 1
      ) || '))'
    ), 4326);
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE operations_geocercas SET
      nombre = p_nombre, tipo = p_tipo,
      radio    = CASE WHEN p_tipo = 'circulo'  THEN p_radio ELSE NULL END,
      poligono = CASE WHEN p_tipo = 'poligono' THEN v_poly  ELSE NULL END,
      centro   = CASE WHEN p_tipo = 'circulo'  THEN COALESCE(v_centro, centro) ELSE NULL END,
      color = p_color, activa = p_activa, updated_at = NOW()
    WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RETURN QUERY SELECT FALSE, NULL::UUID, 'Geocerca no encontrada'; RETURN;
    END IF;
    RETURN QUERY SELECT TRUE, v_id, 'Geocerca actualizada correctamente'; RETURN;
  END IF;

  IF p_empresa_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'empresa_id es obligatorio para crear'; RETURN;
  END IF;

  INSERT INTO operations_geocercas (empresa_id, nombre, tipo, radio, poligono, centro, color, activa)
  VALUES (
    p_empresa_id, p_nombre, p_tipo,
    CASE WHEN p_tipo = 'circulo'  THEN p_radio ELSE NULL END,
    CASE WHEN p_tipo = 'poligono' THEN v_poly  ELSE NULL END,
    CASE WHEN p_tipo = 'circulo'  THEN v_centro ELSE NULL END,
    p_color, p_activa
  ) RETURNING id INTO v_id;

  RETURN QUERY SELECT TRUE, v_id, 'Geocerca creada correctamente';
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, SQLERRM;
END $$;

-- Outbox con idempotencia estable
CREATE OR REPLACE FUNCTION public.publicar_evento_outbox(
  p_empresa_id UUID, p_aggregate_type VARCHAR, p_aggregate_id UUID,
  p_event_type VARCHAR, p_payload JSONB,
  p_destino VARCHAR DEFAULT NULL, p_idempotency_key VARCHAR DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_id UUID; v_key VARCHAR(255);
BEGIN
  v_key := COALESCE(
    p_idempotency_key,
    p_aggregate_type || ':' || p_aggregate_id::text || ':' || p_event_type || ':' ||
    COALESCE(p_payload->>'event_id', p_payload->>'version',
             encode(digest(p_payload::text, 'sha256'), 'hex'))
  );
  INSERT INTO integration_outbox (empresa_id, aggregate_type, aggregate_id, event_type, payload, destino, idempotency_key)
  VALUES (p_empresa_id, p_aggregate_type, p_aggregate_id, p_event_type, p_payload, p_destino, v_key)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM integration_outbox WHERE idempotency_key = v_key;
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.integration_dequeue_outbox(p_limit INTEGER DEFAULT 100)
RETURNS SETOF integration_outbox LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
  WITH pendientes AS (
    SELECT id FROM integration_outbox
    WHERE status IN ('pendiente','fallido')
      AND retry_count < max_retries
      AND (next_retry_at IS NULL OR next_retry_at <= NOW())
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE integration_outbox o SET status = 'publicando'
  FROM pendientes p WHERE o.id = p.id
  RETURNING o.*;
$$;

CREATE OR REPLACE FUNCTION public.integration_mark_published(p_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE integration_outbox SET status = 'publicado', published_at = NOW() WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.integration_mark_failed(p_id UUID, p_error TEXT)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE integration_outbox SET
    status = 'fallido',
    retry_count = retry_count + 1,
    last_error = p_error,
    next_retry_at = NOW() + (INTERVAL '1 minute' * POWER(2, LEAST(retry_count, 10)))
  WHERE id = p_id;
$$;

-- Función núcleo: registrar ejecución (bloqueo + autorización + outbox)
CREATE OR REPLACE FUNCTION public.registrar_ejecucion(
  p_operacion_id UUID, p_resultado VARCHAR,
  p_conductor_id UUID DEFAULT NULL, p_motivo_codigo VARCHAR DEFAULT NULL,
  p_latitud DECIMAL DEFAULT NULL, p_longitud DECIMAL DEFAULT NULL,
  p_receptor_nombre VARCHAR DEFAULT NULL, p_client_operation_id UUID DEFAULT NULL,
  p_offline BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
  success BOOLEAN, ejecucion_id UUID, operacion_completada BOOLEAN,
  intentos_restantes INTEGER, message TEXT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_op RECORD; v_ejecucion_id UUID; v_numero_intento INTEGER;
  v_motivo_id UUID; v_empresa_id UUID;
  v_estado_completada UUID; v_estado_fallida UUID; v_restantes INTEGER;
BEGIN
  -- 1) Idempotencia
  IF p_client_operation_id IS NOT NULL THEN
    SELECT id INTO v_ejecucion_id FROM operations_operacion_ejecuciones
    WHERE client_operation_id = p_client_operation_id;
    IF v_ejecucion_id IS NOT NULL THEN
      RETURN QUERY SELECT TRUE, v_ejecucion_id, FALSE, 0, 'Ejecución ya registrada (idempotente)'::TEXT;
      RETURN;
    END IF;
  END IF;

  -- 2) Bloqueo anti-carrera
  SELECT * INTO v_op FROM operations_visita_operaciones
  WHERE id = p_operacion_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, 'Operación no encontrada'::TEXT; RETURN;
  END IF;
  v_empresa_id := v_op.empresa_id;

  -- 3) Autorización explícita
  IF auth.uid() IS NOT NULL AND public.user_empresa_id() IS DISTINCT FROM v_empresa_id THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, 'No autorizado para esta operación'::TEXT; RETURN;
  END IF;

  -- 4) Ya completada
  IF v_op.ejecucion_exitosa_id IS NOT NULL THEN
    RETURN QUERY SELECT FALSE, v_op.ejecucion_exitosa_id, TRUE, 0, 'La operación ya fue completada'::TEXT; RETURN;
  END IF;

  v_numero_intento := v_op.total_intentos + 1;

  -- 5) Límite de intentos
  IF v_numero_intento > v_op.max_intentos AND p_resultado <> 'exitosa' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, 'Se agotaron los intentos permitidos'::TEXT; RETURN;
  END IF;

  -- 6) Resolver motivo (prefiere el de la empresa sobre el global)
  IF p_motivo_codigo IS NOT NULL THEN
    SELECT id INTO v_motivo_id FROM operations_motivos
    WHERE codigo = p_motivo_codigo AND (empresa_id IS NULL OR empresa_id = v_empresa_id)
    ORDER BY empresa_id NULLS LAST LIMIT 1;
  END IF;

  -- 7) Crear ejecución
  INSERT INTO operations_operacion_ejecuciones (
    empresa_id, operacion_id, viaje_id, visita_id, paquete_id,
    numero_intento, resultado, motivo_id, conductor_id,
    latitud, longitud, receptor_nombre, client_operation_id, offline,
    finalizada_en, sincronizada_en, created_by
  ) VALUES (
    v_empresa_id, p_operacion_id, v_op.viaje_id, v_op.visita_id, v_op.paquete_id,
    v_numero_intento, p_resultado, v_motivo_id, p_conductor_id,
    p_latitud, p_longitud, p_receptor_nombre, p_client_operation_id, p_offline,
    NOW(), CASE WHEN p_offline THEN NULL ELSE NOW() END,
    (SELECT id FROM core_usuarios WHERE auth_user_id = auth.uid() LIMIT 1)
  ) RETURNING id INTO v_ejecucion_id;

  -- 8) Contador
  UPDATE operations_visita_operaciones
  SET total_intentos = v_numero_intento, updated_at = NOW()
  WHERE id = p_operacion_id;

  -- 9) Cierre + outbox
  IF p_resultado = 'exitosa' THEN
    SELECT id INTO v_estado_completada FROM operations_estados_operacion
    WHERE codigo = 'completada' AND es_sistema = TRUE;

    UPDATE operations_visita_operaciones
    SET estado_id = v_estado_completada, ejecucion_exitosa_id = v_ejecucion_id, updated_at = NOW()
    WHERE id = p_operacion_id;

    PERFORM public.publicar_evento_outbox(
      v_empresa_id, 'paquete', v_op.paquete_id, 'paquete.operacion_completada',
      jsonb_build_object(
        'operacion_id', p_operacion_id, 'ejecucion_id', v_ejecucion_id,
        'paquete_id', v_op.paquete_id, 'viaje_id', v_op.viaje_id
      ),
      NULL,
      'paquete:' || v_op.paquete_id::text || ':operacion_completada:' || v_ejecucion_id::text
    );
  ELSIF v_numero_intento >= v_op.max_intentos AND p_resultado = 'fallida' THEN
    SELECT id INTO v_estado_fallida FROM operations_estados_operacion
    WHERE codigo = 'fallida' AND es_sistema = TRUE;
    UPDATE operations_visita_operaciones
    SET estado_id = v_estado_fallida, updated_at = NOW()
    WHERE id = p_operacion_id;
  END IF;

  v_restantes := GREATEST(v_op.max_intentos - v_numero_intento, 0);
  RETURN QUERY SELECT TRUE, v_ejecucion_id, (p_resultado = 'exitosa'), v_restantes,
    CASE WHEN p_resultado = 'exitosa' THEN 'Operación completada exitosamente'
         ELSE 'Intento registrado. Reintentos restantes: ' || v_restantes END::TEXT;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, SQLERRM::TEXT;
END $$;

-- Consulta de custodia en un momento dado
CREATE OR REPLACE FUNCTION public.custodia_en_momento(p_paquete_id UUID, p_momento TIMESTAMPTZ)
RETURNS TABLE (custodio_tipo VARCHAR, custodio_nombre VARCHAR, recibido_en TIMESTAMPTZ, entregado_en TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT c.custodio_tipo, c.custodio_nombre, c.recibido_en, c.entregado_en
  FROM operations_custodia c
  WHERE c.paquete_id = p_paquete_id
    AND c.recibido_en <= p_momento
    AND (c.entregado_en IS NULL OR c.entregado_en > p_momento)
  ORDER BY c.secuencia DESC LIMIT 1;
$$;

-- ============================================================================
-- 19. VISTAS (security_invoker: respetan RLS)
-- ============================================================================
CREATE VIEW v_paquetes_completo WITH (security_invoker = true) AS
SELECT p.*,
  c.nombre AS cliente_nombre,
  e.nombre AS estado_nombre, e.color AS estado_color,
  r.nombre AS remitente_nombre, d.nombre AS destinatario_nombre
FROM shipping_paquetes p
LEFT JOIN customers_clientes c ON p.cliente_id = c.id
LEFT JOIN shipping_estados_envio e ON p.estado_actual = e.id
LEFT JOIN customers_remitentes r ON p.remitente_id = r.id
LEFT JOIN customers_destinatarios d ON p.destinatario_id = d.id
WHERE p.deleted_at IS NULL;

CREATE VIEW v_viajes_activos WITH (security_invoker = true) AS
SELECT v.*,
  cond.nombre || ' ' || cond.apellido AS conductor_nombre,
  cond.telefono AS conductor_telefono,
  veh.matricula,
  veh.marca || ' ' || veh.modelo AS vehiculo_descripcion,
  r.nombre AS ruta_nombre
FROM operations_viajes v
LEFT JOIN operations_viajes_conductores vjc
  ON v.id = vjc.viaje_id AND vjc.principal = TRUE AND vjc.deleted_at IS NULL
LEFT JOIN fleet_conductores fc ON vjc.conductor_id = fc.id
LEFT JOIN core_usuarios cond ON fc.usuario_id = cond.id
LEFT JOIN operations_viajes_vehiculos vjv
  ON v.id = vjv.viaje_id AND vjv.principal = TRUE AND vjv.deleted_at IS NULL
LEFT JOIN fleet_vehiculos veh ON vjv.vehiculo_id = veh.id
LEFT JOIN operations_rutas r ON v.ruta_id = r.id
WHERE v.deleted_at IS NULL AND v.estado IN ('programado','en_curso');

CREATE VIEW v_ultima_posicion_gps WITH (security_invoker = true) AS
SELECT vehiculo_id, empresa_id, viaje_id, conductor_id,
       latitud, longitud, velocidad_kmh, bateria, internet, gps, created_at
FROM tracking_ultima_posicion;

CREATE OR REPLACE VIEW v_kpi_first_attempt WITH (security_invoker = true) AS
SELECT
  op.empresa_id, op.viaje_id, DATE(e.iniciada_en) AS fecha,
  COUNT(DISTINCT op.id) AS total_operaciones,
  COUNT(DISTINCT op.id) FILTER (
    WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
  ) AS exitosas_primer_intento,
  COUNT(DISTINCT op.id) FILTER (WHERE op.ejecucion_exitosa_id IS NOT NULL) AS exitosas_total,
  ROUND(100.0 * COUNT(DISTINCT op.id) FILTER (
      WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
    ) / NULLIF(COUNT(DISTINCT op.id) FILTER (WHERE op.ejecucion_exitosa_id IS NOT NULL), 0), 2
  ) AS first_attempt_success_among_successful_pct,
  ROUND(100.0 * COUNT(DISTINCT op.id) FILTER (
      WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
    ) / NULLIF(COUNT(DISTINCT op.id), 0), 2
  ) AS first_attempt_success_among_attempted_pct,
  AVG(e.duracion_segundos) FILTER (WHERE e.resultado = 'exitosa') AS duracion_promedio_seg
FROM operations_visita_operaciones op
JOIN operations_operacion_ejecuciones e ON e.operacion_id = op.id
WHERE op.deleted_at IS NULL
GROUP BY op.empresa_id, op.viaje_id, DATE(e.iniciada_en);

-- ============================================================================
-- 20. RLS
-- ============================================================================
-- 20.1 Política estándar para todas las tablas con empresa_id directo
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'core_sucursales','core_configuraciones',
    'fleet_dispositivos_gps','fleet_vehiculos','fleet_remolques','fleet_conductores',
    'fleet_mantenimientos','fleet_checklists','fleet_capacidades',
    'customers_clientes','customers_direcciones','customers_remitentes','customers_destinatarios',
    'operations_geocercas','operations_geocercas_vinculos','operations_rutas',
    'operations_rutas_optimizadas','operations_viajes','operations_asignaciones',
    'operations_viaje_visitas','operations_visita_operaciones',
    'operations_operacion_ejecuciones','operations_evidencias','operations_custodia',
    'operations_restricciones','planning_optimizaciones',
    'shipping_envios','shipping_paquetes','shipping_cargas','shipping_carga_evidencias',
    'tracking_alertas','tracking_sesiones','tracking_eventos',
    'delivery_firmas','delivery_entregas','delivery_incidencias','delivery_fotografias',
    'delivery_sesiones','communication_chats','storage_documentos'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "empresa_all" ON %I', t);
    EXECUTE format(
      'CREATE POLICY "empresa_all" ON %I FOR ALL
       USING (empresa_id = public.user_empresa_id())
       WITH CHECK (empresa_id = public.user_empresa_id())', t);
  END LOOP;
END $$;

-- 20.2 Tablas hijas (acceso a través del padre)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('operations_paradas',            'ruta_id',      'operations_rutas'),
    ('operations_checkpoints',        'viaje_id',     'operations_viajes'),
    ('operations_eta',                'viaje_id',     'operations_viajes'),
    ('operations_viajes_conductores', 'viaje_id',     'operations_viajes'),
    ('operations_viajes_vehiculos',   'viaje_id',     'operations_viajes'),
    ('operations_viajes_paquetes',    'viaje_id',     'operations_viajes'),
    ('operations_viajes_eventos',     'viaje_id',     'operations_viajes'),
    ('fleet_checklists_items',        'checklist_id', 'fleet_checklists'),
    ('shipping_paquetes_cargas',      'carga_id',     'shipping_cargas'),
    ('shipping_historial_estados',    'paquete_id',   'shipping_paquetes'),
    ('communication_chat_mensajes',   'chat_id',      'communication_chats')
  ) AS x(tabla, col, padre)
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', r.tabla);
    EXECUTE format('DROP POLICY IF EXISTS "empresa_via_padre" ON %I', r.tabla);
    EXECUTE format(
      'CREATE POLICY "empresa_via_padre" ON %I FOR ALL USING (
         %I IN (SELECT id FROM %I WHERE empresa_id = public.user_empresa_id())
       )', r.tabla, r.col, r.padre);
  END LOOP;
END $$;

-- 20.3 Políticas especiales
-- core_empresas
ALTER TABLE core_empresas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "empresas_insert_registro" ON core_empresas FOR INSERT WITH CHECK (true);
CREATE POLICY "empresas_select_propia" ON core_empresas FOR SELECT USING (id = public.user_empresa_id());
CREATE POLICY "empresas_update_propia" ON core_empresas FOR UPDATE
  USING (id = public.user_empresa_id()) WITH CHECK (id = public.user_empresa_id());
CREATE POLICY "empresas_delete_propia" ON core_empresas FOR DELETE USING (id = public.user_empresa_id());

-- core_usuarios (sin recursión: la función helper es SECURITY DEFINER)
ALTER TABLE core_usuarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "usuarios_insert_propio" ON core_usuarios FOR INSERT
  WITH CHECK (auth_user_id = auth.uid());
CREATE POLICY "usuarios_select" ON core_usuarios FOR SELECT
  USING (empresa_id = public.user_empresa_id() OR auth_user_id = auth.uid());
CREATE POLICY "usuarios_update" ON core_usuarios FOR UPDATE
  USING (empresa_id = public.user_empresa_id() OR auth_user_id = auth.uid())
  WITH CHECK (empresa_id = public.user_empresa_id() OR auth_user_id = auth.uid());
CREATE POLICY "usuarios_delete" ON core_usuarios FOR DELETE
  USING (empresa_id = public.user_empresa_id() OR auth_user_id = auth.uid());

-- Catálogos: lectura global + gestión por empresa
ALTER TABLE core_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "roles_lectura" ON core_roles FOR SELECT USING (true);

ALTER TABLE core_permisos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "permisos_via_rol" ON core_permisos FOR ALL USING (
  rol_id IN (SELECT id FROM core_roles
             WHERE empresa_id = public.user_empresa_id() OR empresa_id IS NULL)
);

ALTER TABLE shipping_estados_envio ENABLE ROW LEVEL SECURITY;
CREATE POLICY "estados_lectura" ON shipping_estados_envio FOR SELECT USING (true);

ALTER TABLE shipping_tipos_paquete ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tipos_paquete" ON shipping_tipos_paquete FOR ALL
  USING (empresa_id = public.user_empresa_id() OR empresa_id IS NULL)
  WITH CHECK (empresa_id = public.user_empresa_id());

ALTER TABLE fleet_checklists_plantillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plantillas" ON fleet_checklists_plantillas FOR ALL
  USING (empresa_id = public.user_empresa_id() OR empresa_id IS NULL)
  WITH CHECK (empresa_id = public.user_empresa_id());

ALTER TABLE operations_motivos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "motivos_select" ON operations_motivos FOR SELECT
  USING (empresa_id IS NULL OR empresa_id = public.user_empresa_id());
CREATE POLICY "motivos_insert" ON operations_motivos FOR INSERT
  WITH CHECK (empresa_id = public.user_empresa_id());
CREATE POLICY "motivos_update" ON operations_motivos FOR UPDATE
  USING (empresa_id = public.user_empresa_id()) WITH CHECK (empresa_id = public.user_empresa_id());
CREATE POLICY "motivos_delete" ON operations_motivos FOR DELETE
  USING (empresa_id = public.user_empresa_id());

ALTER TABLE operations_estados_operacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "estados_op_lectura" ON operations_estados_operacion FOR SELECT USING (true);
ALTER TABLE operations_tipos_operacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tipos_op_lectura" ON operations_tipos_operacion FOR SELECT USING (true);

-- tracking_gps: solo SELECT (los inserts van por servicio)
ALTER TABLE tracking_gps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gps_select" ON tracking_gps FOR SELECT
  USING (empresa_id = public.user_empresa_id());

-- tracking_ultima_posicion: CORREGIDO (antes filtraba entre empresas)
ALTER TABLE tracking_ultima_posicion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ultpos_select" ON tracking_ultima_posicion FOR SELECT
  USING (empresa_id = public.user_empresa_id());

-- Notificaciones: solo el propio usuario
ALTER TABLE communication_notificaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mis_notificaciones" ON communication_notificaciones FOR ALL
  USING (usuario_id IN (SELECT id FROM core_usuarios WHERE auth_user_id = auth.uid()));

-- ============================================================================
-- 21. GRANTS (endurecidos: anon solo puede registrarse)
-- ============================================================================
REVOKE ALL ON FUNCTION public.registrar_conductor FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guardar_geocerca    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.registrar_ejecucion FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.integration_dequeue_outbox(INTEGER) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.integration_mark_published(UUID)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.integration_mark_failed(UUID, TEXT) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.registrar_empresa_usuario TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.registrar_conductor       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.guardar_geocerca          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.registrar_ejecucion       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.integration_dequeue_outbox(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.integration_mark_published(UUID)    TO service_role;
GRANT EXECUTE ON FUNCTION public.integration_mark_failed(UUID, TEXT) TO service_role;   