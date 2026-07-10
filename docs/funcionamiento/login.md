Cuando el conductor se logea, la aplicación no debería abrir directamente un Dashboard con datos fijos. Debe ejecutar un **bootstrap operativo**: identificar al usuario, cargar su empresa, conductor, vehículo, viaje activo, checklist y siguiente parada; luego decidir cuál es la primera acción disponible.

## Flujo recomendado

```text
Login exitoso
    ↓
Validar sesión y usuario
    ↓
Cargar perfil, empresa y rol
    ↓
Cargar conductor y vehículo
    ↓
Buscar viaje activo o programado
    ↓
Cargar checklist, ruta, parada y paquetes
    ↓
Restaurar estado anterior
    ↓
Mostrar Dashboard correspondiente
```

---

# 1. La app inicia con un Splash

Al abrir la aplicación:

```text
Comprobando sesión...
Sincronizando operación...
```

Debe comprobar si existe una sesión de Supabase:

```dart
final session = Supabase.instance.client.auth.currentSession;
```

### Si no hay sesión

Mostrar:

```text
Login
```

### Si hay sesión válida

No mostrar el login nuevamente. Ejecutar el bootstrap del conductor.

También debes escuchar cambios de sesión:

```dart
Supabase.instance.client.auth.onAuthStateChange.listen((event) {
  // signedIn, signedOut, tokenRefreshed, etc.
});
```

---

# 2. Validar el usuario y el rol

Después del login, debes buscar el registro de `core_usuarios` asociado con:

```text
auth.users.id = core_usuarios.auth_user_id
```

Y validar:

- que el usuario exista;
- que esté activo;
- que no tenga `deleted_at`;
- que pertenezca a una empresa;
- que su rol sea `Chofer`.

La app debería cargar algo similar a:

```json
{
  "userId": "uuid",
  "empresaId": "uuid",
  "nombre": "Carlos",
  "apellido": "Mendoza",
  "rol": "Chofer",
  "activo": true
}
```

Si el usuario está autenticado pero no tiene perfil operativo:

```text
Tu usuario no está configurado como conductor.
Contacta al administrador.
```

No deberías mostrar un Dashboard vacío o con datos demo.

---

# 3. Cargar el conductor

Con el `core_usuarios.id`, se obtiene `fleet_conductores`:

```text
core_usuarios.id → fleet_conductores.usuario_id
```

Datos necesarios:

```json
{
  "conductorId": "uuid",
  "licencia": "123456",
  "estado": "disponible",
  "vehiculoActual": "uuid"
}
```

Si el conductor está:

```text
inactivo
```

la app debe bloquear la operación:

```text
Tu cuenta de conductor está inactiva.
Contacta al supervisor.
```

El vehículo mostrado en el Dashboard debería salir preferentemente de:

```text
operations_viajes_vehiculos
```

para el viaje actual, no solamente de `fleet_conductores.vehiculo_actual`, porque el vehículo puede haber cambiado para ese viaje.

---

# 4. Buscar el viaje del conductor

La relación es:

```text
core_usuarios
    ↓
fleet_conductores
    ↓
operations_viajes_conductores
    ↓
operations_viajes
```

La app debe buscar viajes donde el conductor tenga una asignación activa:

```sql
operations_viajes_conductores.estado IN (
    'asignado',
    'aceptado',
    'en_curso'
)
```

Y donde el viaje no esté eliminado ni cancelado.

Los estados del backend son:

```text
programado
en_curso
pausado
completado
cancelado
```

El conductor podría tener estos escenarios.

---

# Escenario A: no tiene viaje asignado

Mostrar una pantalla específica:

```text
Hola Carlos

No tienes viajes asignados actualmente.

Próxima actualización:
Hoy, 14:00

[ACTUALIZAR]
[CONTACTAR SOPORTE]
```

No deberías mostrar:

- Warehouse B;
- paquetes ficticios;
- porcentaje 65%;
- KPIs que no corresponden;
- botón `INICIAR VIAJE`.

En este estado el Dashboard puede mostrar únicamente:

- estado de conexión;
- vehículo;
- perfil;
- notificaciones;
- soporte;
- historial del día, si existe.

---

# Escenario B: tiene viaje programado

Si:

```text
operations_viajes.estado = 'programado'
```

la app carga:

