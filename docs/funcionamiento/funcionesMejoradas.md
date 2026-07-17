# SQL Corregido — Migración Puente + Capa Final Endurecida

Te lo entrego en **fases ejecutables en orden**. Cada fase es idempotente donde es posible (`IF NOT EXISTS`, `DROP ... IF EXISTS`) para poder re-ejecutar sin romper.

---

## FASE 0 — Extensiones necesarias

```sql
-- ============================================================================
-- FASE 0: EXTENSIONES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- digest() para hash/idempotencia
CREATE EXTENSION IF NOT EXISTS "btree_gist"; -- exclusion constraints de custodia
```

---

## FASE 1 — Hardening del DDL existente

### 1.1 Corregir funciones helper con `search_path`

```sql
-- ============================================================================
-- FASE 1.1: HELPERS SEGUROS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.user_empresa_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT empresa_id
  FROM core_usuarios
  WHERE auth_user_id = auth.uid()
    AND deleted_at IS NULL
    AND activo = TRUE
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.user_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core_usuarios u
    JOIN core_roles r ON u.rol_id = r.id
    WHERE u.auth_user_id = auth.uid()
      AND r.nombre = 'Administrador'
      AND u.deleted_at IS NULL
      AND u.activo = TRUE
  );
$$;
```

### 1.2 Corregir el bug de unicidad de paquete activo en viaje

```sql
-- ============================================================================
-- FASE 1.2: BUG LÓGICO - paquete solo en UN viaje activo
-- ============================================================================

-- El índice original NO garantizaba lo que decía su comentario.
DROP INDEX IF EXISTS uq_viaje_paquete_activo;

-- Un paquete solo puede tener UNA asignación activa (en cualquier viaje)
CREATE UNIQUE INDEX uq_paquete_asignacion_activa
  ON operations_viajes_paquetes(paquete_id)
  WHERE deleted_at IS NULL
    AND estado NOT IN ('entregado', 'reasignado');
```

### 1.3 Eliminar constraints UNIQUE globales y reemplazar por unicidad por empresa

```sql
-- ============================================================================
-- FASE 1.3: UNICIDAD MULTI-TENANT (no global)
-- ============================================================================

-- operations_rutas
ALTER TABLE operations_rutas DROP CONSTRAINT IF EXISTS operations_rutas_codigo_key;
DROP INDEX IF EXISTS idx_rutas_codigo;
CREATE UNIQUE INDEX IF NOT EXISTS uq_rutas_empresa_codigo_activa
  ON operations_rutas(empresa_id, codigo)
  WHERE deleted_at IS NULL AND codigo IS NOT NULL;

-- operations_viajes
ALTER TABLE operations_viajes DROP CONSTRAINT IF EXISTS operations_viajes_codigo_key;
DROP INDEX IF EXISTS idx_viajes_codigo;
CREATE UNIQUE INDEX IF NOT EXISTS uq_viajes_empresa_codigo_activo
  ON operations_viajes(empresa_id, codigo)
  WHERE deleted_at IS NULL;

-- shipping_cargas
ALTER TABLE shipping_cargas DROP CONSTRAINT IF EXISTS shipping_cargas_codigo_key;
DROP INDEX IF EXISTS idx_cargas_codigo;
CREATE UNIQUE INDEX IF NOT EXISTS uq_cargas_empresa_codigo_activa
  ON shipping_cargas(empresa_id, codigo)
  WHERE deleted_at IS NULL;

-- shipping_envios
CREATE UNIQUE INDEX IF NOT EXISTS uq_envios_empresa_codigo_activo
  ON shipping_envios(empresa_id, codigo)
  WHERE deleted_at IS NULL;

-- fleet_vehiculos: matrícula única por empresa (solo activos)
DROP INDEX IF EXISTS idx_vehiculos_matricula;
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehiculos_empresa_matricula_activa
  ON fleet_vehiculos(empresa_id, matricula)
  WHERE deleted_at IS NULL;

-- NOTA: fleet_dispositivos_gps.imei se mantiene UNIQUE global (correcto:
-- un IMEI físico no puede existir en dos empresas).
```

### 1.4 Corregir unicidad de catálogos globales (`empresa_id NULL`)

```sql
-- ============================================================================
-- FASE 1.4: UNIQUE con NULL (los NULL no son iguales entre sí en PG)
-- ============================================================================

-- core_roles
ALTER TABLE core_roles DROP CONSTRAINT IF EXISTS unique_rol_empresa;
CREATE UNIQUE INDEX IF NOT EXISTS uq_roles_sistema_nombre
  ON core_roles(nombre)
  WHERE empresa_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_roles_empresa_nombre
  ON core_roles(empresa_id, nombre)
  WHERE empresa_id IS NOT NULL AND deleted_at IS NULL;

-- shipping_tipos_paquete
ALTER TABLE shipping_tipos_paquete DROP CONSTRAINT IF EXISTS unique_tipo_paquete_empresa;
CREATE UNIQUE INDEX IF NOT EXISTS uq_tipos_paquete_sistema_codigo
  ON shipping_tipos_paquete(codigo)
  WHERE empresa_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_tipos_paquete_empresa_codigo
  ON shipping_tipos_paquete(empresa_id, codigo)
  WHERE empresa_id IS NOT NULL AND deleted_at IS NULL;
```

### 1.5 RLS faltante en tablas sensibles

