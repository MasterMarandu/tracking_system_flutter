# Instalación desde cero - Tracking System

## Orden de ejecución

1. **`00_drop_all.sql`** — Limpia TODA la base de datos (⚠️ borra todo)
2. **`tracking.sql`** — Schema completo (tablas, índices, RLS, triggers básicos)
3. **`migrations/001_delivery_rpcs.sql`** — RPCs de delivery
4. **`migrations/002_auto_checkpoints.sql`** — Trigger que genera checkpoints automáticamente
5. **`migrations/003_validate_empresa_assignments.sql`** — Trigger que valida empresa en asignaciones
6. **`06_seed_data.sql`** — Datos de prueba mínimos

## Cómo ejecutar

### Opción A: Script maestro (recomendado)

Si tenés acceso a `psql`:

```bash
psql -h <host> -U postgres -d postgres -f 00_install_master.sql
```

### Opción B: Manual desde Supabase SQL Editor

Ejecutá cada archivo en orden en el SQL Editor de Supabase.

## Pasos previos en Supabase Dashboard

Antes de ejecutar el seed data:

1. **Crear usuario en `auth.users`:**
   - Ir a Authentication → Users → Add user
   - Email: `marcos@gmail.com` (o el que quieras)
   - Auto Confirm User: ✅
   - Guardar el `auth_user_id` (UUID)

2. **Editar `06_seed_data.sql`:**
   - Reemplazar `v_auth_user_id` con el UUID real
   - Reemplazar el email si es distinto

## Verificación post-instalación

```sql
-- Verificar que el trigger de validación existe
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'trg_validate_viaje_conductor_empresa';

-- Verificar que el trigger de auto-checkpoints existe
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'trg_auto_generate_checkpoints';

-- Verificar RPCs
SELECT routine_name FROM information_schema.routines
WHERE routine_name IN ('complete_delivery', 'verify_delivery_otp', 'get_driver_bootstrap');

-- Probar la RPC con el usuario creado
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

**Importante:** En `operations_viajes_conductores.conductor_id` se debe guardar `fleet_conductores.id`, **NUNCA** `fleet_conductores.usuario_id`.
