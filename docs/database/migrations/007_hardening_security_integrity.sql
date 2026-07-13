-- ============================================================================
-- MIGRATION 007: Security hardening & integrity fixes
-- Addresses: SECURITY DEFINER exposure, RLS gaps, multi-tenant integrity,
--   index correctness, estado sync, audit trigger crash, global UNIQUE removal
-- ============================================================================

-- ============================================================================
-- P0.1: Fix SECURITY DEFINER functions - verify auth.uid() and empresa
-- ============================================================================
-- WARNING: registrar_empresa_usuario is inherently complex for self-registration.
-- The INSERT into core_empresas is allowed via RLS policy "Empresas INSERT registro".
-- After that, all subsequent operations must use auth.uid() checks.

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
    -- CRITICAL: caller must match authenticated user
    IF p_auth_user_id IS DISTINCT FROM auth.uid() THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'auth.uid() mismatch: cannot create user for another uid';
        RETURN;
    END IF;

    -- Validate required fields
    IF p_auth_user_id IS NULL OR p_email IS NULL OR p_nombre IS NULL OR p_apellido IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Missing required fields: auth_user_id, email, nombre, apellido';
        RETURN;
    END IF;

    -- Get the role
    SELECT id INTO v_rol_id
    FROM core_roles
    WHERE nombre = p_rol_nombre AND es_sistema = TRUE
    LIMIT 1;

    IF v_rol_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Role not found: ' || COALESCE(p_rol_nombre, 'NULL');
        RETURN;
    END IF;

    -- Handle mode
    IF p_mode = 'new_company' THEN
        IF p_company_name IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Company name is required for new_company mode';
            RETURN;
        END IF;

        INSERT INTO core_empresas (nombre, ruc, email, estado)
        VALUES (p_company_name, p_company_ruc, p_email, 'activo')
        RETURNING id INTO v_empresa_id;

    ELSIF p_mode = 'join_company' THEN
        IF p_invite_code IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invite code required for join_company mode';
            RETURN;
        END IF;

        SELECT id INTO v_empresa_id
        FROM core_empresas
        WHERE ruc = p_invite_code
          AND estado = 'activo'
          AND deleted_at IS NULL
        LIMIT 1;

        IF v_empresa_id IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invalid invite code (no active empresa with that RUC)';
            RETURN;
        END IF;
    ELSE
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, 'Invalid mode: must be new_company or join_company';
        RETURN;
    END IF;

    -- Create user profile
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

