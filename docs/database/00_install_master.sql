-- ============================================================================
-- TRACKING SYSTEM - INSTALACIÓN COMPLETA DESDE CERO (VERSIÓN DEFINITIVA)
-- ============================================================================
-- Orden de ejecución:
--   1. 00_drop_all.sql                    (limpia toda la base)
--   2. tracking.sql                       (schema completo)
--   3. 001_delivery_rpcs.sql              (RPCs de delivery)
--   4. 005_robust_auto_checkpoints.sql     (trigger robusto auto-genera checkpoints)
--   5. 003_validate_empresa_assignments.sql (trigger validación empresa)
--   6. 006_robust_bootstrap_rpc.sql        (RPC robusta get_driver_bootstrap)
-- ============================================================================

\echo '=============================================================================='
\echo 'PASO 1: Limpiando base de datos'
\echo '=============================================================================='
\i 00_drop_all.sql

\echo '=============================================================================='
\echo 'PASO 2: Schema completo'
\echo '=============================================================================='
\i tracking.sql

\echo '=============================================================================='
\echo 'PASO 3: RPCs de delivery'
\echo '=============================================================================='
\i migrations/001_delivery_rpcs.sql

\echo '=============================================================================='
\echo 'PASO 4: Trigger robusto de auto-generación de checkpoints'
\echo '=============================================================================='
\i migrations/005_robust_auto_checkpoints.sql

\echo '=============================================================================='
\echo 'PASO 5: Trigger de validación de empresa'
\echo '=============================================================================='
\i migrations/003_validate_empresa_assignments.sql

\echo '=============================================================================='
\echo 'PASO 6: RPC robusta get_driver_bootstrap'
\echo '=============================================================================='
\i migrations/006_robust_bootstrap_rpc.sql

\echo '=============================================================================='
\echo 'INSTALACIÓN COMPLETA'
\echo '=============================================================================='
\echo 'El sistema ahora:'
\echo '  ✓ Genera checkpoints automáticamente (con o sin paradas)'
\echo '  ✓ Valida que conductor y vehículo sean de la misma empresa'
\echo '  ✓ Devuelve datos de bootstrap aunque no haya paradas'
\echo '  ✓ Es robusto ante datos incompletos'
\echo ''
\echo 'Próximos pasos:'
\echo '  1. Crear usuario en auth.users desde Supabase Dashboard'
\echo '  2. Insertar en core_usuarios con el auth_user_id'
\echo '  3. Crear conductor en fleet_conductores'
\echo '  4. Crear viajes y asignaciones desde React'
\echo '  5. El trigger generará checkpoints automáticamente'
\echo '  6. La RPC devolverá datos aunque no haya paradas'
