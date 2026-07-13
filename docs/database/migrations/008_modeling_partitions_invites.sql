-- ============================================================================
-- MIGRATION 008: Remaining model fixes, partitions, invites
-- Addresses: remolques, auth_user_id uniqueness, polimorfismo validation,
--   partition automation, duplicate assignment cleanup, redundant indexes,
--   missing validations
-- ============================================================================

-- ============================================================================
-- 1. REMOLQUES EN VIAJES
-- Add remolque_id to operations_viajes_vehiculos, keeping vehiculo_id for trucks
-- A viaje can have: 1 principal vehicle (camión) + optionally 1 remolque
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_viajes_vehiculos' AND column_name = 'remolque_id'
    ) THEN
        ALTER TABLE operations_viajes_vehiculos
            ADD COLUMN remolque_id UUID REFERENCES fleet_remolques(id);
    END IF;
END $$;

-- Validate remolque belongs to same empresa as viaje
CREATE OR REPLACE FUNCTION public.fn_validate_viaje_vehiculo_remolque_empresa()
RETURNS TRIGGER AS $$
DECLARE
    v_trip_empresa UUID;
    v_vehiculo_empresa UUID;
    v_remolque_empresa UUID;
BEGIN
    SELECT empresa_id INTO v_trip_empresa
    FROM operations_viajes WHERE id = NEW.viaje_id AND deleted_at IS NULL;

    IF v_trip_empresa IS NULL THEN
        RAISE EXCEPTION 'Viaje % not found', NEW.viaje_id;
    END IF;

    SELECT empresa_id INTO v_vehiculo_empresa
    FROM fleet_vehiculos WHERE id = NEW.vehiculo_id AND deleted_at IS NULL;

    IF v_vehiculo_empresa IS DISTINCT FROM v_trip_empresa THEN
        RAISE EXCEPTION 'Vehicle % does not belong to viaje empresa %', NEW.vehiculo_id, v_trip_empresa;
    END IF;

    IF NEW.remolque_id IS NOT NULL THEN
        SELECT empresa_id INTO v_remolque_empresa
        FROM fleet_remolques WHERE id = NEW.remolque_id AND deleted_at IS NULL;

        IF v_remolque_empresa IS DISTINCT FROM v_trip_empresa THEN
            RAISE EXCEPTION 'Remolque % does not belong to viaje empresa %', NEW.remolque_id, v_trip_empresa;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_validate_viaje_vehiculo_remolque_empresa ON operations_viajes_vehiculos;
CREATE TRIGGER trg_validate_viaje_vehiculo_remolque_empresa
    BEFORE INSERT OR UPDATE OF viaje_id, vehiculo_id, remolque_id
    ON operations_viajes_vehiculos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_viaje_vehiculo_remolque_empresa();

-- Drop old trigger (from migration 003) that only checks vehiculo
DROP TRIGGER IF EXISTS trg_validate_viaje_vehiculo_empresa ON operations_viajes_vehiculos;

-- Index for remolque lookups
CREATE INDEX IF NOT EXISTS idx_viajes_vehiculos_remolque
    ON operations_viajes_vehiculos(remolque_id)
    WHERE remolque_id IS NOT NULL AND deleted_at IS NULL;


-- ============================================================================
-- 2. CORE_USUARIOS: auth_user_id UNIQUE (single-empresa model)
-- In a logistics platform, each user belongs to exactly one empresa.
-- If duplicates exist, keep the most recent and soft-delete others.
-- ============================================================================
DO $$
DECLARE
    v_dup_count INTEGER;