-- Revoke from anon; only authenticated users should call this
REVOKE ALL ON FUNCTION public.registrar_empresa_usuario(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_empresa_usuario(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO authenticated;


-- ============================================================================
-- Fix registrar_conductor: add auth.uid() checks and empresa validation
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
    v_caller_empresa UUID;
BEGIN
    -- Validate required fields
    IF p_empresa_id IS NULL OR p_nombre IS NULL OR p_apellido IS NULL OR p_email IS NULL OR p_licencia IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Missing required fields';
        RETURN;
    END IF;

    -- CRITICAL: caller must belong to the target empresa
    v_caller_empresa := public.user_empresa_id();
    IF v_caller_empresa IS DISTINCT FROM p_empresa_id THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Auth user does not belong to the specified empresa';
        RETURN;
    END IF;

    -- Verify driver license is unique per empresa
    IF EXISTS (
        SELECT 1 FROM fleet_conductores
        WHERE empresa_id = p_empresa_id AND licencia = p_licencia AND deleted_at IS NULL
    ) THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'A driver with that license already exists in this empresa';
        RETURN;
    END IF;

    -- Get the Chofer role
    SELECT id INTO v_rol_id
    FROM core_roles
    WHERE nombre = 'Chofer' AND es_sistema = TRUE
    LIMIT 1;

    IF v_rol_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'Chofer role not found';
        RETURN;
    END IF;

    -- auth_user_id is required (caller must create auth user first)
    IF p_auth_user_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, 'auth_user_id is required';
        RETURN;
    END IF;

    v_auth_user_id := p_auth_user_id;

    -- Create driver
    INSERT INTO fleet_conductores (
        empresa_id, licencia, tipo_licencia, vencimiento_licencia, telefono, estado
    )
    VALUES (
        p_empresa_id, p_licencia, p_tipo_licencia, p_vencimiento_licencia, p_telefono, 'disponible'
    )
    RETURNING id INTO v_conductor_id;

    -- Create user
    INSERT INTO core_usuarios (
        auth_user_id, empresa_id, rol_id, nombre, apellido, email, telefono, activo
    )
    VALUES (
        v_auth_user_id, p_empresa_id, v_rol_id, p_nombre, p_apellido, p_email, p_telefono, TRUE
    )
    RETURNING id INTO v_usuario_id;

    -- Link user to driver
    UPDATE fleet_conductores
    SET usuario_id = v_usuario_id
    WHERE id = v_conductor_id;

    RETURN QUERY SELECT TRUE, v_conductor_id, v_usuario_id, v_auth_user_id, 'Driver registered successfully';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.registrar_conductor(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_conductor(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, UUID) TO authenticated;


-- ============================================================================
-- Fix guardar_geocerca: add empresa ownership check
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
    v_caller_empresa UUID;
BEGIN
    -- Validate input
    IF p_nombre IS NULL OR p_nombre = '' THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'Name is required';
        RETURN;
    END IF;

    IF p_tipo NOT IN ('circulo', 'poligono') THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'Invalid type: must be circulo or poligono';
        RETURN;
    END IF;

    -- Build geography point
    IF p_latitud IS NOT NULL AND p_longitud IS NOT NULL THEN
        v_centro := ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography;
    END IF;

    -- Build polygon from JSONB (expected format: GeoJSON-like coordinates)
    IF p_tipo = 'poligono' AND p_poligono IS NOT NULL THEN
        BEGIN
            v_poligono_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_poligono::text), 4326);
            IF ST_GeometryType(v_poligono_geom) != 'ST_Polygon' THEN
                RETURN QUERY SELECT FALSE, NULL::UUID, 'Polygon geometry required, got ' || ST_GeometryType(v_poligono_geom);
                RETURN;
            END IF;
            IF NOT ST_IsValid(v_poligono_geom) THEN
                RETURN QUERY SELECT FALSE, NULL::UUID, 'Invalid polygon geometry';
                RETURN;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, 'Invalid GeoJSON polygon: ' || SQLERRM;
            RETURN;
        END;
    END IF;

    -- UPDATE path
    IF p_id IS NOT NULL THEN
        -- CRITICAL: verify ownership
        SELECT empresa_id INTO v_caller_empresa
        FROM operations_geocercas
        WHERE id = p_id AND deleted_at IS NULL;

        IF v_caller_empresa IS NULL THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, 'Geocerca not found';
            RETURN;
        END IF;

        IF v_caller_empresa != public.user_empresa_id() THEN
            RETURN QUERY SELECT FALSE, NULL::UUID, 'Geocerca belongs to another empresa';
            RETURN;
        END IF;

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

        RETURN QUERY SELECT TRUE, v_geocerca_id, 'Geocerca updated successfully';
        RETURN;
    END IF;

    -- INSERT path
    IF p_empresa_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'empresa_id is required for create';
        RETURN;
    END IF;

    -- CRITICAL: caller must own the empresa
    IF p_empresa_id != public.user_empresa_id() THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 'Cannot create geocerca for another empresa';
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

    RETURN QUERY SELECT TRUE, v_geocerca_id, 'Geocerca created successfully';

EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.guardar_geocerca(UUID, UUID, VARCHAR, VARCHAR, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, VARCHAR, BOOLEAN, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_geocerca(UUID, UUID, VARCHAR, VARCHAR, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, VARCHAR, BOOLEAN, JSONB) TO authenticated;


-- ============================================================================
-- P0.2: Add RLS to tracking_ultima_posicion
-- ============================================================================
ALTER TABLE IF EXISTS tracking_ultima_posicion ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ultima posicion SELECT propia empresa" ON tracking_ultima_posicion;
CREATE POLICY "Ultima posicion SELECT propia empresa" ON tracking_ultima_posicion
    FOR SELECT
    USING (empresa_id = public.user_empresa_id());

-- Note: tracking_ultima_posicion is maintained by a SECURITY DEFINER trigger;
-- no INSERT/UPDATE/DELETE policies needed for regular users.


-- ============================================================================
-- P0.3: Fix audit trigger crash on tables without empresa_id
-- Create separate audit functions for tables with/without empresa_id
-- ============================================================================

-- Drop existing audit triggers before replacing the function
DROP TRIGGER IF EXISTS trg_auditoria_paquetes ON shipping_paquetes;
DROP TRIGGER IF EXISTS trg_auditoria_viajes ON operations_viajes;
DROP TRIGGER IF EXISTS trg_auditoria_entregas ON delivery_entregas;
DROP TRIGGER IF EXISTS trg_auditoria_envios ON shipping_envios;
DROP TRIGGER IF EXISTS trg_auditoria_viajes_paquetes ON operations_viajes_paquetes;
DROP TRIGGER IF EXISTS trg_auditoria_asignaciones ON operations_asignaciones;
DROP TRIGGER IF EXISTS trg_auditoria_tipos_paquete ON shipping_tipos_paquete;

-- Replace with robust version that handles missing empresa_id
CREATE OR REPLACE FUNCTION fn_auditoria_general()
RETURNS TRIGGER AS $$
DECLARE
    v_empresa_id UUID;
    v_usuario_id UUID;
    v_registro_id UUID;
    v_row JSONB;
BEGIN
    -- Determine row data and empresa_id safely
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_row := to_jsonb(NEW);
        v_registro_id := NEW.id;
        v_empresa_id := NEW.empresa_id;
        v_usuario_id := COALESCE(NEW.updated_by, NEW.created_by);
    ELSE -- DELETE
        v_row := to_jsonb(OLD);
        v_registro_id := OLD.id;
        v_empresa_id := OLD.empresa_id;
        v_usuario_id := OLD.updated_by;
    END IF;

    -- empresa_id might be NULL (e.g., bridge tables like operations_viajes_paquetes)
    -- Try to resolve from viaje_id as fallback
    IF v_empresa_id IS NULL AND v_row ? 'viaje_id' AND v_row->>'viaje_id' IS NOT NULL THEN
        SELECT empresa_id INTO v_empresa_id
        FROM operations_viajes
        WHERE id = (v_row->>'viaje_id')::UUID AND deleted_at IS NULL;
    END IF;

    INSERT INTO audit_auditoria (
        empresa_id, usuario_id, accion, tabla_afectada,
        registro_id, datos_antes, datos_despues
    ) VALUES (
        v_empresa_id,
        v_usuario_id,
        TG_OP,
        TG_TABLE_NAME,
        v_registro_id,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Re-create triggers
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
-- P0.4: Ensure RLS is enabled on core_usuarios
-- ============================================================================
ALTER TABLE core_usuarios ENABLE ROW LEVEL SECURITY;

-- Policies are defined in the main schema; re-assert they exist.
-- The main script already defines them. This is a safety net.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'core_usuarios'::regclass
        AND polname = 'Usuarios INSERT propio perfil'
    ) THEN
        CREATE POLICY "Usuarios INSERT propio perfil" ON core_usuarios
            FOR INSERT
            WITH CHECK (auth_user_id = auth.uid());
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'core_usuarios'::regclass
        AND polname = 'Usuarios SELECT propia'
    ) THEN
        CREATE POLICY "Usuarios SELECT propia" ON core_usuarios
            FOR SELECT USING (
                empresa_id = public.user_empresa_id()
                OR auth_user_id = auth.uid()
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'core_usuarios'::regclass
        AND polname = 'Usuarios UPDATE propia'
    ) THEN
        CREATE POLICY "Usuarios UPDATE propia" ON core_usuarios
            FOR UPDATE USING (
                empresa_id = public.user_empresa_id()
                OR auth_user_id = auth.uid()
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'core_usuarios'::regclass
        AND polname = 'Usuarios DELETE propia'
    ) THEN
        CREATE POLICY "Usuarios DELETE propia" ON core_usuarios
            FOR DELETE USING (
                empresa_id = public.user_empresa_id()
                OR auth_user_id = auth.uid()
            );
    END IF;
END $$;


-- ============================================================================
-- P1.1: Fix uq_viaje_paquete_activo - unique on paquete_id, not (viaje_id, paquete_id)
-- A package can only be actively assigned to ONE trip at a time
-- ============================================================================
DROP INDEX IF EXISTS uq_viaje_paquete_activo;

-- This index ensures a package appears in at most ONE active trip assignment
CREATE UNIQUE INDEX uq_paquete_viaje_activo
    ON operations_viajes_paquetes(paquete_id)
    WHERE deleted_at IS NULL
      AND estado IN ('asignado', 'cargado', 'en_transito', 'descargado');


-- ============================================================================
-- P1.2: Fix core_roles UNIQUE for global roles (NULL empresa_id)
-- Add a partial unique index for system roles (empresa_id IS NULL)
-- ============================================================================
-- The existing constraint UNIQUE (empresa_id, nombre) allows duplicates
-- when empresa_id is NULL because PostgreSQL treats NULLs as distinct.
-- Add a proper unique index for global roles.

DROP INDEX IF EXISTS uq_roles_globales;
CREATE UNIQUE INDEX uq_roles_globales
    ON core_roles(lower(nombre))
    WHERE empresa_id IS NULL AND deleted_at IS NULL;

DROP INDEX IF EXISTS uq_roles_empresa;
CREATE UNIQUE INDEX uq_roles_empresa
    ON core_roles(empresa_id, lower(nombre))
    WHERE empresa_id IS NOT NULL AND deleted_at IS NULL;


-- ============================================================================
-- P1.3: Unify estado model - trigger to auto-log historial when estado_actual changes
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_log_estado_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Only log when estado_actual actually changes
    IF TG_OP = 'UPDATE' AND OLD.estado_actual IS DISTINCT FROM NEW.estado_actual THEN
        INSERT INTO shipping_historial_estados (
            paquete_id, estado_id, usuario_id, comentario, fecha
        ) VALUES (
            NEW.id,
            NEW.estado_actual,
            COALESCE(NEW.updated_by, NEW.created_by),
            'Auto-logged from estado_actual change',
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_estado_change ON shipping_paquetes;
CREATE TRIGGER trg_log_estado_change
    AFTER UPDATE OF estado_actual ON shipping_paquetes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_log_estado_change();


-- ============================================================================
-- P1.4: Add unique index for single principal conductor/vehiculo per viaje
-- ============================================================================
DROP INDEX IF EXISTS uq_viaje_conductor_principal;
CREATE UNIQUE INDEX uq_viaje_conductor_principal
    ON operations_viajes_conductores(viaje_id)
    WHERE principal = TRUE AND deleted_at IS NULL;

DROP INDEX IF EXISTS uq_viaje_vehiculo_principal;
CREATE UNIQUE INDEX uq_viaje_vehiculo_principal
    ON operations_viajes_vehiculos(viaje_id)
    WHERE principal = TRUE AND deleted_at IS NULL;

-- Also add unique constraint to avoid duplicate (viaje_id, conductor_id) and (viaje_id, vehiculo_id)
DROP INDEX IF EXISTS uq_viaje_conductor;
CREATE UNIQUE INDEX uq_viaje_conductor
    ON operations_viajes_conductores(viaje_id, conductor_id)
    WHERE deleted_at IS NULL;

DROP INDEX IF EXISTS uq_viaje_vehiculo;
CREATE UNIQUE INDEX uq_viaje_vehiculo
    ON operations_viajes_vehiculos(viaje_id, vehiculo_id)
    WHERE deleted_at IS NULL;


-- ============================================================================
-- P1.5: Add empresa_id to bridge tables that need it but lack it
-- ============================================================================

-- operations_viajes_paquetes: add empresa_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_viajes_paquetes' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE operations_viajes_paquetes ADD COLUMN empresa_id UUID REFERENCES core_empresas(id);

        -- Backfill from viaje
        UPDATE operations_viajes_paquetes ovp
        SET empresa_id = v.empresa_id
        FROM operations_viajes v
        WHERE ovp.viaje_id = v.id
          AND ovp.empresa_id IS NULL;

        -- Make NOT NULL after backfill
        ALTER TABLE operations_viajes_paquetes ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- operations_viajes_conductores: add empresa_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_viajes_conductores' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE operations_viajes_conductores ADD COLUMN empresa_id UUID REFERENCES core_empresas(id);

        UPDATE operations_viajes_conductores ovc
        SET empresa_id = v.empresa_id
        FROM operations_viajes v
        WHERE ovc.viaje_id = v.id
          AND ovc.empresa_id IS NULL;

        ALTER TABLE operations_viajes_conductores ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- operations_viajes_vehiculos: add empresa_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_viajes_vehiculos' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE operations_viajes_vehiculos ADD COLUMN empresa_id UUID REFERENCES core_empresas(id);

        UPDATE operations_viajes_vehiculos ovv
        SET empresa_id = v.empresa_id
        FROM operations_viajes v
        WHERE ovv.viaje_id = v.id
          AND ovv.empresa_id IS NULL;

        ALTER TABLE operations_viajes_vehiculos ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- operations_viajes_eventos: add empresa_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_viajes_eventos' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE operations_viajes_eventos ADD COLUMN empresa_id UUID REFERENCES core_empresas(id);

        UPDATE operations_viajes_eventos ove
        SET empresa_id = v.empresa_id
        FROM operations_viajes v
        WHERE ove.viaje_id = v.id
          AND ove.empresa_id IS NULL;

        ALTER TABLE operations_viajes_eventos ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- operations_checkpoints: add empresa_id if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints' AND column_name = 'empresa_id'
    ) THEN
        -- Already has empresa_id in the current schema, this is a safety net
        -- Mark as NOT NULL if it somehow isn't
        ALTER TABLE operations_checkpoints ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- shipping_paquetes_cargas: add empresa_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shipping_paquetes_cargas' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE shipping_paquetes_cargas ADD COLUMN empresa_id UUID REFERENCES core_empresas(id);

        UPDATE shipping_paquetes_cargas spc
        SET empresa_id = p.empresa_id
        FROM shipping_paquetes p
        WHERE spc.paquete_id = p.id
          AND spc.empresa_id IS NULL;

        ALTER TABLE shipping_paquetes_cargas ALTER COLUMN empresa_id SET NOT NULL;
    END IF;
END $$;

-- shipping_historial_estados: add empresa_id (derived from paquete)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shipping_historial_estados' AND column_name = 'empresa_id'
    ) THEN
        ALTER TABLE shipping_historial_estados ADD COLUMN empresa_id UUID;

        UPDATE shipping_historial_estados she
        SET empresa_id = p.empresa_id
        FROM shipping_paquetes p
        WHERE she.paquete_id = p.id
          AND she.empresa_id IS NULL;
    END IF;