```sql
-- ============================================================================
-- FASE 1.5: RLS FALTANTE
-- ============================================================================

-- core_sucursales
ALTER TABLE core_sucursales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Sucursales de la empresa" ON core_sucursales;
CREATE POLICY "Sucursales de la empresa" ON core_sucursales
  FOR ALL USING (empresa_id = public.user_empresa_id())
  WITH CHECK (empresa_id = public.user_empresa_id());

-- core_configuraciones
ALTER TABLE core_configuraciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Configuraciones de la empresa" ON core_configuraciones;
CREATE POLICY "Configuraciones de la empresa" ON core_configuraciones
  FOR ALL USING (empresa_id = public.user_empresa_id())
  WITH CHECK (empresa_id = public.user_empresa_id());

-- fleet_mantenimientos
ALTER TABLE fleet_mantenimientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Mantenimientos de la empresa" ON fleet_mantenimientos;
CREATE POLICY "Mantenimientos de la empresa" ON fleet_mantenimientos
  FOR ALL USING (empresa_id = public.user_empresa_id())
  WITH CHECK (empresa_id = public.user_empresa_id());

-- shipping_paquetes_cargas (a través de carga)
ALTER TABLE shipping_paquetes_cargas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Paquetes-cargas de la empresa" ON shipping_paquetes_cargas;
CREATE POLICY "Paquetes-cargas de la empresa" ON shipping_paquetes_cargas
  FOR ALL USING (
    carga_id IN (SELECT id FROM shipping_cargas WHERE empresa_id = public.user_empresa_id())
  );

-- shipping_historial_estados (particionada - RLS en la tabla padre)
ALTER TABLE shipping_historial_estados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Historial de la empresa" ON shipping_historial_estados;
CREATE POLICY "Historial de la empresa" ON shipping_historial_estados
  FOR ALL USING (
    paquete_id IN (SELECT id FROM shipping_paquetes WHERE empresa_id = public.user_empresa_id())
  );
```

### 1.6 Corregir `tracking_ultima_posicion` (fuga cross-tenant)

```sql
-- ============================================================================
-- FASE 1.6: tracking_ultima_posicion - NO debe filtrar entre empresas
-- ============================================================================

ALTER TABLE tracking_ultima_posicion ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ultima posicion de la empresa" ON tracking_ultima_posicion;
CREATE POLICY "Ultima posicion de la empresa" ON tracking_ultima_posicion
  FOR SELECT USING (empresa_id = public.user_empresa_id());

-- El trigger que la actualiza es SECURITY DEFINER, por lo que sigue
-- funcionando aunque RLS esté activo. Solo restringimos la LECTURA.
```

### 1.7 Corregir grants peligrosos a `anon`

```sql
-- ============================================================================
-- FASE 1.7: GRANTS - anon no debe crear conductores/geocercas
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public.registrar_conductor FROM anon;
REVOKE EXECUTE ON FUNCTION public.guardar_geocerca   FROM anon;

GRANT EXECUTE ON FUNCTION public.registrar_conductor TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.guardar_geocerca   TO authenticated, service_role;

-- registrar_empresa_usuario SÍ puede quedar para anon (es el registro inicial),
-- pero validando internamente (ver fase 1.8).
```

### 1.8 Re-crear funciones privilegiadas con `search_path` y autorización

```sql
-- ============================================================================
-- FASE 1.8: registrar_conductor endurecida
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
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conductor_id UUID;
  v_usuario_id UUID;
  v_rol_id UUID;
  v_existe_conductor BOOLEAN;
  v_existe_usuario BOOLEAN;
BEGIN
  -- Autorización explícita: solo un usuario de esa empresa (o admin) puede crear
  IF auth.uid() IS NOT NULL
     AND public.user_empresa_id() IS DISTINCT FROM p_empresa_id THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'No autorizado para registrar conductores en esta empresa'::TEXT;
    RETURN;
  END IF;

  IF p_empresa_id IS NULL OR p_nombre IS NULL OR p_apellido IS NULL
     OR p_email IS NULL OR p_licencia IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'Faltan campos obligatorios'::TEXT;
    RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM fleet_conductores
    WHERE empresa_id = p_empresa_id AND licencia = p_licencia AND deleted_at IS NULL
  ) INTO v_existe_conductor;

  IF v_existe_conductor THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'Ya existe un conductor con esa licencia'::TEXT;
    RETURN;
  END IF;

  SELECT id INTO v_rol_id FROM core_roles
    WHERE nombre = 'Chofer' AND es_sistema = TRUE LIMIT 1;

  SELECT EXISTS(
    SELECT 1 FROM core_usuarios WHERE email = p_email AND deleted_at IS NULL
  ) INTO v_existe_usuario;

  IF v_existe_usuario THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'Ya existe un usuario con ese email'::TEXT;
    RETURN;
  END IF;

  IF p_auth_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID,
      'Se requiere auth_user_id (crear usuario en auth.users primero)'::TEXT;
    RETURN;
  END IF;

  INSERT INTO fleet_conductores (
    empresa_id, licencia, tipo_licencia, vencimiento_licencia, telefono, estado
  ) VALUES (
    p_empresa_id, p_licencia, p_tipo_licencia, p_vencimiento_licencia, p_telefono, 'disponible'
  ) RETURNING id INTO v_conductor_id;

  INSERT INTO core_usuarios (
    auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo
  ) VALUES (
    p_auth_user_id, p_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE
  ) RETURNING id INTO v_usuario_id;

  UPDATE fleet_conductores SET usuario_id = v_usuario_id WHERE id = v_conductor_id;

  RETURN QUERY SELECT TRUE, v_conductor_id, v_usuario_id, p_auth_user_id,
    'Conductor registrado exitosamente'::TEXT;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, SQLERRM::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_conductor TO authenticated, service_role;
```

> Aplica el mismo patrón (`SET search_path = public, pg_temp` + validación de empresa) a `guardar_geocerca` y `registrar_empresa_usuario`. En `guardar_geocerca` añade al inicio:
> ```sql
> IF auth.uid() IS NOT NULL
>    AND p_empresa_id IS NOT NULL
>    AND public.user_empresa_id() IS DISTINCT FROM p_empresa_id THEN
>   RETURN QUERY SELECT FALSE, NULL::UUID, 'No autorizado'::TEXT;
>   RETURN;
> END IF;
> ```

---

## FASE 2 — Catálogos del nuevo modelo Operación/Ejecución

