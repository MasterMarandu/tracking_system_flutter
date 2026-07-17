A continuación, se presenta un **análisis de ingeniería de software y base de datos** que mapea la interfaz de usuario descrita con el schema relacional PostgreSQL/PostGIS diseñado en el paso anterior. 

Este análisis demuestra cómo cada componente visual, acción del usuario y flujo de trabajo interactúa directamente con el modelo de datos unificado.

---

# Mapeo de Flujo: Interfaz vs. Schema Relacional

## 1. Pantalla: Planificador de Viaje (Crear Viaje)

Este panel unifica tres dominios: la disponibilidad de inventario (Shipping), la optimización geográfica (Planning) y la construcción del itinerario (Operations).

```text
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ Crear viaje · VJ-2026-0042                       BORRADOR         [Guardar] [Programar viaje]│
│ Salida: 12 jun · 08:00  ·  Plan v3  ·  Optimización: OR-Tools  ·  Sin guardar ●             │
```

### Acciones de Cabecera e Integración con BD
*   **Código de Viaje (`VJ-2026-0042`):** Generado mediante la función del sistema `public.generar_codigo_empresa('operations_viajes', empresa_id, 'VJ-2026-')`.
*   **Estado `BORRADOR`:** Almacenado en `operations_viajes.estado` como `'programado'`.
*   **Plan v3 / Optimización OR-Tools:** Representa un registro en la tabla `planning_optimizaciones` donde `algoritmo = 'google_or_tools'` y `version_plan = 3`.
*   **Fecha/Hora Salida:** Mapea directamente a `operations_viajes.hora_programada_salida`.

---

```text
│ PAQUETES DISPONIBLES    │ MAPA                             │ ITINERARIO                    │
│                         │                                  │                               │
│ [Buscar tracking...]    │           ② Cliente X            │ ① A · Almacén principal  🔒  │
│                         │          ╱                       │    08:00–09:00                │
│ Cliente  [Todos      ▼] │     ① A ●──────● C               │    ↑ Cargar 3 paquetes       │
```

### Panel Izquierdo: Paquetes Disponibles
*   **Query de Búsqueda:** Consume la vista segura `v_paquetes_completo`. Filtra los paquetes cuyo `estado_actual` apunta a `'CREADO'` o `'PREPARANDO'` y que **no** tienen registros activos en `operations_viajes_paquetes` gracias al índice de exclusión:
    ```sql
    CREATE UNIQUE INDEX uq_paquete_asignacion_activa ON operations_viajes_paquetes(paquete_id)
    WHERE deleted_at IS NULL AND estado NOT IN ('entregado', 'reasignado');
    ```
*   **Botón `[+ Agregar]`:** Inserta una fila en `operations_viajes_paquetes` vinculando el `paquete_id` al `viaje_id` actual.

### Panel Central: Mapa Interactivo
*   **Renderizado de Puntos:** Utiliza la columna `ubicacion` (tipo `GEOGRAPHY`) de las tablas `customers_direcciones` (para entregas a clientes) y `core_sucursales` (para el punto de partida y retorno A).

### Panel Derecho: Itinerario (Visitas del Viaje)
*   **Representación en BD:** Cada tarjeta numerada (①, ②, ③, ④) representa una fila en `operations_viaje_visitas` ordenada secuencialmente por la columna `orden`.
*   **Icono de Candado (🔒):** Indica que la visita está marcada como fija. En base de datos, esto interactúa con las restricciones del planificador en `operations_restricciones` bajo un tipo de restricción dura para el solver (`es_dura = TRUE`).

---

```text
│ CAPACIDAD DEL TRAMO                                                                      │
│ Peso 1,250/3,500 kg  ███████░░░ 36%  · Volumen 8.2/20 m³ ████░░░░░░ 41%                  │
│ Pallets 8/14 · Bultos 27/80 · ADR 0/2 · Temperatura 2–8 °C ✓                             │
```

### Cálculo de Capacidad Dinámica en Tiempo Real
*   El backend ejecuta agregaciones sobre los paquetes asignados al viaje en ese tramo de la ruta:
    ```sql
    SELECT 
        COALESCE(SUM(p.peso), 0) AS peso_total,
        COALESCE(SUM(p.volumen), 0) AS volumen_total,
        COALESCE(SUM(CASE WHEN p.tipo = 'pallet' THEN 1 ELSE 0 END), 0) AS pallets_totales
    FROM operations_viajes_paquetes ovp
    JOIN shipping_paquetes p ON ovp.paquete_id = p.id
    WHERE ovp.viaje_id = 'VJ-uuid' AND ovp.deleted_at IS NULL;
    ```