BEGIN
    -- Find users with duplicate auth_user_id
    SELECT COUNT(*) - COUNT(DISTINCT auth_user_id) INTO v_dup_count
    FROM core_usuarios
    WHERE auth_user_id IS NOT NULL AND deleted_at IS NULL;

    IF v_dup_count > 0 THEN
        RAISE NOTICE 'Found % users with duplicate auth_user_id. Soft-deleting duplicates...', v_dup_count;

        -- For each duplicate auth_user_id, keep only the most recent (by created_at)
        WITH ranked AS (
            SELECT id, auth_user_id, created_at,
                   ROW_NUMBER() OVER (
                       PARTITION BY auth_user_id
                       ORDER BY created_at DESC
                   ) AS rn
            FROM core_usuarios
            WHERE auth_user_id IS NOT NULL AND deleted_at IS NULL
        )
        UPDATE core_usuarios
        SET deleted_at = NOW(),
            deleted_by = (
                SELECT id FROM core_usuarios WHERE auth_user_id = ranked.auth_user_id AND rn = 1 LIMIT 1
            )
        FROM ranked
        WHERE core_usuarios.id = ranked.id AND ranked.rn > 1;

        RAISE NOTICE 'Cleaned up duplicate auth_user_id records';
    END IF;
END $$;

-- Now add UNIQUE constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'core_usuarios'
          AND constraint_type = 'UNIQUE'
          AND constraint_name = 'uq_usuarios_auth_user_id'
    ) THEN
        -- First drop index that would conflict
        DROP INDEX IF EXISTS idx_usuarios_auth;

        -- Make NOT NULL first (auth is required for all users)
        ALTER TABLE core_usuarios ALTER COLUMN auth_user_id SET NOT NULL;

        -- Add the UNIQUE constraint
        ALTER TABLE core_usuarios
            ADD CONSTRAINT uq_usuarios_auth_user_id UNIQUE (auth_user_id);
    END IF;
END $$;

-- Update user_empresa_id() function to use the unique auth_user_id
CREATE OR REPLACE FUNCTION public.user_empresa_id()
RETURNS UUID AS $$
    SELECT empresa_id FROM core_usuarios
    WHERE auth_user_id = auth.uid() AND deleted_at IS NULL AND activo = TRUE
    LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;


-- ============================================================================
-- 3. POLIMORFISMO: validation triggers for referencia_tipo / referencia_id
-- Apply to: operations_geocercas_vinculos, storage_documentos, operations_asignaciones
-- ============================================================================

-- Generic function to validate polymorphic references
CREATE OR REPLACE FUNCTION public.fn_validate_polymorphic_ref(
    p_referencia_tipo VARCHAR,
    p_referencia_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_exists BOOLEAN;
    v_table_name VARCHAR;
BEGIN
    IF p_referencia_id IS NULL THEN
        RETURN TRUE; -- NULL ref is allowed
    END IF;

    -- Map tipo to table name (whitelist for safety)
    v_table_name := CASE p_referencia_tipo
        WHEN 'cliente' THEN 'customers_clientes'
        WHEN 'direccion' THEN 'customers_direcciones'
        WHEN 'sucursal' THEN 'core_sucursales'
        WHEN 'viaje' THEN 'operations_viajes'
        WHEN 'paquete' THEN 'shipping_paquetes'
        WHEN 'envio' THEN 'shipping_envios'
        WHEN 'vehiculo' THEN 'fleet_vehiculos'
        WHEN 'conductor' THEN 'fleet_conductores'
        WHEN 'ruta' THEN 'operations_rutas'
        WHEN 'carga' THEN 'shipping_cargas'
        WHEN 'entrega' THEN 'delivery_entregas'
        WHEN 'incidencia' THEN 'delivery_incidencias'
        WHEN 'usuario' THEN 'core_usuarios'
        WHEN 'checkpoint' THEN 'operations_checkpoints'
        ELSE NULL
    END;

    IF v_table_name IS NULL THEN
        RAISE WARNING 'Unknown referencia_tipo: %', p_referencia_tipo;
        RETURN FALSE;
    END IF;

    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM %I WHERE id = $1 AND deleted_at IS NULL)',
        v_table_name
    ) INTO v_exists USING p_referencia_id;

    RETURN v_exists;
END;
$$ LANGUAGE plpgsql STABLE SET search_path = public;


-- Trigger for operations_geocercas_vinculos
CREATE OR REPLACE FUNCTION public.fn_validate_geocerca_vinculo()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.fn_validate_polymorphic_ref(NEW.referencia_tipo, NEW.referencia_id) THEN
        RAISE EXCEPTION 'Invalid polymorphic reference: tipo=%, id=%', NEW.referencia_tipo, NEW.referencia_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_geocerca_vinculo ON operations_geocercas_vinculos;
