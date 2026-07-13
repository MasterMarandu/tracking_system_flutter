-- ============================================================================
-- MIGRATION: RPC Functions for Delivery App
-- Run this AFTER tracking.sql
-- ============================================================================

-- ============================================================================
-- 0. Add missing columns FIRST (before functions that use them)
-- ============================================================================

-- Add columns to operations_checkpoints
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN metadata JSONB;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints' AND column_name = 'foto_evidencia_url'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN foto_evidencia_url TEXT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints' AND column_name = 'firma_receptor'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN firma_receptor TEXT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'operations_checkpoints' AND column_name = 'otp_expires_at'
    ) THEN
        ALTER TABLE operations_checkpoints ADD COLUMN otp_expires_at TIMESTAMPTZ;
    END IF;
END $$;

-- Update事件 tipo constraint to allow new event types
DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    SELECT conname INTO v_constraint_name
    FROM pg_constraint
    WHERE conrelid = 'operations_viajes_eventos'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%tipo%';

    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE operations_viajes_eventos DROP CONSTRAINT %I',
            v_constraint_name
        );
    END IF;

    ALTER TABLE operations_viajes_eventos
    ADD CONSTRAINT operations_viajes_eventos_tipo_check
    CHECK (tipo IN (
        'viaje_aceptado', 'checklist_completado', 'carga_iniciada', 'carga_finalizada',
        'viaje_iniciado', 'viaje_pausado', 'viaje_reanudado', 'parada_programada',
        'parada_no_programada', 'incidente', 'entrega', 'otp_verificado',
        'firma_capturada', 'foto_capturada', 'viaje_cerrado'
    ));
END $$;

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
SET search_path = public
AS $$
DECLARE
    v_checkpoint operations_checkpoints%ROWTYPE;
    v_trip operations_viajes%ROWTYPE;
    v_total_stops INTEGER;
    v_completed_stops INTEGER;
    v_trip_completed BOOLEAN := FALSE;
    v_estado_entregado_id UUID;
    v_empresa_id UUID;
    v_result JSONB;