*   Estas sumas se contrastan contra los límites definidos en la tabla `fleet_capacidades` para el vehículo asignado.
*   **Temperatura (2–8 °C ✓):** Valida si algún paquete exige refrigeración (`shipping_paquetes.requiere_refrigeracion = TRUE`) y comprueba que el vehículo cuente con ella en `fleet_capacidades.tiene_refrigeracion = TRUE`.

---

## 2. Panel de Detalle de Parada (Visita)

Este panel lateral expone la granularidad del modelo **Operación vs. Ejecución** diseñado para soportar múltiples intentos sin perder la trazabilidad.

```text
┌─────────────────────────────────────────────────────┐
│ Parada 3 de 4                                  [×]  │
│ Cliente Y · Av. Principal 123                       │
│ ETA 12:20 · Ventana 12:00–13:00 · 20 min           │
│ Estado: PENDIENTE                                   │
```

*   **Identificación:** Representa un registro en `operations_viaje_visitas` donde el estado es `'pendiente'`.
*   **ETA e Intervalo:** Proviene de `operations_eta` (`eta_actual`) y de `operations_paradas` (`tiempo_estancia_min`).

---

```text
│ OPERACIONES                                         │
│                                                     │
│ ↓ Entregar · TRK002                                 │
│   Cliente Y · 18 kg                                 │
│   Requiere: escaneo, firma y fotografía             │
│   Estado: Pendiente                                 │
```

### Desacoplamiento de Procesos (Operaciones)
*   Cada una de estas acciones requeridas en la parada se almacena como un registro en `operations_visita_operaciones`.
*   **Atributos de Control:**
    *   `tipo_id` apunta al catálogo `operations_tipos_operacion` con códigos `'entregar'` o `'recoger'`.
    *   `total_intentos` (en este caso, `0`).
    *   `ejecucion_exitosa_id` (en este caso, `NULL`).

---

### Pestaña: Restricciones
```text
Restricciones
────────────────────────────────────
● Ventana horaria       12:00–13:00
● Requiere frío         2–8 °C
```
*   **Estructura Relacional:** Se mapea a la tabla `operations_restricciones`.
*   **Ejemplo de fila de BD para la ventana horaria:**
    *   `referencia_tipo`: `'visita'`
    *   `referencia_id`: `[UUID_de_la_visita]`
    *   `tipo`: `'ventana_horaria'`
    *   `valor`: `'{"inicio": "12:00", "fin": "13:00"}'::jsonb`
    *   `es_dura`: `TRUE`

---

### Pestaña: Eventos
```text
Eventos
────────────────────────────────────────
11:15  Optimización v3 aplicada
```
*   **Estructura Relacional:** Cada cambio en el diseño del viaje escribe un registro histórico en `operations_viajes_eventos`.
*   El cambio de orden de las paradas registra un evento con el payload correspondiente en la columna estructurada `metadata` (tipo `JSONB`).

---

## 3. Asignación de Recursos (Paso 2)

Asociación de los recursos físicos y humanos necesarios para la ejecución segura de la ruta.

```text
│ VEHÍCULO                         │ CONDUCTORES                      │
│ [ABC-123 · Volvo FH          ▼]  │ Principal [Carlos Gómez      ▼]  │
│ Remolque                         │ Relevo    [Luis Pérez        ▼]  │
│ [REM-009 · Refrigerado       ▼]  │                                  │
```

*   **Vehículo:** Se inserta en la tabla intermedia de control de flota `operations_viajes_vehiculos` con `tipo = 'principal'`.
*   **Remolque:** Se inserta en la misma tabla (`operations_viajes_vehiculos`) con `tipo = 'remolque'`.
*   **Conductores (Soporte de Relevos):** Se insertan en la tabla intermedia `operations_viajes_conductores`.
    *   Carlos Gómez se registra con `principal = TRUE`.
    *   Luis Pérez se registra con `principal = FALSE`.
*   **Validación de Disponibilidad (Cruces de Horarios):** Se comprueba que no existan solapamientos de viaje activos para el conductor consultando las sesiones en `tracking_sesiones` donde `fecha_fin IS NULL`.

---

## 4. Flujo de Ejecución en Ruta (Aplicación Móvil del Conductor)

Este flujo demuestra cómo la base de datos procesa las transacciones en tiempo real de forma segura y tolerante a fallos.

```text
┌───────────────────────────────┐
│ Cliente Y · EN PROCESO        │
│                               │
│ 1. Paquetes a entregar        │
│    ○ TRK002       [Escanear]  │
│ 2. Evidencias                 │
│    ○ Firma                    │
└───────────────────────────────┘
```

### Paso 1: Confirmar Llegada a Destino
*   El conductor presiona `[Confirmar llegada]`.
*   La aplicación móvil envía una solicitud que actualiza el estado de la visita:
    ```sql
    UPDATE operations_viaje_visitas 
    SET estado = 'en_proceso', hora_llegada = NOW() 
    WHERE id = '[visita_uuid]';
    ```