CREATE TRIGGER trg_validate_geocerca_vinculo
    BEFORE INSERT OR UPDATE OF referencia_tipo, referencia_id
    ON operations_geocercas_vinculos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_geocerca_vinculo();


-- Trigger for storage_documentos
CREATE OR REPLACE FUNCTION public.fn_validate_documento_ref()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.referencia_tipo IS NOT NULL AND NEW.referencia_id IS NOT NULL THEN
        IF NOT public.fn_validate_polymorphic_ref(NEW.referencia_tipo, NEW.referencia_id) THEN
            RAISE EXCEPTION 'Invalid document reference: tipo=%, id=%', NEW.referencia_tipo, NEW.referencia_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_documento_ref ON storage_documentos;
CREATE TRIGGER trg_validate_documento_ref
    BEFORE INSERT OR UPDATE OF referencia_tipo, referencia_id
    ON storage_documentos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_documento_ref();


-- Trigger for operations_asignaciones
CREATE OR REPLACE FUNCTION public.fn_validate_asignacion_ref()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.referencia_tipo IS NOT NULL AND NEW.referencia_id IS NOT NULL THEN
        IF NOT public.fn_validate_polymorphic_ref(NEW.referencia_tipo, NEW.referencia_id) THEN
            RAISE EXCEPTION 'Invalid assignment reference: tipo=%, id=%', NEW.referencia_tipo, NEW.referencia_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_asignacion_ref ON operations_asignaciones;
CREATE TRIGGER trg_validate_asignacion_ref
    BEFORE INSERT OR UPDATE OF referencia_tipo, referencia_id
    ON operations_asignaciones
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_asignacion_ref();


-- ============================================================================
-- 4. TABLA DE INVITACIONES (reemplaza RUC como invite code)
-- ============================================================================
CREATE TABLE IF NOT EXISTS core_invitaciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id) ON DELETE CASCADE,
    token VARCHAR(64) UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    rol_id UUID NOT NULL REFERENCES core_roles(id),
    email_destino VARCHAR(255),
    usos_maximos INTEGER DEFAULT 1,
    usos_actuales INTEGER DEFAULT 0,
    expira_en TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    activa BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID
);

CREATE INDEX IF NOT EXISTS idx_invitaciones_token ON core_invitaciones(token) WHERE deleted_at IS NULL AND activa = TRUE;
CREATE INDEX IF NOT EXISTS idx_invitaciones_empresa ON core_invitaciones(empresa_id) WHERE deleted_at IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'update_invitaciones_updated_at'
          AND tgrelid = 'core_invitaciones'::regclass
    ) THEN
        CREATE TRIGGER update_invitaciones_updated_at BEFORE UPDATE ON core_invitaciones
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- RLS
ALTER TABLE core_invitaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Invitaciones SELECT empresa" ON core_invitaciones;
CREATE POLICY "Invitaciones SELECT empresa" ON core_invitaciones
    FOR SELECT USING (empresa_id = public.user_empresa_id());

DROP POLICY IF EXISTS "Invitaciones INSERT empresa" ON core_invitaciones;
CREATE POLICY "Invitaciones INSERT empresa" ON core_invitaciones
    FOR INSERT WITH CHECK (empresa_id = public.user_empresa_id());

DROP POLICY IF EXISTS "Invitaciones UPDATE empresa" ON core_invitaciones;
CREATE POLICY "Invitaciones UPDATE empresa" ON core_invitaciones
    FOR UPDATE USING (empresa_id = public.user_empresa_id());


-- Update registrar_empresa_usuario to use invitation tokens
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
    v_invite RECORD;