- ruta;
- paradas;
- vehículo;
- paquetes;
- checklist pre-viaje;
- horario programado.

La pantalla debe mostrar:

```text
Próximo viaje

Ruta Norte
Salida programada: 08:30
Vehículo: TRK-4521
8 paradas
24 paquetes

Checklist pendiente

[INICIAR CHECKLIST]
```

El botón `INICIAR VIAJE` debe estar deshabilitado hasta completar el checklist.

Tu estado Flutter sería:

```dart
TripState.preTrip
```

Pero no significa necesariamente que el checklist esté vacío. Debes cargar el checklist real de:

```text
fleet_checklists
fleet_checklists_items
```

---

# Escenario C: checklist iniciado pero incompleto

Si existe un checklist:

```text
fleet_checklists.estado = 'en_proceso'
```

la app debe restaurar el avance:

```text
Checklist: 7/12 completado
```

Mostrar:

```text
Continúa la inspección del vehículo

[CONTINUAR CHECKLIST]
```

No debe crear un checklist nuevo cada vez que el conductor inicia sesión.

Debe reutilizar el checklist existente asociado con:

```text
viaje_id
vehiculo_id
conductor_id
tipo = 'pre_viaje'
```

---

# Escenario D: checklist completado, viaje aún no iniciado

Si el checklist está completo y el viaje sigue en:

```text
programado
```

mostrar:

```text
Todo listo para iniciar

Vehículo: TRK-4521
Ruta: Warehouse B - Zona Norte
8 paradas
24 paquetes

[INICIAR VIAJE]
```

Al pulsar `INICIAR VIAJE`, no conviene actualizar varias tablas directamente desde Flutter. Debe ejecutarse una operación transaccional como:

```text
iniciar_viaje(viaje_id)
```

Esa operación debería:

1. validar que el conductor sea el asignado;
2. validar que el checklist esté completo;
3. cambiar `operations_viajes.estado` a `en_curso`;
4. registrar `hora_real_salida`;
5. actualizar el estado del conductor;
6. actualizar el estado del vehículo;
7. crear `tracking_sesiones`;
8. insertar un evento `inicio_viaje`;
9. devolver el estado actualizado.

Por ejemplo:

```json
{
  "success": true,
  "tripState": "en_curso",
  "trackingSessionId": "uuid",
  "startedAt": "2026-07-10T08:30:00Z"
}
```

Solo después de recibir confirmación del backend se debe cambiar la interfaz a:

```dart
TripState.inRoute
```

---

# Escenario E: viaje en curso

Si:

```text
operations_viajes.estado = 'en_curso'
```

la app debe cargar la parada actual.

La siguiente parada se obtiene desde:

```text
operations_checkpoints
operations_paradas
operations_viajes_paquetes
operations_eta
```

La consulta conceptual sería:

```text
viaje actual
    ↓
checkpoints pendientes
    ↓
parada con menor orden
    ↓
ETA de esa parada
    ↓
paquetes asignados a esa parada
```

El Dashboard mostraría:

```text
Próxima parada

Warehouse B - Zona Norte
Coca Cola Paraguay
Av. Principal 456

4.2 km
12 min
Llegada 09:22
5 paquetes

[NAVEGAR]
```

El estado Flutter sería:

```dart
TripState.inRoute
```

El tracking GPS debería comenzar únicamente después de que el viaje esté oficialmente iniciado, no simplemente por abrir la aplicación.

---

# Escenario F: el conductor ya está en la geocerca

La entrada en geocerca debería generarse automáticamente desde el servicio de ubicación.

Cuando el dispositivo detecta la llegada:

1. inserta un evento en `tracking_eventos`;
2. actualiza el checkpoint;
3. registra la hora de llegada;
4. cambia el estado visual.

Por ejemplo:

```text
tracking_eventos.tipo = 'entrada_geocerca'
operations_checkpoints.estado = 'llego'
operations_checkpoints.hora_llegada = NOW()
```

La app muestra:

```text
Llegaste a Warehouse B

[INICIAR ENTREGA]
```

Estado Flutter:

```dart
TripState.geofenceEntry
```

El botón manual de llegada debe existir como respaldo si falla el GPS, pero debería pasar por una RPC:

```text
registrar_llegada_manual(viaje_id, parada_id, latitud, longitud)
```

La operación debería registrar que fue manual:

