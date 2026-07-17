# Routio — App del conductor

App móvil Flutter del ecosistema **Routio** (misma base Supabase que la web).

## Marca

- Nombre: **Routio**
- Tagline: App del conductor
- Color primario: `#206B5C` (igual que la web)

## Stack

- Flutter + Riverpod + Supabase
- Geolocator / GPS → `tracking_gps` + `tracking_ultima_posicion`
- Schema oficial: `logistics-trip-planner-interface/database/trackingV2.sql`

## Run

```bash
flutter pub get
flutter run
```

## Notas

El package Dart sigue llamándose `tracking_system_app` (imports internos). El nombre visible al usuario es **Routio**.