```sql
-- ============================================================================
-- FASE 2.1: CATÁLOGO DE ESTADOS DE OPERACIÓN
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_estados_operacion (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo VARCHAR(50) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  es_final BOOLEAN DEFAULT FALSE,
  es_sistema BOOLEAN DEFAULT FALSE,
  orden INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_estados_op_codigo
  ON operations_estados_operacion(codigo) WHERE es_sistema = TRUE;

INSERT INTO operations_estados_operacion (codigo, nombre, es_final, es_sistema, orden) VALUES
  ('pendiente',   'Pendiente',   FALSE, TRUE, 1),
  ('en_proceso',  'En proceso',  FALSE, TRUE, 2),
  ('completada',  'Completada',  TRUE,  TRUE, 3),
  ('fallida',     'Fallida',     TRUE,  TRUE, 4),
  ('cancelada',   'Cancelada',   TRUE,  TRUE, 5),
  ('reasignada',  'Reasignada',  TRUE,  TRUE, 6)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- FASE 2.2: CATÁLOGO DE TIPOS DE OPERACIÓN (con inventory_action)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_tipos_operacion (
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
CREATE UNIQUE INDEX IF NOT EXISTS uq_tipos_op_codigo
  ON operations_tipos_operacion(codigo) WHERE es_sistema = TRUE;

INSERT INTO operations_tipos_operacion (codigo, nombre, inventory_action, requiere_firma, es_sistema) VALUES
  ('recoger',      'Recoger',      'ADD',          FALSE, TRUE),
  ('cargar',       'Cargar',       'ADD',          FALSE, TRUE),
  ('entregar',     'Entregar',     'REMOVE',       TRUE,  TRUE),
  ('descargar',    'Descargar',    'REMOVE',       FALSE, TRUE),
  ('transferir',   'Transferir',   'TRANSFER_OUT', FALSE, TRUE),
  ('inspeccionar', 'Inspeccionar', 'NONE',         FALSE, TRUE),
  ('pesar',        'Pesar',        'NONE',         FALSE, TRUE),
  ('retener',      'Retener',      'NONE',         FALSE, TRUE)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- FASE 2.3: CATÁLOGO DE MOTIVOS (con unicidad correcta y RLS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_motivos (
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

-- Unicidad correcta: separar global de por-empresa
CREATE UNIQUE INDEX IF NOT EXISTS uq_motivos_sistema_codigo
  ON operations_motivos(codigo) WHERE empresa_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_motivos_empresa_codigo
  ON operations_motivos(empresa_id, codigo) WHERE empresa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_motivos_categoria
  ON operations_motivos(categoria) WHERE activo = TRUE;

INSERT INTO operations_motivos (codigo, nombre, categoria, permite_reintento, es_responsabilidad_cliente, es_sistema) VALUES
  ('cliente_ausente',      'Cliente ausente',           'fallo_entrega',  TRUE,  TRUE,  TRUE),
  ('direccion_incorrecta', 'Dirección incorrecta',      'fallo_entrega',  TRUE,  FALSE, TRUE),
  ('direccion_cerrada',    'Establecimiento cerrado',   'fallo_entrega',  TRUE,  TRUE,  TRUE),
  ('rechazado_cliente',    'Rechazado por cliente',     'devolucion',     FALSE, FALSE, TRUE),
  ('paquete_danado',       'Paquete dañado',            'incidencia',     FALSE, FALSE, TRUE),
  ('acceso_restringido',   'Acceso restringido',        'fallo_entrega',  TRUE,  FALSE, TRUE),
  ('sin_pago',             'Falta de pago (COD)',       'fallo_entrega',  TRUE,  TRUE,  TRUE),
  ('zona_peligrosa',       'Zona insegura',             'fallo_entrega',  TRUE,  FALSE, TRUE),
  ('fuera_horario',        'Fuera de ventana horaria',  'fallo_entrega',  TRUE,  FALSE, TRUE),
  ('documento_faltante',   'Documentación incompleta',  'fallo_recogida', TRUE,  TRUE,  TRUE)
ON CONFLICT DO NOTHING;

ALTER TABLE operations_motivos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Motivos visibles" ON operations_motivos;
CREATE POLICY "Motivos visibles" ON operations_motivos
  FOR SELECT USING (
    empresa_id IS NULL OR empresa_id = public.user_empresa_id()
  );

DROP POLICY IF EXISTS "Motivos empresa insert" ON operations_motivos;
CREATE POLICY "Motivos empresa insert" ON operations_motivos
  FOR INSERT WITH CHECK (empresa_id = public.user_empresa_id());

DROP POLICY IF EXISTS "Motivos empresa update" ON operations_motivos;
CREATE POLICY "Motivos empresa update" ON operations_motivos
  FOR UPDATE USING (empresa_id = public.user_empresa_id())
  WITH CHECK (empresa_id = public.user_empresa_id());

DROP POLICY IF EXISTS "Motivos empresa delete" ON operations_motivos;
CREATE POLICY "Motivos empresa delete" ON operations_motivos
  FOR DELETE USING (empresa_id = public.user_empresa_id());
```

---

## FASE 3 — Entidades Visita / Operación / Ejecución