### Paso 2: Escaneo e Intentos de Entrega (Idempotencia y Reintentos)
*   El conductor escanea el paquete `TRK002` y captura la firma del cliente.
*   Al procesar la entrega, se invoca la función transaccional unificada:
    ```sql
    SELECT * FROM public.registrar_ejecucion(
        p_operacion_id := '[operacion_uuid]',
        p_resultado := 'exitosa',
        p_conductor_id := '[conductor_uuid]',
        p_client_operation_id := '[uuid_generado_por_la_app_movil]', -- Idempotencia ante reintentos de red
        p_receptor_nombre := 'Cliente Y'
    );
    ```

#### ¿Qué ocurre internamente en la Base de Datos durante esta llamada?
1.  **Bloqueo de Fila:** La función ejecuta `SELECT FOR UPDATE` sobre la operación en `operations_visita_operaciones`. Esto previene condiciones de carrera si el conductor presiona el botón varias veces o la red reenvía el paquete de datos.
2.  **Validación de Intentos:** Verifica que `total_intentos` no supere `max_intentos`.
3.  **Registro Histórico:** Inserta el intento en `operations_operacion_ejecuciones` incrementando el correlativo `numero_intento`.
4.  **Cierre de Operación:** Como el resultado fue `'exitosa'`, actualiza el estado de la operación a completada y asocia `ejecucion_exitosa_id` con el nuevo registro de ejecución.
5.  **Cierre de Custodia (Seguridad Logística):** Se dispara un trigger que cierra la custodia actual del paquete en la tabla `operations_custodia` (seteando `entregado_en = NOW()`) e inserta un nuevo registro transfiriendo la custodia física al cliente receptor final.
6.  **Despacho de Evento (Outbox Pattern):** Inserta un registro en `integration_outbox` con el payload de la entrega para que sea consumido asíncronamente por el integrador de eventos de la empresa:
    ```json
    {
      "viaje_id": "VJ-uuid",
      "paquete_id": "TRK002-uuid",
      "operacion_id": "operacion-uuid",
      "ejecucion_id": "ejecucion-uuid"
    }
    ```

---

### Paso 3: Manejo de Entregas Fallidas (Reintentos)

Si el cliente no se encuentra en el domicilio, el conductor registra el evento:

```text
No se pudo completar la entrega
Motivo: [ Cliente ausente             ▼ ]
```

```sql
SELECT * FROM public.registrar_ejecucion(
    p_operacion_id := '[operacion_uuid]',
    p_resultado := 'fallida',
    p_motivo_codigo := 'cliente_ausente',
    p_conductor_id := '[conductor_uuid]'
);
```

#### Comportamiento del Sistema en Fallos
*   La función registra una nueva ejecución en `operations_operacion_ejecuciones` con `resultado = 'fallida'` y vincula el `motivo_id` correspondiente a `'cliente_ausente'`.
*   El contador `total_intentos` en `operations_visita_operaciones` se incrementa en `1`.
*   **La operación sigue abierta:** La tarjeta de la parada en el sistema de despacho web vuelve a estar disponible para su planificación en una visita posterior (segundo intento), manteniendo intacto el historial de auditoría de los intentos previos del día.

---

## 5. Auditoría y Trazabilidad en Tiempo Real (Pantalla de Viaje en Curso)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ VJ-2026-0042 · EN CURSO            Plan v3 · Último GPS hace 20 segundos   │
├──────────────────────────────────────────┬──────────────────────────────────┤
│ MAPA                                     │ PROGRESO                         │
│ A ✓────C ✓────●────D────F                │ ✓ 1. A · Completada             │
│             vehículo                     │ ✓ 2. C · Completada             │
```

### Sincronización del Mapa y Telemetría
*   **Último GPS:** La UI del mapa consume la vista de alta velocidad `v_ultima_posicion_gps`, la cual lee directamente de la tabla de caché indexada `tracking_ultima_posicion`. Esto evita realizar escaneos secuenciales costosos sobre la tabla histórica de telemetría (`tracking_gps`), garantizando tiempos de respuesta inferiores a 10ms.
*   **Puntos de Recorrido:** Las coordenadas históricas se guardan de forma optimizada en la tabla particionada por rango mensual `tracking_gps`.
*   **Eventos de Geocerca:** Cuando el vehículo ingresa al polígono almacenado en `operations_geocercas.poligono`, el motor espacial de la base de datos detecta la intersección:
    ```sql
    ST_Contains(geocerca.poligono, gps.ubicacion::geometry)
    ```
    Al detectarse, se inserta automáticamente un evento en `tracking_eventos` con tipo `'entrada_geocerca'`, actualizando la interfaz del despachador de inmediato.