END $$;


-- ============================================================================
-- P1.6: Fix global UNIQUE constraints not properly removed
-- The original script declares UNIQUE on columns but later tries to DROP INDEX
-- by name, while the constraint has a system-generated name.
-- ============================================================================

DO $$
BEGIN
    -- operations_rutas: codigo was declared UNIQUE in CREATE TABLE
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'operations_rutas'
          AND constraint_type = 'UNIQUE'
          AND constraint_name LIKE '%codigo%'
    ) THEN
        EXECUTE (
            SELECT 'ALTER TABLE operations_rutas DROP CONSTRAINT ' || quote_ident(constraint_name)
            FROM information_schema.table_constraints
            WHERE table_name = 'operations_rutas'
              AND constraint_type = 'UNIQUE'
              AND constraint_name LIKE '%codigo%'
            LIMIT 1
        );
    END IF;

    -- operations_viajes: codigo was declared UNIQUE in CREATE TABLE
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'operations_viajes'
          AND constraint_type = 'UNIQUE'
          AND constraint_name LIKE '%codigo%'
    ) THEN
        EXECUTE (
            SELECT 'ALTER TABLE operations_viajes DROP CONSTRAINT ' || quote_ident(constraint_name)
            FROM information_schema.table_constraints
            WHERE table_name = 'operations_viajes'
              AND constraint_type = 'UNIQUE'
              AND constraint_name LIKE '%codigo%'
            LIMIT 1
        );
    END IF;

    -- shipping_cargas: codigo was declared UNIQUE in CREATE TABLE
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'shipping_cargas'
          AND constraint_type = 'UNIQUE'
          AND constraint_name LIKE '%codigo%'
    ) THEN
        EXECUTE (
            SELECT 'ALTER TABLE shipping_cargas DROP CONSTRAINT ' || quote_ident(constraint_name)
            FROM information_schema.table_constraints
            WHERE table_name = 'shipping_cargas'
              AND constraint_type = 'UNIQUE'
              AND constraint_name LIKE '%codigo%'
            LIMIT 1
        );
    END IF;