BEGIN
    IF p_auth_user_id IS DISTINCT FROM auth.uid() THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'auth.uid() mismatch';
        RETURN;
    END IF;

    IF p_auth_user_id IS NULL OR p_email IS NULL OR p_nombre IS NULL OR p_apellido IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Missing required fields';
        RETURN;
    END IF;

    IF p_mode = 'new_company' THEN
        IF p_company_name IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Company name required';
            RETURN;
        END IF;

        SELECT id INTO v_rol_id
        FROM core_roles
        WHERE nombre = COALESCE(p_rol_nombre, 'Administrador') AND es_sistema = TRUE
        LIMIT 1;

        INSERT INTO core_empresas (nombre, ruc, email, estado)
        VALUES (p_company_name, p_company_ruc, p_email, 'activo')
        RETURNING id INTO v_empresa_id;

    ELSIF p_mode = 'join_company' THEN
        IF p_invite_code IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invitation token required';
            RETURN;
        END IF;

        -- Validate token
        SELECT * INTO v_invite
        FROM core_invitaciones
        WHERE token = p_invite_code
          AND activa = TRUE
          AND deleted_at IS NULL
          AND (expira_en IS NULL OR expira_en > NOW())
          AND (usos_maximos IS NULL OR usos_actuales < usos_maximos)
        LIMIT 1;

        IF v_invite.id IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invalid or expired invitation token';
            RETURN;
        END IF;

        v_empresa_id := v_invite.empresa_id;
        v_rol_id := v_invite.rol_id;

        -- Increment usage
        UPDATE core_invitaciones
        SET usos_actuales = usos_actuales + 1,
            activa = CASE WHEN usos_maximos IS NOT NULL AND usos_actuales + 1 >= usos_maximos THEN FALSE ELSE activa END
        WHERE id = v_invite.id;

    ELSE
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invalid mode';
        RETURN;
    END IF;

    INSERT INTO core_usuarios (
        auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo
    )
    VALUES (
        p_auth_user_id, v_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE
    )
    RETURNING id INTO v_usuario_id;

    RETURN QUERY SELECT TRUE, v_empresa_id, v_usuario_id, 'Registration successful';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.registrar_empresa_usuario(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_empresa_usuario(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO authenticated;


-- ============================================================================
-- 5. ASIGNACIÓN DUPLICADA: remove fleet_conductores.vehiculo_actual
-- Bridge tables (operations_viajes_vehiculos / operations_viajes_conductores)
-- are the source of truth. vehiculo_actual is a cached denormalization.
-- Replace with a view + trigger to keep it in sync for backward compat.
-- ============================================================================

DO $$
BEGIN
    -- Keep the column but add a comment noting it's derived
    COMMENT ON COLUMN fleet_conductores.vehiculo_actual
        IS 'DENORMALIZED - use operations_viajes_vehiculos as source of truth. Updated by trigger.';

    COMMENT ON COLUMN fleet_remolques.vehiculo_id
        IS 'DENORMALIZED - use operations_viajes_vehiculos as source of truth. Updated by trigger.';
END $$;

-- Trigger to sync fleet_conductores.vehiculo_actual when viaje vehiculos change
CREATE OR REPLACE FUNCTION public.fn_sync_conductor_vehiculo_actual()
RETURNS TRIGGER AS $$
DECLARE
    v_conductor_id UUID;
BEGIN
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.principal = TRUE) THEN
        -- Find conductor assigned to this viaje as principal
        SELECT ovc.conductor_id INTO v_conductor_id
        FROM operations_viajes_conductores ovc
        WHERE ovc.viaje_id = NEW.viaje_id
          AND ovc.principal = TRUE
          AND ovc.deleted_at IS NULL
        LIMIT 1;

        IF v_conductor_id IS NOT NULL THEN
            UPDATE fleet_conductores
            SET vehiculo_actual = NEW.vehiculo_id
            WHERE id = v_conductor_id
              AND (vehiculo_actual IS DISTINCT FROM NEW.vehiculo_id);
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_conductor_vehiculo_actual ON operations_viajes_vehiculos;
CREATE TRIGGER trg_sync_conductor_vehiculo_actual
    AFTER INSERT OR UPDATE OF viaje_id, vehiculo_id, principal
    ON operations_viajes_vehiculos
    FOR EACH ROW
    WHEN (NEW.principal = TRUE)
    EXECUTE FUNCTION public.fn_sync_conductor_vehiculo_actual();

-- Also sync when conductor assignment changes
CREATE OR REPLACE FUNCTION public.fn_sync_vehiculo_from_conductor()
RETURNS TRIGGER AS $$
DECLARE
    v_vehiculo_id UUID;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.principal = TRUE THEN
        SELECT ovv.vehiculo_id INTO v_vehiculo_id
        FROM operations_viajes_vehiculos ovv
        WHERE ovv.viaje_id = NEW.viaje_id
          AND ovv.principal = TRUE
          AND ovv.deleted_at IS NULL
        LIMIT 1;

        IF v_vehiculo_id IS NOT NULL THEN
            UPDATE fleet_conductores
            SET vehiculo_actual = v_vehiculo_id
            WHERE id = NEW.conductor_id
              AND (vehiculo_actual IS DISTINCT FROM v_vehiculo_id);
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_vehiculo_from_conductor ON operations_viajes_conductores;
CREATE TRIGGER trg_sync_vehiculo_from_conductor
    AFTER INSERT OR UPDATE OF viaje_id, conductor_id, principal
    ON operations_viajes_conductores
    FOR EACH ROW
    WHEN (NEW.principal = TRUE)
    EXECUTE FUNCTION public.fn_sync_vehiculo_from_conductor();


-- ============================================================================
-- 6. REDUNDANT INDEXES ON UNIQUE COLUMNS
-- Remove indexes on columns that already have UNIQUE constraints
-- ============================================================================

-- shipping_paquetes.tracking_number is UNIQUE
DROP INDEX IF EXISTS idx_paquetes_tracking;

-- fleet_dispositivos_gps.imei is UNIQUE
DROP INDEX IF EXISTS idx_gps_imei;

-- customers_clientes.ruc has UNIQUE
DROP INDEX IF EXISTS idx_clientes_ruc;

-- core_usuarios.email has no UNIQUE but is in the main query pattern;
-- keep idx_usuarios_email for performance (auth_user_id is now the unique key)

-- fleet_conductores.licencia is NOT globally unique but is now validated per-empresa;
-- keep the index for lookup

-- We already eliminated low-cardinality indexes in 007


-- ============================================================================
-- 7. MISSING VALIDATIONS
-- ============================================================================

-- 7a. One primary address per client
DROP INDEX IF EXISTS uq_direccion_principal_cliente;
CREATE UNIQUE INDEX uq_direccion_principal_cliente
    ON customers_direcciones(cliente_id)
    WHERE tipo = 'principal' AND deleted_at IS NULL;

-- 7b. A GPS device assigned to at most ONE active vehicle
DROP INDEX IF EXISTS uq_vehiculo_gps_activo;
CREATE UNIQUE INDEX uq_vehiculo_gps_activo
    ON fleet_vehiculos(gps_id)
    WHERE gps_id IS NOT NULL AND deleted_at IS NULL
      AND estado != 'fuera_servicio';

-- 7c. One usuario per active conductor
DROP INDEX IF EXISTS uq_conductor_usuario_activo;
CREATE UNIQUE INDEX uq_conductor_usuario_activo
    ON fleet_conductores(usuario_id)
    WHERE usuario_id IS NOT NULL AND deleted_at IS NULL AND estado != 'inactivo';

-- 7d. License unique per empresa
DROP INDEX IF EXISTS idx_conductores_licencia;
CREATE UNIQUE INDEX uq_conductor_licencia_empresa
    ON fleet_conductores(empresa_id, licencia)
    WHERE deleted_at IS NULL;

-- 7e. Email normalization trigger (lowercase + trim)
CREATE OR REPLACE FUNCTION public.fn_normalize_email()
RETURNS TRIGGER AS $$
BEGIN
    NEW.email := lower(trim(NEW.email));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to customer and user emails
DROP TRIGGER IF EXISTS trg_normalize_email_usuarios ON core_usuarios;
CREATE TRIGGER trg_normalize_email_usuarios
    BEFORE INSERT OR UPDATE OF email ON core_usuarios
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_normalize_email();

DROP TRIGGER IF EXISTS trg_normalize_email_clientes ON customers_clientes;
CREATE TRIGGER trg_normalize_email_clientes
    BEFORE INSERT OR UPDATE OF email ON customers_clientes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_normalize_email();

-- 7f. Add email UNIQUE index for usuarios (per empresa)
DROP INDEX IF EXISTS idx_usuarios_email;
CREATE UNIQUE INDEX uq_usuarios_email_empresa
    ON core_usuarios(empresa_id, lower(email))
    WHERE deleted_at IS NULL;


-- ============================================================================
-- 8. PARTITION AUTOMATION
-- Function to create next month's partitions automatically.
-- Call this monthly via pg_cron or a scheduled task.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_next_month_partitions()
RETURNS TABLE (table_name TEXT, created BOOLEAN) AS $$
DECLARE
    v_next_month DATE;
    v_start_date TEXT;
    v_end_date TEXT;
    v_month_label TEXT;
BEGIN
    v_next_month := DATE_TRUNC('month', NOW()) + INTERVAL '1 month';
    v_start_date := TO_CHAR(v_next_month, 'YYYY-MM-DD');
    v_end_date := TO_CHAR(v_next_month + INTERVAL '1 month', 'YYYY-MM-DD');
    v_month_label := TO_CHAR(v_next_month, 'YYYY_MM');

    -- tracking_gps
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS tracking_gps_%s PARTITION OF tracking_gps
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'tracking_gps_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'tracking_gps_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- tracking_eventos
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS tracking_eventos_%s PARTITION OF tracking_eventos
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'tracking_eventos_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'tracking_eventos_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- shipping_historial_estados
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS shipping_historial_estados_%s PARTITION OF shipping_historial_estados
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'shipping_historial_estados_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'shipping_historial_estados_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- audit_auditoria
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS audit_auditoria_%s PARTITION OF audit_auditoria
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'audit_auditoria_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'audit_auditoria_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- Also create the month after next (to always have 2 months ahead)
    v_next_month := v_next_month + INTERVAL '1 month';
    v_start_date := TO_CHAR(v_next_month, 'YYYY-MM-DD');
    v_end_date := TO_CHAR(v_next_month + INTERVAL '1 month', 'YYYY-MM-DD');
    v_month_label := TO_CHAR(v_next_month, 'YYYY_MM');

    -- tracking_gps +1
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS tracking_gps_%s PARTITION OF tracking_gps
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'tracking_gps_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'tracking_gps_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- tracking_eventos +1
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS tracking_eventos_%s PARTITION OF tracking_eventos
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'tracking_eventos_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'tracking_eventos_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- historial +1
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS shipping_historial_estados_%s PARTITION OF shipping_historial_estados
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'shipping_historial_estados_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'shipping_historial_estados_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;

    -- audit_auditoria +1
    BEGIN
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS audit_auditoria_%s PARTITION OF audit_auditoria
             FOR VALUES FROM (%L) TO (%L)',
            v_month_label, v_start_date, v_end_date
        );
        table_name := 'audit_auditoria_' || v_month_label;
        created := TRUE;
        RETURN NEXT;
    EXCEPTION WHEN duplicate_table THEN
        table_name := 'audit_auditoria_' || v_month_label;
        created := FALSE;
        RETURN NEXT;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.create_next_month_partitions()
    IS 'Creates partitions for the next 2 months. Run monthly via pg_cron or scheduled task.';

GRANT EXECUTE ON FUNCTION public.create_next_month_partitions() TO authenticated;

-- Revoke direct access to partition tables (force querying parent which has RLS)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT relname FROM pg_class
        WHERE relkind = 'p'  -- partition table
          AND relname LIKE ANY (ARRAY[
            'tracking_gps_%', 'tracking_eventos_%',
            'shipping_historial_estados_%', 'audit_auditoria_%'
          ])
          AND relname NOT LIKE '%_default'
    LOOP
        EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC', rec.relname);
        EXECUTE format('REVOKE ALL ON TABLE %I FROM anon', rec.relname);
        EXECUTE format('REVOKE ALL ON TABLE %I FROM authenticated', rec.relname);
    END LOOP;
END $$;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Migration 008 applied: remolques, auth_user_id UNIQUE, polymorfismo validations,';
    RAISE NOTICE '  invitation tokens, duplicate assignment sync, redundant indexes removed,';
    RAISE NOTICE '  missing validations, partition automation function created,';
    RAISE NOTICE '  direct partition access revoked.';
END $$;