```json
{
  "modo": "manual",
  "motivo": "gps_no_disponible"
}
```

---

# Escenario G: entrega interrumpida

Este escenario es muy importante.

Si el conductor cerró la app después de escanear paquetes, tomar la foto o capturar la firma, al volver a iniciar sesión la app debe continuar desde el último paso.

Por ejemplo:

```text
Entrega en curso
Paquetes: 5/5 escaneados
Foto: completada
Firma: pendiente
OTP: pendiente

[CONTINUAR ENTREGA]
```

Actualmente tu esquema tiene `delivery_entregas`, pero esa tabla representa principalmente la entrega finalizada. No existe todavía una tabla clara para guardar el borrador del flujo.

Conviene crear algo como:

```sql
CREATE TABLE delivery_sesiones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    empresa_id UUID NOT NULL REFERENCES core_empresas(id),
    viaje_id UUID NOT NULL REFERENCES operations_viajes(id),
    parada_id UUID NOT NULL REFERENCES operations_paradas(id),
    conductor_id UUID NOT NULL REFERENCES fleet_conductores(id),
    paso_actual VARCHAR(30) NOT NULL DEFAULT 'confirm_arrival',
    paquetes_escaneados JSONB NOT NULL DEFAULT '[]'::jsonb,
    foto_completada BOOLEAN NOT NULL DEFAULT FALSE,
    firma_completada BOOLEAN NOT NULL DEFAULT FALSE,
    otp_verificado BOOLEAN NOT NULL DEFAULT FALSE,
    estado VARCHAR(20) NOT NULL DEFAULT 'en_proceso'
        CHECK (estado IN ('en_proceso', 'completada', 'cancelada')),
    client_operation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Así el flujo Flutter se puede restaurar aunque:

- la app se cierre;
- se reinicie el teléfono;
- se pierda Internet;
- el conductor cambie temporalmente de dispositivo.

---

# Escenario H: viaje pausado

Si:

```text
operations_viajes.estado = 'pausado'
```

mostrar:

```text
Viaje pausado

La ruta se reanudará cuando confirmes continuar.

[REANUDAR VIAJE]
[REPORTAR INCIDENCIA]
```

Al pulsar `REANUDAR VIAJE`, debe ejecutarse:

```text
reanudar_viaje(viaje_id)
```

y registrarse:

```text
operations_viajes_eventos.tipo = 'viaje_reanudado'
tracking_eventos.tipo correspondiente, si aplica
```

---

# Escenario I: viaje completado

Si:

```text
operations_viajes.estado = 'completado'
```

mostrar un resumen:

```text
Viaje completado

8 de 8 paradas
24 paquetes entregados
45.2 km recorridos
2 incidencias