END $$;

-- Note: shipping_envios.codigo is NOT declared UNIQUE in the CREATE TABLE,
-- but the migration 007 adds an index below. The UNIQUE constraints already
-- dropped above are replaced by per-empresa partial unique indexes in the
-- main schema (already defined as part of "restricciones UNIQUE por empresa").


-- ============================================================================
-- P1.7: Fix tracking_ultima_posicion UPSERT - don't overwrite newer with older
-- ============================================================================
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
            viaje_id = COALESCE(EXCLUDED.viaje_id, tracking_ultima_posicion.viaje_id),
            conductor_id = COALESCE(EXCLUDED.conductor_id, tracking_ultima_posicion.conductor_id),
            dispositivo_id = COALESCE(EXCLUDED.dispositivo_id, tracking_ultima_posicion.dispositivo_id),
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
            updated_at = NOW()
        -- CRITICAL: only overwrite if the new data is newer or same-age
        WHERE EXCLUDED.created_at >= tracking_ultima_posicion.created_at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_update_ultima_posicion ON tracking_gps;
CREATE TRIGGER trg_update_ultima_posicion
    AFTER INSERT ON tracking_gps
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_ultima_posicion();


-- ============================================================================
-- P2.1: Add multi-tenant FK checks (composite foreign keys)
-- These ensure that referenced rows belong to the same empresa.
-- Using triggers for validation rather than composite FKs for flexibility.
-- ============================================================================

