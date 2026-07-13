-- ============================================================================
-- MIGRATION 005: Trigger robusto que genera checkpoints SIN requerir paradas
-- ============================================================================
-- Esta versión:
--   1. Genera checkpoints desde paradas si existen
--   2. Si no hay paradas, genera UN checkpoint genérico para que el viaje
--      sea visible en la app
-- ============================================================================

-- 1. Reemplazar función del trigger
CREATE OR REPLACE FUNCTION public.fn_auto_generate_checkpoints()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_parada_count INTEGER;
BEGIN
    -- 1. Si no hay ruta, no generar nada
    IF NEW.ruta_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- 2. Si ya hay checkpoints para este viaje, no duplicar
    IF EXISTS (
        SELECT 1 FROM operations_checkpoints
        WHERE viaje_id = NEW.id
          AND deleted_at IS NULL
    ) THEN
        RETURN NEW;
    END IF;

    -- 3. Contar paradas de la ruta
    SELECT COUNT(*)::INTEGER INTO v_parada_count
    FROM operations_paradas
    WHERE ruta_id = NEW.ruta_id
      AND deleted_at IS NULL;

    -- 4. Si hay paradas, generar un checkpoint por cada una
    IF v_parada_count > 0 THEN
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
    ELSE
        -- 5. Si NO hay paradas, generar UN checkpoint genérico
        --    para que la RPC pueda devolver el viaje
        INSERT INTO operations_checkpoints (
            empresa_id,
            viaje_id,
            parada_id,
            estado,
            latitud,
            longitud
        ) VALUES (
            NEW.empresa_id,
            NEW.id,
            NULL,
            'pendiente',
            NULL,
            NULL
        );
    END IF;

    RETURN NEW;
END;
$$;

-- 2. El trigger se mantiene igual
DROP TRIGGER IF EXISTS trg_auto_generate_checkpoints ON operations_viajes;

CREATE TRIGGER trg_auto_generate_checkpoints
    AFTER INSERT OR UPDATE OF ruta_id ON operations_viajes
    FOR EACH ROW
    WHEN (NEW.ruta_id IS NOT NULL AND NEW.deleted_at IS NULL)
    EXECUTE FUNCTION public.fn_auto_generate_checkpoints();

-- 3. Backfill: generar checkpoints para viajes existentes que no los tienen
DO $$
DECLARE
    v_viaje RECORD;
    v_parada_count INTEGER;
    v_count INTEGER := 0;
BEGIN
    FOR v_viaje IN
        SELECT v.id, v.empresa_id, v.ruta_id, v.codigo
        FROM operations_viajes v
        WHERE v.deleted_at IS NULL
          AND v.ruta_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM operations_checkpoints
              WHERE viaje_id = v.id AND deleted_at IS NULL
          )
    LOOP
        -- Contar paradas
        SELECT COUNT(*)::INTEGER INTO v_parada_count
        FROM operations_paradas
        WHERE ruta_id = v_viaje.ruta_id AND deleted_at IS NULL;

        -- Generar checkpoints según haya paradas o no
        IF v_parada_count > 0 THEN
            INSERT INTO operations_checkpoints (
                empresa_id, viaje_id, parada_id, estado, latitud, longitud
            )
            SELECT
                v_viaje.empresa_id, v_viaje.id, p.id, 'pendiente', p.latitud, p.longitud
            FROM operations_paradas p
            WHERE p.ruta_id = v_viaje.ruta_id AND p.deleted_at IS NULL
            ORDER BY p.orden;
        ELSE
            INSERT INTO operations_checkpoints (
                empresa_id, viaje_id, parada_id, estado, latitud, longitud
            ) VALUES (
                v_viaje.empresa_id, v_viaje.id, NULL, 'pendiente', NULL, NULL
            );
        END IF;

        v_count := v_count + 1;
        RAISE NOTICE 'Checkpoints generados para viaje %', v_viaje.codigo;
    END LOOP;

    RAISE NOTICE 'Total viajes procesados: %', v_count;
END $$;
