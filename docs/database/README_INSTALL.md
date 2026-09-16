# Base de datos — App del conductor (Routio)

## Fuente de verdad ÚNICA del schema

El DDL oficial del ecosistema Routio vive **solo** en el repositorio web:

```
logistics-trip-planner-interface/database/trackingV2.sql
```

Este repositorio (`tracking_system_flutter`) **consume** ese schema; **no lo define ni lo duplica** (ADR-011). Por eso se eliminaron de aquí los antiguos `trackingV2.sql`, `tracking.sql`, `1_all.sql`, `2_all.sql`, `00_install_master.sql`, `00_drop_all.sql` y la carpeta `migrations/`: todo eso quedó consolidado en el archivo oficial, incluidos los objetos que usa la app:

- Tabla `operations_checkpoints` con columnas `metadata`, `foto_evidencia_url`, `firma_receptor`, `otp_expires_at`.
- RPC `get_driver_bootstrap()` — payload de arranque de la app.
- RPC `complete_delivery(...)` — cierre de entrega idempotente por `client_op_id`.
- RPC `verify_delivery_otp(...)` — verificación de OTP de entrega.

## Instalación en limpio

1. En el proyecto Supabase, ejecutar **`database/trackingV2.sql`** del repo web (SQL Editor o `psql`).
2. Eso deja el schema completo + los RPCs que consume esta app.

```bash
# desde el repo web
psql -h <host> -U postgres -d postgres -f database/trackingV2.sql
```

## Verificación post-instalación

```sql
-- Triggers clave
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name IN ('trg_auto_generate_checkpoints');

-- RPCs que usa la app
SELECT routine_name FROM information_schema.routines
WHERE routine_name IN ('complete_delivery', 'verify_delivery_otp', 'get_driver_bootstrap');

-- Probar el bootstrap con el usuario autenticado
SELECT public.get_driver_bootstrap();
```

## Estructura de IDs (orden de dependencias)

```
auth.users.id  →  core_usuarios.auth_user_id
                        ↓
                  core_usuarios.id
                        ↓
                  fleet_conductores.usuario_id
                        ↓
                  fleet_conductores.id
                        ↓
                  operations_viajes_conductores.conductor_id
```

**Importante:** en `operations_viajes_conductores.conductor_id` se guarda `fleet_conductores.id`, **nunca** `fleet_conductores.usuario_id`.

## Cambios de modelo

Todo cambio de schema se hace **primero** en `logistics-trip-planner-interface/database/trackingV2.sql`, luego se alinea Drizzle (`src/db/schema.ts`) y, si hay DBs vivas, una migración incremental en el repo web. Nunca se redefine el schema desde este repo.