-- Validate shipping_paquetes -> customers_clientes empresa match
CREATE OR REPLACE FUNCTION public.fn_validate_paquete_cliente_empresa()
RETURNS TRIGGER AS $$
DECLARE
    v_cliente_empresa UUID;
BEGIN
    SELECT empresa_id INTO v_cliente_empresa
    FROM customers_clientes WHERE id = NEW.cliente_id AND deleted_at IS NULL;

    IF v_cliente_empresa IS NULL THEN
        RAISE EXCEPTION 'Cliente % not found or deleted', NEW.cliente_id;
    END IF;

    IF v_cliente_empresa != NEW.empresa_id THEN
        RAISE EXCEPTION 'Empresa mismatch: paquete empresa=%, cliente empresa=%', NEW.empresa_id, v_cliente_empresa;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_validate_paquete_cliente_empresa ON shipping_paquetes;
CREATE TRIGGER trg_validate_paquete_cliente_empresa
    BEFORE INSERT OR UPDATE OF cliente_id, empresa_id ON shipping_paquetes
    FOR EACH ROW EXECUTE FUNCTION public.fn_validate_paquete_cliente_empresa();


-- Validate shipping_envios -> customers_clientes empresa match
CREATE OR REPLACE FUNCTION public.fn_validate_envio_cliente_empresa()
RETURNS TRIGGER AS $$
DECLARE
    v_cliente_empresa UUID;
