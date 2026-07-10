-- ============================================================================
-- MIGRATION: RPC Functions for Delivery App
-- Run this AFTER tracking.sql
-- ============================================================================

-- ============================================================================
-- 1. complete_delivery
-- Called by SyncEngine to mark a delivery as completed
-- ============================================================================
CREATE OR REPLACE FUNCTION public.complete_delivery(
    p_checkpoint_id UUID,
    p_trip_id UUID,
    p_stop_id UUID,
    p_outcome VARCHAR(50),
    p_incident_reason TEXT DEFAULT NULL,
    p_packages_delivered INTEGER DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_checkpoint operations_checkpoints%ROWTYPE;
    v_trip operations_viajes%ROWTYPE;
    v_new_stops_progress INTEGER;
    v_total_stops INTEGER;
    v_trip_completed BOOLEAN := FALSE;
    v_result JSONB;
BEGIN
    -- 1. Get and validate checkpoint
    SELECT * INTO v_checkpoint
    FROM operations_checkpoints
    WHERE id = p_checkpoint_id
      AND viaje_id = p_trip_id
      AND deleted_at IS NULL;

    IF v_checkpoint IS NULL THEN
        RAISE EXCEPTION 'Checkpoint not found: %', p_checkpoint_id;
    END IF;

    -- 2. Update checkpoint
    UPDATE operations_checkpoints
    SET
        estado = CASE
            WHEN p_outcome = 'complete' THEN 'completado'
            WHEN p_outcome = 'incident' THEN 'completado'
            ELSE estado
        END,
        hora_salida = NOW(),
        observaciones = CASE
            WHEN p_incident_reason IS NOT NULL THEN p_incident_reason
            ELSE observaciones
        END,
        updated_at = NOW()
    WHERE id = p_checkpoint_id;

    -- 3. Get trip info
    SELECT * INTO v_trip
    FROM operations_viajes
    WHERE id = p_trip_id AND deleted_at IS NULL;

    IF v_trip IS NULL THEN
        RAISE EXCEPTION 'Trip not found: %', p_trip_id;
    END IF;

    v_total_stops := COALESCE(v_trip.total_stops, 0);
    v_new_stops_progress := COALESCE(v_trip.stops_progress, 0) + 1;

    -- 4. Update trip progress
    UPDATE operations_viajes
    SET
        stops_progress = v_new_stops_progress,
        updated_at = NOW(),
        estado = CASE
            WHEN v_new_stops_progress >= v_total_stops AND v_total_stops > 0
                THEN 'completado'
            ELSE estado
        END,
        fecha_fin = CASE
            WHEN v_new_stops_progress >= v_total_stops AND v_total_stops > 0
                THEN NOW()
            ELSE fecha_fin
        END
    WHERE id = p_trip_id;

    v_trip_completed := (v_new_stops_progress >= v_total_stops AND v_total_stops > 0);

    -- 5. If complete delivery (not incident), update package statuses
    IF p_outcome = 'complete' THEN
        UPDATE shipping_paquetes
        SET
            estado = 'entregado',
            fecha_entrega = NOW(),
            updated_at = NOW()
        WHERE id IN (
            SELECT paquete_id
            FROM operations_viajes_paquetes
            WHERE viaje_id = p_trip_id
              AND parada_id = p_stop_id
              AND deleted_at IS NULL
        )
        AND deleted_at IS NULL;
    END IF;

    -- 6. Log event
    INSERT INTO operations_viajes_eventos (
        viaje_id, tipo, descripcion, metadata
    ) VALUES (
        p_trip_id,
        'entrega',
        CASE
            WHEN p_outcome = 'complete' THEN 'Entrega completada'
            ELSE 'Entrega con incidencia: ' || COALESCE(p_incident_reason, 'sin detalle')
        END,
        jsonb_build_object(
            'checkpoint_id', p_checkpoint_id,
            'stop_id', p_stop_id,
            'outcome', p_outcome,
            'packages_delivered', p_packages_delivered,
            'incident_reason', p_incident_reason
        )
    );

    -- 7. Build result
    v_result := jsonb_build_object(
        'success', TRUE,
        'checkpoint_id', p_checkpoint_id,
        'trip_completed', v_trip_completed,
        'stops_progress', v_new_stops_progress,
        'total_stops', v_total_stops,
        'packages_delivered', p_packages_delivered
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 2. verify_delivery_otp
-- Verifies OTP code for a delivery checkpoint
-- ============================================================================
CREATE OR REPLACE FUNCTION public.verify_delivery_otp(
    p_checkpoint_id UUID,
    p_otp_code VARCHAR(10)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_checkpoint operations_checkpoints%ROWTYPE;
    v_stored_otp TEXT;
    v_otp_expires_at TIMESTAMPTZ;
    v_is_valid BOOLEAN;
BEGIN
    -- 1. Get checkpoint
    SELECT * INTO v_checkpoint
    FROM operations_checkpoints
    WHERE id = p_checkpoint_id AND deleted_at IS NULL;

    IF v_checkpoint IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Checkpoint not found'
        );
    END IF;

    -- 2. Check for OTP in observaciones (stored as JSON)
    -- Format in observaciones: {"otp_code": "123456", "otp_expires_at": "2026-07-10T..."}
    BEGIN
        v_stored_otp := (v_checkpoint.observaciones::jsonb)->>'otp_code';
        v_otp_expires_at := ((v_checkpoint.observaciones::jsonb)->>'otp_expires_at')::timestamptz;
    EXCEPTION WHEN OTHERS THEN
        -- Fallback: look for a dedicated OTP column or table
        -- For now, return error if we can't parse
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'OTP not configured for this checkpoint'
        );
    END;

    -- 3. Validate OTP exists
    IF v_stored_otp IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'OTP not configured for this checkpoint'
        );
    END IF;

    -- 4. Check expiry
    IF v_otp_expires_at IS NOT NULL AND v_otp_expires_at < NOW() THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'OTP code expired',
            'expired', TRUE
        );
    END IF;

    -- 5. Verify code
    v_is_valid := (v_stored_otp = p_otp_code);

    IF NOT v_is_valid THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Invalid OTP code',
            'attempts_remaining', 3  -- placeholder, implement actual tracking if needed
        );
    END IF;

    -- 6. OTP valid - mark checkpoint as verified
    UPDATE operations_checkpoints
    SET
        estado = 'completado',
        updated_at = NOW()
    WHERE id = p_checkpoint_id;

    -- 7. Log event
    INSERT INTO operations_viajes_eventos (
        viaje_id, tipo, descripcion, metadata
    ) VALUES (
        v_checkpoint.viaje_id,
        'entrega',
        'OTP verificado exitosamente',
        jsonb_build_object(
            'checkpoint_id', p_checkpoint_id,
            'otp_verified', TRUE
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'checkpoint_id', p_checkpoint_id,
        'verified', TRUE
    );
END;
$$;

-- ============================================================================
-- 3. get_driver_bootstrap
-- Main RPC to load all driver data at app startup
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_driver_bootstrap()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
    v_user JSONB;
    v_driver JSONB;
    v_vehicle JSONB;
    v_trip JSONB;
    v_checklist JSONB;
    v_current_stop JSONB;
    v_stops JSONB;
    v_delivery_session JSONB;
    v_result JSONB;
BEGIN
    -- 1. Get authenticated user
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 2. Get user profile
    SELECT jsonb_build_object(
        'id', u.id,
        'auth_user_id', u.auth_user_id,
        'nombre', u.nombre,
        'apellido', u.apellido,
        'email', u.email,
        'telefono', u.telefono,
        'activo', u.activo,
        'empresa_id', u.empresa_id,
        'rol_id', u.rol_id
    ) INTO v_user
    FROM core_usuarios u
    WHERE u.auth_user_id = v_user_id
      AND u.deleted_at IS NULL
    LIMIT 1;

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'User profile not found';
    END IF;

    v_empresa_id := (v_user->>'empresa_id')::UUID;

    -- 3. Get driver record
    SELECT jsonb_build_object(
        'id', fc.id,
        'licencia', fc.licencia,
        'telefono', fc.telefono,
        'estado', fc.estado,
        'foto', fc.foto
    ) INTO v_driver
    FROM fleet_conductores fc
    WHERE fc.usuario_id = (v_user->>'id')::UUID
      AND fc.empresa_id = v_empresa_id
      AND fc.deleted_at IS NULL
    LIMIT 1;

    -- 4. Get assigned vehicle
    IF v_driver IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', fv.id,
            'matricula', fv.matricula,
            'marca', fv.marca,
            'modelo', fv.modelo,
            'anio', fv.anio
        ) INTO v_vehicle
        FROM fleet_vehiculos fv
        WHERE fv.id = (
            SELECT vehiculo_actual FROM fleet_conductores
            WHERE id = (v_driver->>'id')::UUID
        )
        AND fv.deleted_at IS NULL
        LIMIT 1;
    END IF;

    -- 5. Get active trip
    IF v_driver IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', ov.id,
            'codigo', ov.codigo,
            'estado', ov.estado,
            'stops_progress', COALESCE(ov.stops_progress, 0),
            'total_stops', (
                SELECT COUNT(*)::INTEGER
                FROM operations_checkpoints oc
                WHERE oc.viaje_id = ov.id AND oc.deleted_at IS NULL
            ),
            'progress_percent', CASE
                WHEN (SELECT COUNT(*) FROM operations_checkpoints oc WHERE oc.viaje_id = ov.id AND oc.deleted_at IS NULL) > 0
                THEN (COALESCE(ov.stops_progress, 0)::DECIMAL /
                      (SELECT COUNT(*)::DECIMAL FROM operations_checkpoints oc WHERE oc.viaje_id = ov.id AND oc.deleted_at IS NULL) * 100)
                ELSE 0
            END,
            'packages_remaining', (
                SELECT COUNT(*)::INTEGER
                FROM operations_viajes_paquetes ovp
                WHERE ovp.viaje_id = ov.id
                  AND ovp.estado != 'entregado'
                  AND ovp.deleted_at IS NULL
            ),
            'departure_time', ov.hora_real_salida,
            'estimated_arrival', ov.hora_programada_llegada,
            'total_distance', ov.km_estimados,
            'remaining_distance', ov.distancia_real_km
        ) INTO v_trip
        FROM operations_viajes ov
        JOIN operations_viajes_conductores ovc ON ovc.viaje_id = ov.id
        WHERE ovc.conductor_id = (v_driver->>'id')::UUID
          AND ov.estado IN ('en_curso', 'programado')
          AND ov.deleted_at IS NULL
          AND ovc.deleted_at IS NULL
        ORDER BY ov.created_at DESC
        LIMIT 1;
    END IF;

    -- 6. Get current stop (first incomplete checkpoint)
    IF v_trip IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', oc.id,
            'nombre', op.nombre,
            'address', op.direccion,
            'customer_name', cs.nombre,
            'latitud', op.latitud,
            'longitud', op.longitud,
            'eta_minutes', op.eta_minutos,
            'packages', (
                SELECT COUNT(*)::INTEGER
                FROM operations_viajes_paquetes ovp
                WHERE ovp.viaje_id = oc.viaje_id
                  AND ovp.parada_id = oc.parada_id
                  AND ovp.deleted_at IS NULL
            )
        ) INTO v_current_stop
        FROM operations_checkpoints oc
        LEFT JOIN operations_paradas op ON oc.parada_id = op.id
        LEFT JOIN customers_clientes cs ON op.direccion_id IN (
            SELECT id FROM customers_direcciones WHERE cliente_id = cs.id
        )
        WHERE oc.viaje_id = (v_trip->>'id')::UUID
          AND oc.estado IN ('pendiente', 'llego')
          AND oc.deleted_at IS NULL
        ORDER BY (
            SELECT orden FROM operations_paradas WHERE id = oc.parada_id
        )
        LIMIT 1;

        -- 7. Get all stops for progress
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', oc.id,
                'nombre', op.nombre,
                'orden', (SELECT orden FROM operations_paradas WHERE id = oc.parada_id),
                'estado', oc.estado
            ) ORDER BY (SELECT orden FROM operations_paradas WHERE id = oc.parada_id)
        ) INTO v_stops
        FROM operations_checkpoints oc
        LEFT JOIN operations_paradas op ON oc.parada_id = op.id
        WHERE oc.viaje_id = (v_trip->>'id')::UUID
          AND oc.deleted_at IS NULL;
    END IF;

    -- 8. Get checklist for current trip
    IF v_trip IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', fc.id,
            'tipo', fc.tipo,
            'estado', fc.estado,
            'items', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', fci.id,
                        'nombre', fci.nombre,
                        'categoria', fci.categoria,
                        'estado', fci.estado,
                        'observacion', fci.observacion
                    )
                )
                FROM fleet_checklists_items fci
                WHERE fci.checklist_id = fc.id AND fci.deleted_at IS NULL
            )
        ) INTO v_checklist
        FROM fleet_checklists fc
        WHERE fc.viaje_id = (v_trip->>'id')::UUID
          AND fc.deleted_at IS NULL
        ORDER BY fc.created_at DESC
        LIMIT 1;
    END IF;

    -- 9. Build result
    v_result := jsonb_build_object(
        'user', v_user,
        'driver', v_driver,
        'vehicle', v_vehicle,
        'trip', v_trip,
        'current_stop', v_current_stop,
        'stops', COALESCE(v_stops, '[]'::jsonb),
        'checklist', v_checklist,
        'device', jsonb_build_object(
            'gps', TRUE,
            'internet', TRUE,
            'synced', TRUE
        )
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 4. Grant permissions
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.complete_delivery(UUID, UUID, UUID, VARCHAR, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_delivery_otp(UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_driver_bootstrap() TO authenticated;

-- ============================================================================
-- 5. Add missing columns to operations_checkpoints if needed
-- ============================================================================

-- Add metadata column for OTP storage
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints'
          AND column_name = 'metadata'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN metadata JSONB;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints'
          AND column_name = 'foto_evidencia_url'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN foto_evidencia_url TEXT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints'
          AND column_name = 'firma_receptor'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN firma_receptor TEXT;
    END IF;
END $$;

-- ============================================================================
-- 6. Add otp_expires_at to checkpoints for OTP expiry tracking
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints'
          AND column_name = 'otp_expires_at'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN otp_expires_at TIMESTAMPTZ;
    END IF;
END $$;