BEGIN
    -- 0. Multi-tenant security: verify user belongs to this trip's empresa
    SELECT v.empresa_id INTO v_empresa_id
    FROM operations_viajes v
    WHERE v.id = p_trip_id AND v.deleted_at IS NULL;

    IF NOT EXISTS (
        SELECT 1 FROM core_usuarios u
        WHERE u.auth_user_id = auth.uid()
          AND u.empresa_id = v_empresa_id
          AND u.deleted_at IS NULL
          AND u.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'Access denied: user does not belong to this empresa';
    END IF;

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
            WHEN p_outcome IN ('complete', 'incident') THEN 'completado'
            ELSE estado
        END,
        hora_salida = NOW(),
        observaciones = CASE
            WHEN p_incident_reason IS NOT NULL THEN p_incident_reason
            ELSE observaciones
        END,
        updated_at = NOW()
    WHERE id = p_checkpoint_id;

    -- 3. Calculate progress from checkpoints (not from viajes columns)
    SELECT COUNT(*)::INTEGER INTO v_total_stops
    FROM operations_checkpoints
    WHERE viaje_id = p_trip_id AND deleted_at IS NULL;

    SELECT COUNT(*)::INTEGER INTO v_completed_stops
    FROM operations_checkpoints
    WHERE viaje_id = p_trip_id
      AND estado = 'completado'
      AND deleted_at IS NULL;

    -- 4. Update trip: mark completed if all checkpoints done
    v_trip_completed := (v_completed_stops >= v_total_stops AND v_total_stops > 0);

    UPDATE operations_viajes
    SET
        updated_at = NOW(),
        estado = CASE
            WHEN v_trip_completed THEN 'completado'
            ELSE estado
        END,
        fecha_fin = CASE
            WHEN v_trip_completed THEN NOW()
            ELSE fecha_fin
        END
    WHERE id = p_trip_id;

    -- 5. If complete delivery (not incident), update package statuses
    IF p_outcome = 'complete' THEN
        -- Get the UUID for 'ENTREGADO' status
        SELECT id INTO v_estado_entregado_id
        FROM shipping_estados_envio
        WHERE codigo = 'ENTREGADO';

        UPDATE shipping_paquetes
        SET
            estado_actual = v_estado_entregado_id,
            fecha_entrega_real = NOW(),
            updated_at = NOW()
        WHERE id IN (
            SELECT paquete_id
            FROM operations_viajes_paquetes
            WHERE viaje_id = p_trip_id
              AND parada_id = p_stop_id
              AND deleted_at IS NULL
        )
        AND deleted_at IS NULL;

        -- Update operations_viajes_paquetes.estado to 'entregado'
        UPDATE operations_viajes_paquetes
        SET
            estado = 'entregado',
            updated_at = NOW()
        WHERE viaje_id = p_trip_id
          AND parada_id = p_stop_id
          AND deleted_at IS NULL;

        -- Update shipping_envios if all their packages are now delivered
        UPDATE shipping_envios se
        SET
            estado = 'entregado',
            fecha_entrega = NOW(),
            updated_at = NOW()
        WHERE se.id IN (
            SELECT DISTINCT sp.envio_id
            FROM operations_viajes_paquetes ovp
            JOIN shipping_paquetes sp ON ovp.paquete_id = sp.id
            WHERE ovp.viaje_id = p_trip_id
              AND ovp.parada_id = p_stop_id
              AND ovp.deleted_at IS NULL
              AND sp.deleted_at IS NULL
              AND sp.envio_id IS NOT NULL
        )
        AND se.estado IN ('creado', 'preparando', 'despachado', 'en_ruta')
        AND se.deleted_at IS NULL
        AND NOT EXISTS (
            SELECT 1
            FROM shipping_paquetes sp2
            WHERE sp2.envio_id = se.id
              AND sp2.deleted_at IS NULL
              AND (sp2.estado_actual IS DISTINCT FROM v_estado_entregado_id)
        );
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
        'stops_progress', v_completed_stops,
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
SET search_path = public
AS $$
DECLARE
    v_checkpoint operations_checkpoints%ROWTYPE;
    v_stored_otp TEXT;
    v_otp_expires_at TIMESTAMPTZ;
    v_is_valid BOOLEAN;
    v_empresa_id UUID;
BEGIN
    -- 0. Multi-tenant security
    SELECT oc.empresa_id INTO v_empresa_id
    FROM operations_checkpoints oc
    WHERE oc.id = p_checkpoint_id;

    -- empresa_id may be NULL on checkpoints, get from trip
    IF v_empresa_id IS NULL THEN
        SELECT v.empresa_id INTO v_empresa_id
        FROM operations_viajes v
        JOIN operations_checkpoints oc ON oc.viaje_id = v.id
        WHERE oc.id = p_checkpoint_id;
    END IF;

    IF v_empresa_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM core_usuarios u
            WHERE u.auth_user_id = auth.uid()
              AND u.empresa_id = v_empresa_id
              AND u.deleted_at IS NULL
              AND u.activo = TRUE
        ) THEN
            RAISE EXCEPTION 'Access denied';
        END IF;
    END IF;

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

    -- 2. Get OTP from metadata (not observaciones)
    v_stored_otp := v_checkpoint.metadata->>'otp_code';
    v_otp_expires_at := v_checkpoint.otp_expires_at;

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
            'error', 'Invalid OTP code'
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
        'otp_verificado',
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
SET search_path = public
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
    v_result JSONB;
    v_driver_id UUID;
    v_trip_id UUID;
    v_total_stops INTEGER;
    v_completed_stops INTEGER;