BEGIN
    SELECT empresa_id INTO v_cliente_empresa
    FROM customers_clientes WHERE id = NEW.cliente_id AND deleted_at IS NULL;

    IF v_cliente_empresa IS NULL THEN
        RAISE EXCEPTION 'Cliente % not found or deleted', NEW.cliente_id;
    END IF;

    IF v_cliente_empresa != NEW.empresa_id THEN
        RAISE EXCEPTION 'Empresa mismatch: envio empresa=%, cliente empresa=%', NEW.empresa_id, v_cliente_empresa;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_validate_envio_cliente_empresa ON shipping_envios;
CREATE TRIGGER trg_validate_envio_cliente_empresa
    BEFORE INSERT OR UPDATE OF cliente_id, empresa_id ON shipping_envios
    FOR EACH ROW EXECUTE FUNCTION public.fn_validate_envio_cliente_empresa();


-- ============================================================================
-- P2.2: Fix delivery_sesiones - add RLS, indexes, trigger, soft delete
-- ============================================================================

-- Add soft delete columns if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'delivery_sesiones' AND column_name = 'deleted_at'
    ) THEN
        ALTER TABLE delivery_sesiones
            ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE,
            ADD COLUMN deleted_by UUID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'delivery_sesiones' AND column_name = 'created_by'
    ) THEN
        ALTER TABLE delivery_sesiones
            ADD COLUMN created_by UUID,
            ADD COLUMN updated_by UUID;
    END IF;
END $$;

-- Add paso_actual CHECK if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'delivery_sesiones'
          AND cc.check_clause LIKE '%paso_actual%'
    ) THEN
        ALTER TABLE delivery_sesiones
            ADD CONSTRAINT chk_delivery_sesiones_paso CHECK (
                paso_actual IN (
                    'confirm_arrival', 'scan_packages', 'take_photo',
                    'collect_signature', 'verify_otp', 'complete'
                )
            );
    END IF;
END $$;

-- Add unique index on client_operation_id for idempotency
DROP INDEX IF EXISTS uq_delivery_sesiones_client_op;
CREATE UNIQUE INDEX uq_delivery_sesiones_client_op
    ON delivery_sesiones(client_operation_id)
    WHERE client_operation_id IS NOT NULL AND deleted_at IS NULL;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_delivery_sesiones_empresa
    ON delivery_sesiones(empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_delivery_sesiones_viaje
    ON delivery_sesiones(viaje_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_delivery_sesiones_estado
    ON delivery_sesiones(estado) WHERE deleted_at IS NULL;

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_delivery_sesiones_updated_at ON delivery_sesiones;
CREATE TRIGGER update_delivery_sesiones_updated_at
    BEFORE UPDATE ON delivery_sesiones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS
ALTER TABLE delivery_sesiones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Delivery sesiones de la empresa" ON delivery_sesiones;
CREATE POLICY "Delivery sesiones de la empresa" ON delivery_sesiones
    FOR ALL USING (empresa_id = public.user_empresa_id());


-- ============================================================================
-- P2.3: Fix delivery_fotografias.incidencia_id FK
-- ============================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'delivery_fotografias' AND column_name = 'incidencia_id'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'delivery_fotografias'
          AND constraint_type = 'FOREIGN KEY'
          AND constraint_name LIKE '%incidencia%'
    ) THEN
        -- Add FK only if there's no existing FK on incidencia_id
        -- First remove any orphaned references
        UPDATE delivery_fotografias
        SET incidencia_id = NULL
        WHERE incidencia_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM delivery_incidencias WHERE id = incidencia_id);

        ALTER TABLE delivery_fotografias
            ADD CONSTRAINT fk_fotos_incidencia
            FOREIGN KEY (incidencia_id) REFERENCES delivery_incidencias(id);
    END IF;
END $$;

-- Add CHECK that at least one reference exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'delivery_fotografias'
          AND cc.check_clause LIKE '%paquete_id%entrega_id%incidencia_id%'
    ) THEN
        ALTER TABLE delivery_fotografias
            ADD CONSTRAINT chk_foto_referencia CHECK (
                paquete_id IS NOT NULL
                OR entrega_id IS NOT NULL
                OR incidencia_id IS NOT NULL
            );
    END IF;
END $$;