```sql
-- ============================================================================
-- FASE 3.1: VISITAS (parada ejecutable dentro de un viaje)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_viaje_visitas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  parada_id UUID REFERENCES operations_paradas(id),
  orden INTEGER NOT NULL DEFAULT 0,
  estado VARCHAR(30) DEFAULT 'pendiente' CHECK (estado IN (
    'pendiente','llego','en_proceso','completada','omitida'
  )),
  hora_llegada TIMESTAMPTZ,
  hora_salida TIMESTAMPTZ,
  latitud DECIMAL(10, 8),
  longitud DECIMAL(11, 8),
  ubicacion GEOGRAPHY(POINT, 4326),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID,
  CONSTRAINT chk_visita_lat CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  CONSTRAINT chk_visita_lon CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180)
);
CREATE INDEX IF NOT EXISTS idx_visitas_viaje ON operations_viaje_visitas(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_visitas_orden ON operations_viaje_visitas(viaje_id, orden);
CREATE INDEX IF NOT EXISTS idx_visitas_ubicacion ON operations_viaje_visitas USING GIST(ubicacion);

CREATE TRIGGER trg_set_visitas_ubicacion
  BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_viaje_visitas
  FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();
CREATE TRIGGER update_visitas_updated_at
  BEFORE UPDATE ON operations_viaje_visitas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE operations_viaje_visitas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Visitas de la empresa" ON operations_viaje_visitas
  FOR ALL USING (empresa_id = public.user_empresa_id());

-- ============================================================================
-- FASE 3.2: OPERACIONES (el "QUÉ" - inmutable en intención)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_visita_operaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id) ON DELETE CASCADE,
  visita_id UUID NOT NULL REFERENCES operations_viaje_visitas(id) ON DELETE CASCADE,
  paquete_id UUID REFERENCES shipping_paquetes(id),
  tipo_id UUID REFERENCES operations_tipos_operacion(id),
  estado_id UUID REFERENCES operations_estados_operacion(id),
  orden INTEGER DEFAULT 0,
  -- Contadores denormalizados (controlados por la función registrar_ejecucion)
  total_intentos INTEGER DEFAULT 0,
  max_intentos INTEGER DEFAULT 3,
  ejecucion_exitosa_id UUID,  -- FK diferida se agrega en 3.4
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);
CREATE INDEX IF NOT EXISTS idx_operaciones_viaje ON operations_visita_operaciones(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_operaciones_visita ON operations_visita_operaciones(visita_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_operaciones_paquete ON operations_visita_operaciones(paquete_id);
CREATE INDEX IF NOT EXISTS idx_operaciones_estado ON operations_visita_operaciones(estado_id);

CREATE TRIGGER update_operaciones_updated_at
  BEFORE UPDATE ON operations_visita_operaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE operations_visita_operaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Operaciones de la empresa" ON operations_visita_operaciones
  FOR ALL USING (empresa_id = public.user_empresa_id());

COMMENT ON TABLE operations_visita_operaciones IS
  'OPERACIÓN: define QUÉ debe hacerse con un paquete en una visita. Inmutable en intención. Puede tener múltiples ejecuciones.';

-- ============================================================================
-- FASE 3.3: EJECUCIONES (el "CÓMO" - 0..N intentos)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_operacion_ejecuciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  operacion_id UUID NOT NULL REFERENCES operations_visita_operaciones(id) ON DELETE CASCADE,
  viaje_id UUID NOT NULL REFERENCES operations_viajes(id),
  visita_id UUID NOT NULL REFERENCES operations_viaje_visitas(id),
  paquete_id UUID REFERENCES shipping_paquetes(id),
  numero_intento INTEGER NOT NULL DEFAULT 1,
  resultado VARCHAR(30) NOT NULL DEFAULT 'en_proceso' CHECK (resultado IN (
    'en_proceso','exitosa','fallida','parcial','cancelada'
  )),
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
  latitud DECIMAL(10, 8),
  longitud DECIMAL(11, 8),
  ubicacion GEOGRAPHY(POINT, 4326),
  precision_gps_m DECIMAL(5, 2),
  offline BOOLEAN DEFAULT FALSE,
  sincronizada_en TIMESTAMPTZ,
  client_operation_id UUID,
  firma_verificada BOOLEAN DEFAULT FALSE,
  otp_verificado BOOLEAN DEFAULT FALSE,
  escaneo_verificado BOOLEAN DEFAULT FALSE,
  receptor_nombre VARCHAR(255),
  receptor_documento VARCHAR(20),
  receptor_relacion VARCHAR(50),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  updated_by UUID,
  CONSTRAINT uq_ejecucion_operacion_intento UNIQUE (operacion_id, numero_intento),
  CONSTRAINT uq_ejecucion_client_op UNIQUE (client_operation_id),
  CONSTRAINT chk_ejec_lat CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  CONSTRAINT chk_ejec_lon CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180)
);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_operacion ON operations_operacion_ejecuciones(operacion_id);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_viaje ON operations_operacion_ejecuciones(viaje_id);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_resultado ON operations_operacion_ejecuciones(resultado);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_conductor ON operations_operacion_ejecuciones(conductor_id);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_fecha ON operations_operacion_ejecuciones(iniciada_en DESC);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_offline ON operations_operacion_ejecuciones(offline)
  WHERE offline = TRUE AND sincronizada_en IS NULL;
CREATE INDEX IF NOT EXISTS idx_ejecuciones_ubicacion ON operations_operacion_ejecuciones USING GIST(ubicacion);

CREATE TRIGGER trg_set_ejecuciones_ubicacion
  BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_operacion_ejecuciones
  FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();
CREATE TRIGGER update_ejecuciones_updated_at
  BEFORE UPDATE ON operations_operacion_ejecuciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE operations_operacion_ejecuciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Ejecuciones de la empresa" ON operations_operacion_ejecuciones
  FOR ALL USING (empresa_id = public.user_empresa_id());

COMMENT ON TABLE operations_operacion_ejecuciones IS
  'EJECUCIÓN: cada intento real. Append-only tras finalizar. Permite FADR y KPIs de reintentos.';

-- ============================================================================
-- FASE 3.4: FK circular segura (DEFERRABLE + ON DELETE SET NULL)
-- ============================================================================
ALTER TABLE operations_visita_operaciones
  DROP CONSTRAINT IF EXISTS fk_op_ejecucion_exitosa;
ALTER TABLE operations_visita_operaciones
  ADD CONSTRAINT fk_op_ejecucion_exitosa
  FOREIGN KEY (ejecucion_exitosa_id)
  REFERENCES operations_operacion_ejecuciones(id)
  ON DELETE SET NULL
  DEFERRABLE INITIALLY DEFERRED;

-- ============================================================================
-- FASE 3.5: Ejecuciones append-only (trigger anti-mutación tras cierre)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_prevent_ejecucion_final_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.finalizada_en IS NOT NULL THEN
    IF NEW.resultado          IS DISTINCT FROM OLD.resultado
    OR NEW.motivo_id          IS DISTINCT FROM OLD.motivo_id
    OR NEW.finalizada_en      IS DISTINCT FROM OLD.finalizada_en
    OR NEW.latitud            IS DISTINCT FROM OLD.latitud
    OR NEW.longitud           IS DISTINCT FROM OLD.longitud
    OR NEW.receptor_nombre    IS DISTINCT FROM OLD.receptor_nombre THEN
      RAISE EXCEPTION 'No se puede modificar una ejecución ya finalizada';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_ejecucion_final_mutation
  BEFORE UPDATE ON operations_operacion_ejecuciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_ejecucion_final_mutation();
```

---

## FASE 4 — Evidencias y Custodia