BEGIN
    -- 1. Get authenticated user
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 2. Get user profile (with name composed from nombre + apellido)
    SELECT jsonb_build_object(
        'id', u.id,
        'auth_user_id', u.auth_user_id,
        'name', TRIM(COALESCE(u.nombre, '') || ' ' || COALESCE(u.apellido, '')),
        'email', u.email,
        'telefono', u.telefono,
        'active', u.activo,
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
        'status', fc.estado,
        'foto', fc.foto
    ), fc.id INTO v_driver, v_driver_id
    FROM fleet_conductores fc
    WHERE fc.usuario_id = (v_user->>'id')::UUID
      AND fc.empresa_id = v_empresa_id
      AND fc.deleted_at IS NULL
    LIMIT 1;

    -- 4. Get assigned vehicle
    IF v_driver_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', fv.id,
            'plate', fv.matricula,
            'marca', fv.marca,
            'modelo', fv.modelo,
            'anio', fv.anio
        ) INTO v_vehicle
        FROM fleet_vehiculos fv
        WHERE fv.id = (
            SELECT vehiculo_actual FROM fleet_conductores
            WHERE id = v_driver_id
        )
        AND fv.deleted_at IS NULL
        LIMIT 1;
    END IF;

    -- 5. Get active trip (include 'pausado' too)
    IF v_driver_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', ov.id,
            'codigo', ov.codigo,
            'status', ov.estado,
            'departure_time', to_char(ov.hora_real_salida, 'HH24:MI'),
            'estimated_arrival', to_char(ov.hora_programada_llegada, 'HH24:MI'),
            'total_distance', ov.km_estimados,
            'remaining_distance', COALESCE(ov.distancia_real_km, ov.km_estimados)
        ), ov.id INTO v_trip, v_trip_id
        FROM operations_viajes ov
        JOIN operations_viajes_conductores ovc ON ovc.viaje_id = ov.id
        WHERE ovc.conductor_id = v_driver_id
          AND ov.estado IN ('en_curso', 'programado', 'pausado')
          AND ov.deleted_at IS NULL
          AND ovc.deleted_at IS NULL
        ORDER BY ov.created_at DESC
        LIMIT 1;
    END IF;

    -- 6. Calculate trip progress from checkpoints (real data, not stored columns)
    IF v_trip_id IS NOT NULL THEN
        SELECT COUNT(*)::INTEGER INTO v_total_stops
        FROM operations_checkpoints
        WHERE viaje_id = v_trip_id AND deleted_at IS NULL;

        SELECT COUNT(*)::INTEGER INTO v_completed_stops
        FROM operations_checkpoints
        WHERE viaje_id = v_trip_id
          AND estado = 'completado'
          AND deleted_at IS NULL;

        -- Update trip JSON with calculated fields
        v_trip := v_trip || jsonb_build_object(
            'stops_progress', v_completed_stops,
            'total_stops', v_total_stops,
            'progress_percent', CASE
                WHEN v_total_stops > 0 THEN v_completed_stops::DECIMAL / v_total_stops::DECIMAL
                ELSE 0
            END,
            'packages_remaining', (
                SELECT COUNT(*)::INTEGER
                FROM operations_viajes_paquetes ovp
                WHERE ovp.viaje_id = v_trip_id
                  AND ovp.estado != 'entregado'
                  AND ovp.deleted_at IS NULL
            )
        );
    END IF;

    -- 7. Get current stop (first incomplete checkpoint) with checkpoint_id
    IF v_trip_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', op.id,
            'checkpoint_id', oc.id,
            'name', op.nombre,
            'address', op.direccion,
            'customer_name', COALESCE(
                (SELECT cs.nombre FROM customers_clientes cs
                 JOIN customers_direcciones cd ON cd.cliente_id = cs.id
                 WHERE cd.id = op.direccion_id LIMIT 1),
                ''
            ),
            'latitud', op.latitud,
            'longitud', op.longitud,
            'distance_km', 0,
            'eta_minutes', op.eta_minutos,
            'packages', (
                SELECT COUNT(*)::INTEGER
                FROM operations_viajes_paquetes ovp
                WHERE ovp.viaje_id = v_trip_id
                  AND ovp.parada_id = oc.parada_id
                  AND ovp.deleted_at IS NULL
            )
        ) INTO v_current_stop
        FROM operations_checkpoints oc
        LEFT JOIN operations_paradas op ON oc.parada_id = op.id
        WHERE oc.viaje_id = v_trip_id
          AND oc.estado IN ('pendiente', 'llego')
          AND oc.deleted_at IS NULL
        ORDER BY (SELECT orden FROM operations_paradas WHERE id = oc.parada_id)
        LIMIT 1;

        -- 8. Get all stops for progress
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', oc.id,
                'name', op.nombre,
                'orden', (SELECT orden FROM operations_paradas WHERE id = oc.parada_id),
                'status', oc.estado
            ) ORDER BY (SELECT orden FROM operations_paradas WHERE id = oc.parada_id)
        ) INTO v_stops
        FROM operations_checkpoints oc
        LEFT JOIN operations_paradas op ON oc.parada_id = op.id
        WHERE oc.viaje_id = v_trip_id
          AND oc.deleted_at IS NULL;
    END IF;

    -- 9. Get checklist for current trip
    IF v_trip_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', fc.id,
            'tipo', fc.tipo,
            'status', fc.estado,
            'items', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', fci.id,
                        'name', fci.nombre,
                        'categoria', fci.categoria,
                        'status', fci.estado,
                        'observacion', fci.observacion
                    )
                )
                FROM fleet_checklists_items fci
                WHERE fci.checklist_id = fc.id AND fci.deleted_at IS NULL
            )
        ) INTO v_checklist
        FROM fleet_checklists fc
        WHERE fc.viaje_id = v_trip_id
          AND fc.deleted_at IS NULL
        ORDER BY fc.created_at DESC
        LIMIT 1;
    END IF;

    -- 10. Build result
    v_result := jsonb_build_object(
        'user', v_user,
        'driver', v_driver,
        'vehicle', v_vehicle,
        'trip', v_trip,
        'currentStop', v_current_stop,
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