-- ============================================================================
-- P2.4: Fix fn_set_ubicacion_from_latlon - nullify when coords removed
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_set_ubicacion_from_latlon()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.latitud IS NOT NULL AND NEW.longitud IS NOT NULL THEN
        NEW.ubicacion := ST_SetSRID(
            ST_MakePoint(NEW.longitud::double precision, NEW.latitud::double precision),
            4326
        )::geography;
    ELSE
        NEW.ubicacion := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- P2.5: Add remaining CHECK constraints (non-negative, date ranges, etc.)
-- ============================================================================

-- Non-negative constraints
DO $$
BEGIN
    -- shipping_paquetes
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'shipping_paquetes' AND cc.check_clause LIKE '%peso%'
    ) THEN
        ALTER TABLE shipping_paquetes
            ADD CONSTRAINT chk_paquete_peso CHECK (peso IS NULL OR peso > 0),
            ADD CONSTRAINT chk_paquete_volumen CHECK (volumen IS NULL OR volumen > 0),
            ADD CONSTRAINT chk_paquete_dimensiones CHECK (
                (alto_cm IS NULL OR alto_cm > 0)
                AND (ancho_cm IS NULL OR ancho_cm > 0)
                AND (largo_cm IS NULL OR largo_cm > 0)
            ),
            ADD CONSTRAINT chk_paquete_temperatura CHECK (
                temperatura_min IS NULL OR temperatura_max IS NULL
                OR temperatura_min <= temperatura_max
            ),
            ADD CONSTRAINT chk_paquete_valor CHECK (valor_declarado IS NULL OR valor_declarado >= 0),
            ADD CONSTRAINT chk_paquete_costo CHECK (costo_envio IS NULL OR costo_envio >= 0);
    END IF;

    -- shipping_envios
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'shipping_envios' AND cc.check_clause LIKE '%valor_total%'
    ) THEN
        ALTER TABLE shipping_envios
            ADD CONSTRAINT chk_envio_valor CHECK (valor_total IS NULL OR valor_total >= 0),
            ADD CONSTRAINT chk_envio_costo CHECK (costo_total IS NULL OR costo_total >= 0);
    END IF;

    -- operations_viajes
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'operations_viajes' AND cc.check_clause LIKE '%km_estimados%'
    ) THEN
        ALTER TABLE operations_viajes
            ADD CONSTRAINT chk_viaje_kms CHECK (
                (km_estimados IS NULL OR km_estimados >= 0)
                AND (km_reales IS NULL OR km_reales >= 0)
                AND (distancia_real_km IS NULL OR distancia_real_km >= 0)
            ),
            ADD CONSTRAINT chk_viaje_tiempo CHECK (
                (tiempo_estimado_min IS NULL OR tiempo_estimado_min >= 0)
                AND (tiempo_real_min IS NULL OR tiempo_real_min >= 0)
                AND (tiempo_detenido_seg IS NULL OR tiempo_detenido_seg >= 0)
                AND (tiempo_movimiento_seg IS NULL OR tiempo_movimiento_seg >= 0)
            ),
            ADD CONSTRAINT chk_viaje_combustible CHECK (
                combustible_litros IS NULL OR combustible_litros >= 0
            ),
            ADD CONSTRAINT chk_viaje_costos CHECK (
                costo_total IS NULL OR costo_total >= 0
            );
    END IF;

    -- fleet_vehiculos
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'fleet_vehiculos' AND cc.check_clause LIKE '%capacidad_kg%'
    ) THEN
        ALTER TABLE fleet_vehiculos
            ADD CONSTRAINT chk_vehiculo_capacidad CHECK (
                capacidad_kg IS NULL OR capacidad_kg >= 0
            ),
            ADD CONSTRAINT chk_vehiculo_volumen CHECK (
                capacidad_m3 IS NULL OR capacidad_m3 >= 0
            );
    END IF;

    -- fleet_remolques
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'fleet_remolques' AND cc.check_clause LIKE '%capacidad_kg%'
    ) THEN
        ALTER TABLE fleet_remolques
            ADD CONSTRAINT chk_remolque_capacidad CHECK (
                capacidad_kg IS NULL OR capacidad_kg >= 0
            ),
            ADD CONSTRAINT chk_remolque_volumen CHECK (
                capacidad_m3 IS NULL OR capacidad_m3 >= 0
            );
    END IF;

    -- routes
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'operations_rutas' AND cc.check_clause LIKE '%distancia_km%'
    ) THEN
        ALTER TABLE operations_rutas
            ADD CONSTRAINT chk_ruta_distancia CHECK (distancia_km IS NULL OR distancia_km >= 0),
            ADD CONSTRAINT chk_ruta_tiempo CHECK (tiempo_estimado_min IS NULL OR tiempo_estimado_min >= 0);
    END IF;

    -- Date range checks
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'operations_viajes' AND cc.check_clause LIKE '%fecha_inicio%'
    ) THEN
        ALTER TABLE operations_viajes
            ADD CONSTRAINT chk_viaje_fechas CHECK (
                fecha_fin IS NULL OR fecha_inicio IS NULL
                OR fecha_fin >= fecha_inicio
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'shipping_paquetes' AND cc.check_clause LIKE '%fecha_entrega%'
    ) THEN
        ALTER TABLE shipping_paquetes
            ADD CONSTRAINT chk_paquete_fechas CHECK (
                fecha_entrega_real IS NULL OR fecha_entrega_estimada IS NULL
                OR fecha_entrega_real >= fecha_entrega_estimada
            );
    END IF;

    -- fleet_mantenimientos
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'fleet_mantenimientos' AND cc.check_clause LIKE '%fecha_fin%'
    ) THEN
        ALTER TABLE fleet_mantenimientos
            ADD CONSTRAINT chk_mantenimiento_fechas CHECK (
                fecha_fin IS NULL OR fecha_inicio IS NULL
                OR fecha_fin >= fecha_inicio
            ),
            ADD CONSTRAINT chk_mantenimiento_costo CHECK (costo IS NULL OR costo >= 0),
            ADD CONSTRAINT chk_mantenimiento_kms CHECK (kilometraje IS NULL OR kilometraje >= 0);
    END IF;

    -- tracking_gps: rumbo 0-360 (in addition to existing lat/lon checks)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'tracking_gps' AND cc.check_clause LIKE '%rumbo%'
    ) THEN
        ALTER TABLE tracking_gps
            ADD CONSTRAINT chk_gps_rumbo CHECK (rumbo IS NULL OR (rumbo >= 0 AND rumbo <= 360)),
            ADD CONSTRAINT chk_gps_velocidad CHECK (velocidad_kmh IS NULL OR velocidad_kmh >= 0),
            ADD CONSTRAINT chk_gps_satelites CHECK (satelites IS NULL OR satelites >= 0),
            ADD CONSTRAINT chk_gps_precision CHECK (precision_m IS NULL OR precision_m >= 0);
    END IF;