[VER RESUMEN]
[CERRAR TURNO]
```

No debe aparecer:

- `NAVEGAR`;
- `INICIAR ENTREGA`;
- `INICIAR VIAJE`.

---

# Cómo debería resolverse el estado

Puedes mapear temporalmente los datos del backend así:

```dart
TripState resolveTripState(DriverBootstrap data) {
  final trip = data.trip;

  if (trip == null) {
    return TripState.preTrip;
  }

  switch (trip.status) {
    case 'programado':
      return TripState.preTrip;

    case 'pausado':
      return TripState.paused;

    case 'completado':
    case 'cancelado':
      return TripState.completed;

    case 'en_curso':
      final checkpoint = data.currentCheckpoint;

      if (checkpoint?.status == 'en_proceso') {
        return TripState.delivering;
      }

      if (checkpoint?.status == 'llego') {
        return TripState.geofenceEntry;
      }

      return TripState.inRoute;

    default:
      return TripState.preTrip;
  }
}
```

Sin embargo, para diferenciar correctamente:

```text
preTrip sin viaje
preTrip con checklist pendiente
preTrip con checklist completo
```

es mejor no utilizar solamente `TripState`. Conviene tener un estado de sesión separado:

```dart
enum DriverSessionState {
  loading,
  unauthenticated,
  profileIncomplete,
  noTripAssigned,
  tripReady,
  tripInProgress,
  deliveryInProgress,
  paused,
  completed,
  offlineRestored,
  error,
}
```

---

# Respuesta del bootstrap

En vez de que Flutter haga muchas consultas independientes, recomiendo una RPC:

```text
get_driver_bootstrap()
```

Debe devolver una estructura completa:

```json
{
  "user": {
    "id": "uuid",
    "name": "Carlos Mendoza",
    "role": "Chofer",
    "companyId": "uuid"
  },
  "driver": {
    "id": "uuid",
    "status": "disponible",
    "license": "123456"
  },
  "vehicle": {
    "id": "uuid",
    "plate": "TRK-4521",
    "brand": "Mercedes-Benz",
    "model": "Atego"
  },
  "trip": {
    "id": "uuid",
    "code": "VIA-0001",
    "status": "en_curso"
  },
  "checklist": {
    "id": "uuid",
    "status": "completado",
    "completed": 12,
    "total": 12
  },
  "currentStop": {
    "id": "uuid",
    "name": "Warehouse B - Zona Norte",
    "address": "Av. Principal 456",
    "status": "pendiente",
    "etaMinutes": 12
  },
  "packages": [],
  "deliverySession": null,
  "device": {
    "gps": true,
    "internet": true,
    "synced": true
  }
}
```

En Flutter:

```dart
Future<void> _bootstrapDriver() async {
  try {
    final response = await Supabase.instance.client.rpc(
      'get_driver_bootstrap',
    );

    final bootstrap = DriverBootstrap.fromJson(response);

    if (!mounted) return;

    setState(() {
      _applyBootstrap(bootstrap);
      _isLoading = false;
    });
  } catch (error) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _errorMessage = 'No se pudo cargar la operación';
    });
  }
}
```

---

# Qué debe hacer la app automáticamente después del login

## Inmediatamente

1. Restaurar la sesión.
2. Validar el usuario.
3. Validar el rol `Chofer`.
4. Obtener empresa y conductor.
5. Obtener viaje activo o programado.
6. Obtener vehículo.
7. Obtener checklist.
8. Obtener parada actual.
9. Obtener paquetes.
10. Obtener estado de entrega pendiente.
11. Guardar el snapshot localmente.
12. Mostrar la pantalla apropiada.

## No debe hacer automáticamente

- iniciar el viaje;
- activar tracking permanente;
- marcar llegada;
- crear un checklist duplicado;
- mostrar datos de prueba;
- solicitar todos los permisos sin contexto;
- permitir cambiar de empresa;
- confiar en `rol_id` enviado desde Flutter.

---

# Permisos del dispositivo

Después de cargar el contexto, solicitar permisos según la situación.

Si el conductor tiene un viaje programado:

```text
Para operar el viaje necesitamos:
✓ Ubicación mientras usas la aplicación
✓ Ubicación en segundo plano
✓ Notificaciones
✓ Cámara para evidencias
```

Pero no pediría cámara, GPS en segundo plano ni almacenamiento durante el login de un conductor que no tiene viaje.

El permiso de ubicación en segundo plano debería solicitarse de forma contextual, por ejemplo al pulsar:

```text
INICIAR VIAJE
```

---

# El flujo ideal completo

```text
Abre la app
    ↓
Splash
    ↓
Sesión válida
    ↓
Bootstrap del conductor
    ↓
¿Tiene perfil activo?
    ├── No → Perfil no configurado
    └── Sí
          ↓
¿Tiene viaje?
    ├── No → Sin viaje asignado
    └── Sí
          ↓
¿Estado del viaje?
    ├── Programado → Checklist / Preparar viaje
    ├── En curso → Siguiente parada / Navegar
    ├── En geocerca → Iniciar entrega
    ├── Entrega en curso → Continuar paso pendiente
    ├── Pausado → Reanudar
    └── Completado → Resumen
```

## Recomendación principal

El login solo autentica. La función posterior, `get_driver_bootstrap()`, es la que convierte al usuario autenticado en un **conductor operativo**.

La aplicación debe abrir siempre en el punto exacto donde quedó el conductor:

```text
No mostrar simplemente el Dashboard.
Mostrar la próxima acción operativa.
```

En tu caso, el primer cambio concreto sería reemplazar estos datos hardcodeados:

```dart
TripState _tripState = TripState.preTrip;
final DeviceStatus _deviceStatus = const DeviceStatus(...);
TripData _tripData = TripData(...);
```

por un `DriverBootstrap` cargado desde Supabase y utilizarlo para decidir dinámicamente qué debe aparecer después del login.