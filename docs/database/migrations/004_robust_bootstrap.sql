-- ============================================================================
-- MIGRATION 004: Make get_driver_bootstrap return trip even without paradas
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

    -- 2. Get user profile
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

    -- 6. Calculate trip progress from checkpoints
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
    --    ROBUSTO: funciona aunque no haya paradas
    IF v_trip_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', COALESCE(op.id, oc.parada_id),
            'checkpoint_id', oc.id,
            'name', COALESCE(op.nombre, 'Sin nombre'),
            'address', COALESCE(op.direccion, ''),
            'customer_name', COALESCE(
                (SELECT cs.nombre FROM customers_clientes cs
                 JOIN customers_direcciones cd ON cd.cliente_id = cs.id
                 WHERE cd.id = op.direccion_id LIMIT 1),
                ''
            ),
            'latitud', COALESCE(op.latitud, oc.latitud),
            'longitud', COALESCE(op.longitud, oc.longitud),
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
        ORDER BY (SELECT orden FROM operations_paradas WHERE id = oc.parada_id) NULLS LAST
        LIMIT 1;

        -- 8. Get all stops for progress
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', oc.id,
                'name', COALESCE(op.nombre, 'Sin nombre'),
                'orden', (SELECT orden FROM operations_paradas WHERE id = oc.parada_id),
                'status', oc.estado
            ) ORDER BY (SELECT orden FROM operations_paradas WHERE id = oc.parada_id) NULLS LAST
        ) INTO v_stops
        FROM operations_checkpoints oc
        LEFT JOIN operations_paradas op ON op.id = oc.parada_id
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

GRANT EXECUTE ON FUNCTION public.get_driver_bootstrap() TO authenticated;