```sql
-- ============================================================================
-- FASE 4.1: EVIDENCIAS (N:1 con ejecución, url opcional)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_evidencias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  ejecucion_id UUID REFERENCES operations_operacion_ejecuciones(id) ON DELETE CASCADE,
  operacion_id UUID REFERENCES operations_visita_operaciones(id),
  viaje_id UUID REFERENCES operations_viajes(id),
  paquete_id UUID REFERENCES shipping_paquetes(id),
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN (
    'foto','firma','audio','video','pdf','scan','documento','otp_log','temperatura','ubicacion'
  )),
  url TEXT,                               -- ya NO es NOT NULL
  valor JSONB DEFAULT '{}'::jsonb,        -- para evidencias sin archivo
  bucket VARCHAR(100),
  ruta_archivo TEXT,
  mime_type VARCHAR(100),
  tamano_bytes BIGINT,
  hash_sha256 VARCHAR(64),
  descripcion TEXT,
  orden INTEGER DEFAULT 0,
  latitud DECIMAL(10, 8),
  longitud DECIMAL(11, 8),
  ubicacion GEOGRAPHY(POINT, 4326),
  capturada_en TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT chk_evidencia_contenido CHECK (url IS NOT NULL OR valor <> '{}'::jsonb),
  CONSTRAINT chk_evid_lat CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  CONSTRAINT chk_evid_lon CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180)
);
CREATE INDEX IF NOT EXISTS idx_evidencias_ejecucion ON operations_evidencias(ejecucion_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_evidencias_operacion ON operations_evidencias(operacion_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_evidencias_paquete ON operations_evidencias(paquete_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_evidencias_tipo ON operations_evidencias(tipo) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_evidencias_ubicacion ON operations_evidencias USING GIST(ubicacion);

CREATE TRIGGER trg_set_evidencias_ubicacion
  BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_evidencias
  FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

ALTER TABLE operations_evidencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Evidencias de la empresa" ON operations_evidencias
  FOR ALL USING (empresa_id = public.user_empresa_id());

-- ============================================================================
-- FASE 4.2: CUSTODIA (una sola custodia actual + sin solapamiento temporal)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_custodia (
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
  latitud DECIMAL(10, 8),
  longitud DECIMAL(11, 8),
  ubicacion GEOGRAPHY(POINT, 4326),
  estado_fisico VARCHAR(30) DEFAULT 'integro' CHECK (estado_fisico IN (
    'integro','dañado','mojado','abierto','incompleto'
  )),
  observaciones TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  CONSTRAINT uq_custodia_paquete_secuencia UNIQUE (paquete_id, secuencia),
  CONSTRAINT chk_custodia_periodo CHECK (entregado_en IS NULL OR entregado_en > recibido_en),
  CONSTRAINT chk_cust_lat CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  CONSTRAINT chk_cust_lon CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180)
);

-- Una sola custodia ACTUAL por paquete (UNIQUE, no simple index)
CREATE UNIQUE INDEX IF NOT EXISTS uq_custodia_actual_paquete
  ON operations_custodia(paquete_id) WHERE entregado_en IS NULL;

-- Sin solapamiento temporal de custodias del mismo paquete
ALTER TABLE operations_custodia
  DROP CONSTRAINT IF EXISTS ex_custodia_no_overlap;
ALTER TABLE operations_custodia
  ADD CONSTRAINT ex_custodia_no_overlap
  EXCLUDE USING gist (
    paquete_id WITH =,
    tstzrange(recibido_en, COALESCE(entregado_en, 'infinity'::timestamptz), '[)') WITH &&
  );

CREATE INDEX IF NOT EXISTS idx_custodia_paquete ON operations_custodia(paquete_id, secuencia);
CREATE INDEX IF NOT EXISTS idx_custodia_custodio ON operations_custodia(custodio_tipo, custodio_id);
CREATE INDEX IF NOT EXISTS idx_custodia_ubicacion ON operations_custodia USING GIST(ubicacion);

CREATE TRIGGER trg_set_custodia_ubicacion
  BEFORE INSERT OR UPDATE OF latitud, longitud ON operations_custodia
  FOR EACH ROW EXECUTE FUNCTION fn_set_ubicacion_from_latlon();

ALTER TABLE operations_custodia ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Custodia de la empresa" ON operations_custodia
  FOR ALL USING (empresa_id = public.user_empresa_id());

-- Consulta de custodia en un momento dado
CREATE OR REPLACE FUNCTION public.custodia_en_momento(
  p_paquete_id UUID,
  p_momento TIMESTAMPTZ
) RETURNS TABLE (
  custodio_tipo VARCHAR,
  custodio_nombre VARCHAR,
  recibido_en TIMESTAMPTZ,
  entregado_en TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.custodio_tipo, c.custodio_nombre, c.recibido_en, c.entregado_en
  FROM operations_custodia c
  WHERE c.paquete_id = p_paquete_id
    AND c.recibido_en <= p_momento
    AND (c.entregado_en IS NULL OR c.entregado_en > p_momento)
  ORDER BY c.secuencia DESC
  LIMIT 1;
$$;
```

---

## FASE 5 — Outbox / Inbox con idempotencia estable

