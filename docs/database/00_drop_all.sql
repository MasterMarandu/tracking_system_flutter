-- ============================================================================
-- SCRIPT DE LIMPIEZA: Eliminar TODAS las tablas, funciones, triggers, policies
-- ADVERTENCIA: Esto borra TODO. Ejecutar solo en ambiente de desarrollo.
-- ============================================================================

-- 1. Eliminar policies de RLS
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I CASCADE', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- 2. Eliminar triggers
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT tgname, tgrelid::regclass AS tbl
        FROM pg_trigger
        WHERE tgisinternal = FALSE
          AND tgrelid::regclass::text NOT LIKE 'pg_%'
    )
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s CASCADE', r.tgname, r.tbl);
    END LOOP;
END $$;

-- 3. Eliminar funciones (excepto las de extensiones)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname NOT IN (
              'uuid_generate_v4', 'gen_random_uuid',
              'postgis_version', 'postgis_full_version'
          )
    )
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE', r.nspname, r.proname, r.args);
    END LOOP;
END $$;

-- 4. Eliminar tablas (en orden inverso de dependencias)
DROP TABLE IF EXISTS
    -- Audit
    audit_logs CASCADE,

    -- Communication
    communication_notificaciones CASCADE,
    communication_chat_mensajes CASCADE,
    communication_chats CASCADE,

    -- Delivery
    delivery_incidencias CASCADE,
    delivery_fotografias CASCADE,
    delivery_entregas CASCADE,
    delivery_firmas CASCADE,

    -- Tracking
    tracking_sesiones CASCADE,
    tracking_alertas CASCADE,
    tracking_posiciones_gps CASCADE,

    -- Shipping
    shipping_carga_evidencias CASCADE,
    shipping_paquetes_cargas CASCADE,
    shipping_cargas CASCADE,
    shipping_paquetes CASCADE,
    shipping_envios CASCADE,
    shipping_tipos_paquete CASCADE,
    shipping_estados_envio CASCADE,

    -- Operations
    operations_asignaciones CASCADE,
    operations_viajes_eventos CASCADE,
    operations_viajes_paquetes CASCADE,
    operations_viajes_vehiculos CASCADE,
    operations_viajes_conductores CASCADE,
    operations_checkpoints CASCADE,
    operations_viajes CASCADE,
    operations_eta CASCADE,
    operations_paradas CASCADE,
    operations_rutas_optimizadas CASCADE,
    operations_rutas CASCADE,
    operations_geocercas_vinculos CASCADE,
    operations_geocercas CASCADE,

    -- Customers
    customers_destinatarios CASCADE,
    customers_remitentes CASCADE,
    customers_direcciones CASCADE,
    customers_clientes CASCADE,

    -- Fleet
    fleet_mantenimientos CASCADE,
    fleet_checklists_items CASCADE,
    fleet_checklists CASCADE,
    fleet_checklists_plantillas CASCADE,
    fleet_conductores CASCADE,
    fleet_remolques CASCADE,
    fleet_vehiculos CASCADE,
    fleet_dispositivos_gps CASCADE,

    -- Core
    core_configuraciones CASCADE,
    core_permisos CASCADE,
    core_usuarios CASCADE,
    core_roles CASCADE,
    core_sucursales CASCADE,
    core_empresas CASCADE,

    -- Storage
    storage_documentos CASCADE
CASCADE;

-- 5. Eliminar vistas
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT viewname FROM pg_views WHERE schemaname = 'public')
    LOOP
        EXECUTE format('DROP VIEW IF EXISTS %I CASCADE', r.viewname);
    END LOOP;
END $$;

-- 6. Eliminar tipos enum
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT typname FROM pg_type WHERE typtype = 'e' AND typname NOT LIKE 'pg_%')
    LOOP
        EXECUTE format('DROP TYPE IF EXISTS %I CASCADE', r.typname);
    END LOOP;
END $$;

-- 7. Eliminar esquemas auxiliares (excepto public y los de extensiones)
DROP SCHEMA IF EXISTS extensions CASCADE;

RAISE NOTICE 'Limpieza completa. Base de datos lista para recrear.';