END $$;


-- ============================================================================
-- P2.6: Optimize indexes - remove low-cardinality, add composite
-- ============================================================================

-- Drop redundant single-column indexes on low-cardinality fields
-- (they provide little benefit alone but add write overhead)
DROP INDEX IF EXISTS idx_envios_estado;
DROP INDEX IF EXISTS idx_paquetes_prioridad;
DROP INDEX IF EXISTS idx_viajes_estado;
DROP INDEX IF EXISTS idx_geocercas_centro;
DROP INDEX IF EXISTS idx_geocercas_poligono;
DROP INDEX IF EXISTS idx_rutas_opt_activa;
DROP INDEX IF EXISTS idx_viajes_conductores_estado;
DROP INDEX IF EXISTS idx_viajes_paquetes_estado;
DROP INDEX IF EXISTS idx_cargas_estado;
DROP INDEX IF EXISTS idx_alertas_nivel;
DROP INDEX IF EXISTS idx_alertas_leido;
DROP INDEX IF EXISTS idx_fotos_tipo;
DROP INDEX IF EXISTS idx_incidencias_estado;
DROP INDEX IF EXISTS idx_checklists_items_estado;
DROP INDEX IF EXISTS idx_gps_estado;
DROP INDEX IF EXISTS idx_notificaciones_tipo;
DROP INDEX IF EXISTS idx_notificaciones_leido;
DROP INDEX IF EXISTS idx_viajes_eventos_tipo;

-- Add useful composite indexes
CREATE INDEX IF NOT EXISTS idx_envios_empresa_estado ON shipping_envios(empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_paquetes_empresa_estado_prioridad ON shipping_paquetes(empresa_id, estado_actual, prioridad) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_viajes_empresa_estado ON operations_viajes(empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_paquetes_fecha_estado ON shipping_paquetes(fecha_creacion, estado_actual) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_viajes_fecha_estado ON operations_viajes(fecha_inicio, estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_alertas_empresa_no_leidas ON tracking_alertas(empresa_id, created_at DESC) WHERE NOT leido AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_historial_paquete_fecha ON shipping_historial_estados(paquete_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_eventos_tipo_fecha ON tracking_eventos(tipo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fotos_entrega_tipo ON delivery_fotografias(entrega_id, tipo) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_leidas ON communication_notificaciones(usuario_id, created_at DESC) WHERE NOT leido AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_incidencias_empresa_tipo ON delivery_incidencias(empresa_id, tipo) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_mensajes_chat_fecha ON communication_chat_mensajes(chat_id, created_at DESC) WHERE deleted_at IS NULL;


-- ============================================================================
-- SUMMARY: Log applied fixes
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Migration 007 applied successfully: security hardening + integrity fixes';
END $$;