```sql
-- ============================================================================
-- FASE 5.1: OUTBOX / INBOX
-- ============================================================================
CREATE TABLE IF NOT EXISTS integration_outbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  aggregate_type VARCHAR(50) NOT NULL,
  aggregate_id UUID NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  destino VARCHAR(50),
  status VARCHAR(20) NOT NULL DEFAULT 'pendiente' CHECK (status IN (
    'pendiente','publicando','publicado','fallido','descartado'
  )),
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 5,
  next_retry_at TIMESTAMPTZ,
  last_error TEXT,
  idempotency_key VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  CONSTRAINT uq_outbox_idempotency UNIQUE (idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_outbox_pendientes ON integration_outbox(created_at)
  WHERE status IN ('pendiente','fallido');
CREATE INDEX IF NOT EXISTS idx_outbox_aggregate ON integration_outbox(aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS idx_outbox_retry ON integration_outbox(next_retry_at)
  WHERE status = 'fallido' AND next_retry_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS integration_inbox (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID REFERENCES core_empresas(id),
  origen VARCHAR(50) NOT NULL,
  external_id VARCHAR(255) NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) DEFAULT 'recibido' CHECK (status IN (
    'recibido','procesando','procesado','fallido','duplicado'
  )),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_inbox_origen_external UNIQUE (origen, external_id)
);
CREATE INDEX IF NOT EXISTS idx_inbox_pendientes ON integration_inbox(created_at) WHERE status = 'recibido';

-- Outbox NO necesita RLS de lectura por usuarios finales (lo consumen workers
-- con service_role). Lo dejamos sin RLS de app pero accesible solo a service_role.
ALTER TABLE integration_outbox DISABLE ROW LEVEL SECURITY;
ALTER TABLE integration_inbox  DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON integration_outbox FROM anon, authenticated;
REVOKE ALL ON integration_inbox  FROM anon, authenticated;

-- ============================================================================
-- FASE 5.2: publicar_evento_outbox con idempotencia ESTABLE
-- ============================================================================
CREATE OR REPLACE FUNCTION public.publicar_evento_outbox(
  p_empresa_id UUID,
  p_aggregate_type VARCHAR,
  p_aggregate_id UUID,
  p_event_type VARCHAR,
  p_payload JSONB,
  p_destino VARCHAR DEFAULT NULL,
  p_idempotency_key VARCHAR DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_outbox_id UUID;
  v_idempotency VARCHAR(255);
BEGIN
  v_idempotency := COALESCE(
    p_idempotency_key,
    p_aggregate_type || ':' ||
    p_aggregate_id::text || ':' ||
    p_event_type || ':' ||
    COALESCE(
      p_payload->>'event_id',
      p_payload->>'version',
      encode(digest(p_payload::text, 'sha256'), 'hex')
    )
  );

  INSERT INTO integration_outbox (
    empresa_id, aggregate_type, aggregate_id,
    event_type, payload, destino, idempotency_key
  ) VALUES (
    p_empresa_id, p_aggregate_type, p_aggregate_id,
    p_event_type, p_payload, p_destino, v_idempotency
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_outbox_id;

  -- Si ya existía, recuperar el id existente (idempotencia real)
  IF v_outbox_id IS NULL THEN
    SELECT id INTO v_outbox_id
    FROM integration_outbox
    WHERE idempotency_key = v_idempotency;
  END IF;

  RETURN v_outbox_id;
END;
$$;

-- ============================================================================
-- FASE 5.3: Worker dequeue con FOR UPDATE SKIP LOCKED
-- ============================================================================
CREATE OR REPLACE FUNCTION public.integration_dequeue_outbox(
  p_limit INTEGER DEFAULT 100
)
RETURNS SETOF integration_outbox
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH pendientes AS (
    SELECT id
    FROM integration_outbox
    WHERE status IN ('pendiente','fallido')
      AND retry_count < max_retries
      AND (next_retry_at IS NULL OR next_retry_at <= NOW())
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE integration_outbox o
  SET status = 'publicando'
  FROM pendientes p
  WHERE o.id = p.id
  RETURNING o.*;
$$;

-- Marcar publicado / fallido (para el worker)
CREATE OR REPLACE FUNCTION public.integration_mark_published(p_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE integration_outbox
  SET status = 'publicado', published_at = NOW()
  WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.integration_mark_failed(p_id UUID, p_error TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE integration_outbox
  SET status = 'fallido',
      retry_count = retry_count + 1,
      last_error = p_error,
      next_retry_at = NOW() + (INTERVAL '1 minute' * POWER(2, LEAST(retry_count, 10)))
  WHERE id = p_id;
$$;

REVOKE ALL ON FUNCTION public.integration_dequeue_outbox(INTEGER) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.integration_mark_published(UUID)    FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.integration_mark_failed(UUID, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.integration_dequeue_outbox(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.integration_mark_published(UUID)    TO service_role;
GRANT EXECUTE ON FUNCTION public.integration_mark_failed(UUID, TEXT) TO service_role;
```

---

## FASE 6 — `registrar_ejecucion` con bloqueo, autorización y outbox

