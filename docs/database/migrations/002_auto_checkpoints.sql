-- ============================================================================
-- MIGRATION 002: Add empresa_id to checkpoints + auto-generate on trip create
-- Run AFTER tracking.sql and 001_delivery_rpcs.sql
-- ============================================================================

-- ============================================================================
-- 1. Add empresa_id column to operations_checkpoints
--    (nullable first to allow adding the column without rewriting the table,
--     then we backfill, then we make it NOT NULL)
-- ============================================================================
ALTER TABLE operations_checkpoints
    ADD COLUMN IF NOT EXISTS empresa_id UUID
    REFERENCES core_empresas(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_checkpoints_empresa
    ON operations_checkpoints(empresa_id) WHERE deleted_at IS NULL;

-- ============================================================================
-- 2. Backfill: copy empresa_id from the parent trip for existing checkpoints
-- ============================================================================
UPDATE operations_checkpoints oc
SET empresa_id = v.empresa_id
FROM operations_viajes v
WHERE oc.viaje_id = v.id
  AND oc.empresa_id IS NULL;

-- ============================================================================
-- 3. Function: auto-generate checkpoints from the trip's route
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_auto_generate_checkpoints()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only generate if the trip has a ruta_id
    IF NEW.ruta_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip if checkpoints already exist for this trip
    IF EXISTS (
        SELECT 1 FROM operations_checkpoints
        WHERE viaje_id = NEW.id
          AND deleted_at IS NULL
    ) THEN
        RETURN NEW;
    END IF;

    -- Skip if the route has no paradas
    IF NOT EXISTS (
        SELECT 1 FROM operations_paradas
        WHERE ruta_id = NEW.ruta_id
          AND deleted_at IS NULL
    ) THEN
        RETURN NEW;
    END IF;

    -- Generate one checkpoint per parada, ordered
    INSERT INTO operations_checkpoints (
        empresa_id,
        viaje_id,
        parada_id,
        estado,
        latitud,
        longitud
    )
    SELECT
        NEW.empresa_id,
        NEW.id,
        p.id,
        'pendiente',
        p.latitud,
        p.longitud
    FROM operations_paradas p
    WHERE p.ruta_id = NEW.ruta_id
      AND p.deleted_at IS NULL
    ORDER BY p.orden;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 4. Trigger: fires after INSERT or UPDATE of ruta_id on operations_viajes
-- ============================================================================
DROP TRIGGER IF EXISTS trg_auto_generate_checkpoints ON operations_viajes;

CREATE TRIGGER trg_auto_generate_checkpoints
    AFTER INSERT OR UPDATE OF ruta_id ON operations_viajes
    FOR EACH ROW
    WHEN (NEW.ruta_id IS NOT NULL AND NEW.deleted_at IS NULL)
    EXECUTE FUNCTION public.fn_auto_generate_checkpoints();

-- ============================================================================
-- 5. Backfill: generate checkpoints for existing trips that have a route
--    but no checkpoints yet
-- ============================================================================
DO $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    WITH inserted AS (
        INSERT INTO operations_checkpoints (
            empresa_id,
            viaje_id,
            parada_id,
            estado,
            latitud,
            longitud
        )
        SELECT
            v.empresa_id,
            v.id,
            p.id,
            'pendiente',
            p.latitud,
            p.longitud
        FROM operations_viajes v
        JOIN operations_paradas p ON p.ruta_id = v.ruta_id
        WHERE v.ruta_id IS NOT NULL
          AND v.deleted_at IS NULL
          AND p.deleted_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM operations_checkpoints oc
              WHERE oc.viaje_id = v.id
                AND oc.parada_id = p.id
                AND oc.deleted_at IS NULL
          )
        ORDER BY v.id, p.orden
        RETURNING id
    )
    SELECT COUNT(*) INTO v_count FROM inserted;

    RAISE NOTICE 'Backfill: % checkpoints generados', v_count;
END $$;
