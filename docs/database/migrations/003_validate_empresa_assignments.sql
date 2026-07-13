-- ============================================================================
-- MIGRATION 003: Validate conductor_id.empresa_id matches viaje.empresa_id
-- Close the RLS hole that allows assigning conductors from other empresas
-- ============================================================================

-- ============================================================================
-- 1. Function: validate conductor belongs to same empresa as trip
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_validate_viaje_conductor_empresa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trip_empresa_id UUID;
    v_conductor_empresa_id UUID;
BEGIN
    -- Get the trip's empresa
    SELECT empresa_id INTO v_trip_empresa_id
    FROM operations_viajes
    WHERE id = NEW.viaje_id AND deleted_at IS NULL;

    IF v_trip_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Trip % not found or deleted', NEW.viaje_id;
    END IF;

    -- Get the conductor's empresa
    SELECT empresa_id INTO v_conductor_empresa_id
    FROM fleet_conductores
    WHERE id = NEW.conductor_id AND deleted_at IS NULL;

    IF v_conductor_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Conductor % not found or deleted', NEW.conductor_id;
    END IF;

    -- Validate match
    IF v_trip_empresa_id != v_conductor_empresa_id THEN
        RAISE EXCEPTION
            'Empresa mismatch: trip % belongs to empresa %, but conductor % belongs to empresa %',
            NEW.viaje_id, v_trip_empresa_id, NEW.conductor_id, v_conductor_empresa_id;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Trigger: enforce validation on INSERT and UPDATE
-- ============================================================================
DROP TRIGGER IF EXISTS trg_validate_viaje_conductor_empresa
    ON operations_viajes_conductores;

CREATE TRIGGER trg_validate_viaje_conductor_empresa
    BEFORE INSERT OR UPDATE OF viaje_id, conductor_id
    ON operations_viajes_conductores
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_viaje_conductor_empresa();

-- ============================================================================
-- 3. Same validation for vehicles (operations_viajes_vehiculos)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_validate_viaje_vehiculo_empresa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trip_empresa_id UUID;
    v_vehiculo_empresa_id UUID;
BEGIN
    SELECT empresa_id INTO v_trip_empresa_id
    FROM operations_viajes
    WHERE id = NEW.viaje_id AND deleted_at IS NULL;

    IF v_trip_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Trip % not found or deleted', NEW.viaje_id;
    END IF;

    SELECT empresa_id INTO v_vehiculo_empresa_id
    FROM fleet_vehiculos
    WHERE id = NEW.vehiculo_id AND deleted_at IS NULL;

    IF v_vehiculo_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Vehicle % not found or deleted', NEW.vehiculo_id;
    END IF;

    IF v_trip_empresa_id != v_vehiculo_empresa_id THEN
        RAISE EXCEPTION
            'Empresa mismatch: trip % belongs to empresa %, but vehicle % belongs to empresa %',
            NEW.viaje_id, v_trip_empresa_id, NEW.vehiculo_id, v_vehiculo_empresa_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_viaje_vehiculo_empresa
    ON operations_viajes_vehiculos;

CREATE TRIGGER trg_validate_viaje_vehiculo_empresa
    BEFORE INSERT OR UPDATE OF viaje_id, vehiculo_id
    ON operations_viajes_vehiculos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_validate_viaje_vehiculo_empresa();

-- ============================================================================
-- 4. Backfill: identify existing cross-empresa violations (if any)
-- ============================================================================
DO $$
DECLARE
    v_bad_conductor INTEGER := 0;
    v_bad_vehiculo INTEGER := 0;
BEGIN
    SELECT COUNT(*) INTO v_bad_conductor
    FROM operations_viajes_conductores ovc
    JOIN operations_viajes v ON v.id = ovc.viaje_id
    JOIN fleet_conductores fc ON fc.id = ovc.conductor_id
    WHERE v.empresa_id != fc.empresa_id;

    SELECT COUNT(*) INTO v_bad_vehiculo
    FROM operations_viajes_vehiculos ovv
    JOIN operations_viajes v ON v.id = ovv.viaje_id
    JOIN fleet_vehiculos fv ON fv.id = ovv.vehiculo_id
    WHERE v.empresa_id != fv.empresa_id;

    RAISE NOTICE 'Existing cross-empresa violations: % conductores, % vehiculos',
        v_bad_conductor, v_bad_vehiculo;
END $$;