```sql
-- ============================================================================
-- FASE 6: FUNCIÓN NÚCLEO - registrar_ejecucion (corregida)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.registrar_ejecucion(
  p_operacion_id UUID,
  p_resultado VARCHAR,
  p_conductor_id UUID DEFAULT NULL,
  p_motivo_codigo VARCHAR DEFAULT NULL,
  p_latitud DECIMAL DEFAULT NULL,
  p_longitud DECIMAL DEFAULT NULL,
  p_receptor_nombre VARCHAR DEFAULT NULL,
  p_client_operation_id UUID DEFAULT NULL,
  p_offline BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
  success BOOLEAN,
  ejecucion_id UUID,
  operacion_completada BOOLEAN,
  intentos_restantes INTEGER,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_op RECORD;
  v_ejecucion_id UUID;
  v_numero_intento INTEGER;
  v_motivo_id UUID;
  v_empresa_id UUID;
  v_estado_completada_id UUID;
  v_estado_fallida_id UUID;
  v_intentos_restantes INTEGER;
BEGIN
  -- 1) Idempotencia por client_operation_id
  IF p_client_operation_id IS NOT NULL THEN
    SELECT id INTO v_ejecucion_id
    FROM operations_operacion_ejecuciones
    WHERE client_operation_id = p_client_operation_id;

    IF v_ejecucion_id IS NOT NULL THEN
      RETURN QUERY SELECT TRUE, v_ejecucion_id, FALSE, 0,
        'Ejecución ya registrada (idempotente)'::TEXT;
      RETURN;
    END IF;
  END IF;

  -- 2) Bloquear la operación para evitar carrera en el conteo de intentos
  SELECT * INTO v_op
  FROM operations_visita_operaciones
  WHERE id = p_operacion_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, 'Operación no encontrada'::TEXT;
    RETURN;
  END IF;

  v_empresa_id := v_op.empresa_id;

  -- 3) Autorización explícita (SECURITY DEFINER puede saltar RLS)
  IF auth.uid() IS NOT NULL
     AND public.user_empresa_id() IS DISTINCT FROM v_empresa_id THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0,
      'No autorizado para esta operación'::TEXT;
    RETURN;
  END IF;

  -- 4) Si ya está completada, no permitir más intentos
  IF v_op.ejecucion_exitosa_id IS NOT NULL THEN
    RETURN QUERY SELECT FALSE, v_op.ejecucion_exitosa_id, TRUE, 0,
      'La operación ya fue completada'::TEXT;
    RETURN;
  END IF;

  v_numero_intento := v_op.total_intentos + 1;

  -- 5) Límite de intentos (salvo que sea exitosa)
  IF v_numero_intento > v_op.max_intentos AND p_resultado <> 'exitosa' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0,
      'Se agotaron los intentos permitidos'::TEXT;
    RETURN;
  END IF;

  -- 6) Resolver motivo
  IF p_motivo_codigo IS NOT NULL THEN
    SELECT id INTO v_motivo_id FROM operations_motivos
    WHERE codigo = p_motivo_codigo
      AND (empresa_id IS NULL OR empresa_id = v_empresa_id)
    ORDER BY empresa_id NULLS LAST
    LIMIT 1;
  END IF;

  -- 7) Crear ejecución
  INSERT INTO operations_operacion_ejecuciones (
    empresa_id, operacion_id, viaje_id, visita_id, paquete_id,
    numero_intento, resultado, motivo_id,
    conductor_id, latitud, longitud, receptor_nombre,
    client_operation_id, offline, finalizada_en, sincronizada_en, created_by
  ) VALUES (
    v_empresa_id, p_operacion_id, v_op.viaje_id, v_op.visita_id, v_op.paquete_id,
    v_numero_intento, p_resultado, v_motivo_id,
    p_conductor_id, p_latitud, p_longitud, p_receptor_nombre,
    p_client_operation_id, p_offline, NOW(),
    CASE WHEN p_offline THEN NULL ELSE NOW() END,
    (SELECT id FROM core_usuarios WHERE auth_user_id = auth.uid() LIMIT 1)
  )
  RETURNING id INTO v_ejecucion_id;

  -- 8) Actualizar contador
  UPDATE operations_visita_operaciones
  SET total_intentos = v_numero_intento, updated_at = NOW()
  WHERE id = p_operacion_id;

  -- 9) Resultado exitoso -> cerrar operación + evento outbox
  IF p_resultado = 'exitosa' THEN
    SELECT id INTO v_estado_completada_id
    FROM operations_estados_operacion WHERE codigo = 'completada' AND es_sistema = TRUE;

    UPDATE operations_visita_operaciones
    SET estado_id = v_estado_completada_id,
        ejecucion_exitosa_id = v_ejecucion_id,
        updated_at = NOW()
    WHERE id = p_operacion_id;

    PERFORM public.publicar_evento_outbox(
      v_empresa_id, 'paquete', v_op.paquete_id,
      'paquete.operacion_completada',
      jsonb_build_object(
        'operacion_id', p_operacion_id,
        'ejecucion_id', v_ejecucion_id,
        'paquete_id',   v_op.paquete_id,
        'viaje_id',     v_op.viaje_id
      ),
      NULL,
      -- idempotency key estable de negocio
      'paquete:' || v_op.paquete_id::text || ':operacion_completada:' || v_ejecucion_id::text
    );

  -- Si agotó intentos y no fue exitosa -> marcar fallida
  ELSIF v_numero_intento >= v_op.max_intentos AND p_resultado = 'fallida' THEN
    SELECT id INTO v_estado_fallida_id
    FROM operations_estados_operacion WHERE codigo = 'fallida' AND es_sistema = TRUE;
    UPDATE operations_visita_operaciones
    SET estado_id = v_estado_fallida_id, updated_at = NOW()
    WHERE id = p_operacion_id;
  END IF;

  v_intentos_restantes := GREATEST(v_op.max_intentos - v_numero_intento, 0);

  RETURN QUERY SELECT
    TRUE,
    v_ejecucion_id,
    (p_resultado = 'exitosa'),
    v_intentos_restantes,
    CASE
      WHEN p_resultado = 'exitosa' THEN 'Operación completada exitosamente'
      ELSE 'Intento registrado. Reintentos restantes: ' || v_intentos_restantes
    END::TEXT;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, NULL::UUID, FALSE, 0, SQLERRM::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_ejecucion FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_ejecucion TO authenticated, service_role;
```

---

## FASE 7 — Capacidades, Restricciones, Optimizaciones

```sql
-- ============================================================================
-- FASE 7.1: CAPACIDADES MULTIDIMENSIONALES
-- ============================================================================
CREATE TABLE IF NOT EXISTS fleet_capacidades (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  vehiculo_id UUID NOT NULL REFERENCES fleet_vehiculos(id) ON DELETE CASCADE,
  peso_max_kg DECIMAL(10, 2),
  volumen_max_m3 DECIMAL(10, 2),
  pallets_max INTEGER,
  metros_lineales_max DECIMAL(8, 2),
  bultos_max INTEGER,
  espacios_adr INTEGER,
  tiene_refrigeracion BOOLEAN DEFAULT FALSE,
  temperatura_min DECIMAL(5, 2),
  temperatura_max DECIMAL(5, 2),
  zonas_temperatura INTEGER DEFAULT 1,
  vigente_desde DATE DEFAULT CURRENT_DATE,
  vigente_hasta DATE,
  activa BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_capacidades_vehiculo ON fleet_capacidades(vehiculo_id) WHERE activa = TRUE;
CREATE TRIGGER update_capacidades_updated_at
  BEFORE UPDATE ON fleet_capacidades
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
ALTER TABLE fleet_capacidades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Capacidades de la empresa" ON fleet_capacidades
  FOR ALL USING (empresa_id = public.user_empresa_id());

-- ============================================================================
-- FASE 7.2: RESTRICCIONES (para VRP solver)
-- ============================================================================
CREATE TABLE IF NOT EXISTS operations_restricciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  referencia_tipo VARCHAR(30) NOT NULL CHECK (referencia_tipo IN (
    'paquete','direccion','cliente','visita','vehiculo'
  )),
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
CREATE INDEX IF NOT EXISTS idx_restricciones_referencia
  ON operations_restricciones(referencia_tipo, referencia_id) WHERE activa = TRUE;
CREATE INDEX IF NOT EXISTS idx_restricciones_tipo ON operations_restricciones(tipo) WHERE activa = TRUE;
CREATE INDEX IF NOT EXISTS idx_restricciones_valor ON operations_restricciones USING GIN(valor);
ALTER TABLE operations_restricciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Restricciones de la empresa" ON operations_restricciones
  FOR ALL USING (empresa_id = public.user_empresa_id());

-- ============================================================================
-- FASE 7.3: HISTORIAL DE OPTIMIZACIÓN
-- ============================================================================
CREATE TABLE IF NOT EXISTS planning_optimizaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
  viaje_id UUID REFERENCES operations_viajes(id),
  algoritmo VARCHAR(50) NOT NULL CHECK (algoritmo IN (
    'manual','google_or_tools','ortools_vrp','vroom','osrm',
    'ia_propietaria','nearest_neighbor','clarke_wright'
  )),
  version_algoritmo VARCHAR(20),
  version_plan INTEGER NOT NULL DEFAULT 1,
  parametros JSONB,
  input_snapshot JSONB,
  distancia_total_km DECIMAL(10, 2),
  tiempo_total_min INTEGER,
  costo_estimado DECIMAL(12, 2),
  paradas_reordenadas INTEGER,
  score_calidad DECIMAL(5, 2),
  mejora_vs_anterior_pct DECIMAL(5, 2),
  duracion_computo_ms INTEGER,
  aplicada BOOLEAN DEFAULT FALSE,
  aplicada_en TIMESTAMPTZ,
  aplicada_por UUID REFERENCES core_usuarios(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID
);
CREATE INDEX IF NOT EXISTS idx_optimizaciones_viaje ON planning_optimizaciones(viaje_id, version_plan);
CREATE INDEX IF NOT EXISTS idx_optimizaciones_algoritmo ON planning_optimizaciones(algoritmo);
CREATE INDEX IF NOT EXISTS idx_optimizaciones_aplicada ON planning_optimizaciones(aplicada) WHERE aplicada = TRUE;
ALTER TABLE planning_optimizaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Optimizaciones de la empresa" ON planning_optimizaciones
  FOR ALL USING (empresa_id = public.user_empresa_id());
```

---

## FASE 8 — KPIs y vistas

```sql
-- ============================================================================
-- FASE 8: FADR con denominadores explícitos
-- ============================================================================
CREATE OR REPLACE VIEW v_kpi_first_attempt
WITH (security_invoker = true)
AS
SELECT
  op.empresa_id,
  op.viaje_id,
  DATE(e.iniciada_en) AS fecha,
  COUNT(DISTINCT op.id)                                    AS total_operaciones,
  COUNT(DISTINCT op.id) FILTER (
    WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
  )                                                        AS exitosas_primer_intento,
  COUNT(DISTINCT op.id) FILTER (
    WHERE op.ejecucion_exitosa_id IS NOT NULL
  )                                                        AS exitosas_total,
  -- Denominador 1: entre las exitosas
  ROUND(
    100.0 * COUNT(DISTINCT op.id) FILTER (
      WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
    ) / NULLIF(COUNT(DISTINCT op.id) FILTER (WHERE op.ejecucion_exitosa_id IS NOT NULL), 0),
    2
  ) AS first_attempt_success_among_successful_pct,
  -- Denominador 2: entre todas las intentadas
  ROUND(
    100.0 * COUNT(DISTINCT op.id) FILTER (
      WHERE op.total_intentos = 1 AND op.ejecucion_exitosa_id IS NOT NULL
    ) / NULLIF(COUNT(DISTINCT op.id), 0),
    2
  ) AS first_attempt_success_among_attempted_pct,
  AVG(e.duracion_segundos) FILTER (WHERE e.resultado = 'exitosa') AS duracion_promedio_seg
FROM operations_visita_operaciones op
JOIN operations_operacion_ejecuciones e ON e.operacion_id = op.id
WHERE op.deleted_at IS NULL
GROUP BY op.empresa_id, op.viaje_id, DATE(e.iniciada_en);

COMMENT ON VIEW v_kpi_first_attempt IS
  'FADR con dos denominadores explícitos para evitar disputas: among_successful y among_attempted.';
```

---

## FASE 9 — Auto-generar operaciones desde el viaje

```sql
-- ============================================================================
-- FASE 9: Al asignar paquetes a un viaje con ruta, generar visitas+operaciones
--         (reemplaza/complementa la lógica de checkpoints anterior)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_generar_visitas_operaciones()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_visita_id UUID;
  v_tipo_entregar_id UUID;
  v_estado_pendiente_id UUID;
BEGIN
  IF NEW.ruta_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Evitar duplicar
  IF EXISTS (
    SELECT 1 FROM operations_viaje_visitas
    WHERE viaje_id = NEW.id AND deleted_at IS NULL
  ) THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_tipo_entregar_id FROM operations_tipos_operacion
    WHERE codigo = 'entregar' AND es_sistema = TRUE;
  SELECT id INTO v_estado_pendiente_id FROM operations_estados_operacion
    WHERE codigo = 'pendiente' AND es_sistema = TRUE;

  -- Una visita por cada parada de la ruta
  INSERT INTO operations_viaje_visitas (empresa_id, viaje_id, parada_id, orden, latitud, longitud)
  SELECT NEW.empresa_id, NEW.id, p.id, p.orden, p.latitud, p.longitud
  FROM operations_paradas p
  WHERE p.ruta_id = NEW.ruta_id AND p.deleted_at IS NULL
  ORDER BY p.orden;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generar_visitas_operaciones ON operations_viajes;
CREATE TRIGGER trg_generar_visitas_operaciones
  AFTER INSERT OR UPDATE OF ruta_id ON operations_viajes
  FOR EACH ROW
  WHEN (NEW.ruta_id IS NOT NULL AND NEW.deleted_at IS NULL)
  EXECUTE FUNCTION public.fn_generar_visitas_operaciones();
```

---

## Notas finales de aplicación

1. **Orden estricto**: ejecuta Fase 0 → 9 en orden. Las fases 3.4 (FK diferida) y 4.2 (exclusion constraint) dependen de tablas creadas antes.

2. **Sobre datos existentes**: si ya tienes datos en `operations_viajes_paquetes` / `operations_checkpoints`, necesitas un script de migración de datos (Fase 3 de mi plan anterior) que puebla `operations_viaje_visitas` y `operations_visita_operaciones`. No lo incluí aquí porque depende de cómo mapees tus registros actuales — dímelo y lo escribo.

3. **`delivery_*` se mantienen** como proyección/compatibilidad. No las borres todavía.

4. **Verificación rápida post-ejecución**:

```sql
-- Comprobar que no quedan funciones SECURITY DEFINER sin search_path
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'
  );

-- Comprobar tablas sin RLS que deberían tenerlo
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relrowsecurity = FALSE
  AND c.relname LIKE ANY (ARRAY['operations_%','shipping_%','delivery_%','fleet_%','customers_%','tracking_%']);
```

¿Quieres que escriba ahora el **script de migración de datos** (Fase 3 real) desde `operations_viajes_paquetes` + `delivery_entregas` hacia el nuevo modelo Operación/Ejecución/Custodia?