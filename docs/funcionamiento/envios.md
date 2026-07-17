# Pantalla final: Planificador de viaje

La interfaz final mantiene el término **“Parada”** para el usuario, aunque internamente cada elemento sea una **visita del viaje**. La complejidad de operaciones, ejecuciones, evidencias, custodia y eventos queda disponible en paneles secundarios sin sobrecargar la planificación.

```text
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ Crear viaje · VJ-2026-0042                       BORRADOR         [Guardar] [Programar viaje]│
│ Salida: 12 jun · 08:00  ·  Plan v3  ·  Optimización: OR-Tools  ·  Sin guardar ●             │
├─────────────────────────┬──────────────────────────────────┬───────────────────────────────┤
│ PAQUETES DISPONIBLES    │ MAPA                             │ ITINERARIO                    │
│                         │                                  │                               │
│ [Buscar tracking...]    │           ② Cliente X            │ ① A · Almacén principal  🔒  │
│                         │          ╱                       │    08:00–09:00                │
│ Cliente  [Todos      ▼] │     ① A ●──────● C               │    ↑ Cargar 3 paquetes       │
│ Zona     [Todas      ▼] │                  ╲                │    1,250 kg después          │
│ Fecha    [12/06/2026 ▼] │                   ● D ③           │                               │
│ Prioridad[Todas      ▼] │                     ╲             │ ② C · Cliente X              │
│                         │                      ● F ④         │    ETA 10:45 · 12.8 km       │
│ 8 paquetes encontrados  │                                  │    ↓ Entregar 2 paquetes     │
│                         │                                  │    Firma · Foto              │
│ ┌─────────────────────┐ │                                  │                               │
│ │ TRK001       ALTA   │ │                                  │ ③ D · Cliente Y              │
│ │ Cliente X           │ │                                  │    ETA 12:20 · 34.2 km       │
│ │ A → C               │ │                                  │    ↓ Entregar 1 paquete      │
│ │ 12 kg · 0.04 m³     │ │                                  │    ↑ Recoger 1 paquete       │
│ │ Antes de 13:00      │ │                                  │    Ventana 12:00–13:00 ⚠    │
│ │ [+ Agregar]         │ │                                  │                               │
│ └─────────────────────┘ │                                  │ ④ F · Centro de destino     │
│                         │                                  │    ETA 15:30 · 56.4 km       │
│ ┌─────────────────────┐ │                                  │    ↓ Entregar 5 paquetes     │
│ │ TRK002       NORMAL │ │                                  │                               │
│ │ Cliente Y           │ │                                  │ [+ Agregar parada]           │
│ │ A → D               │ │                                  │ [Optimizar no fijas]         │
│ │ 18 kg · 0.08 m³     │ │                                  │                               │
│ │ [+ Agregar]         │ │                                  │                               │
│ └─────────────────────┘ │                                  │                               │
├─────────────────────────┴──────────────────────────────────┴───────────────────────────────┤
│ CAPACIDAD DEL TRAMO                                                                      │
│ Peso 1,250/3,500 kg  ███████░░░ 36%  · Volumen 8.2/20 m³ ████░░░░░░ 41%                  │
│ Pallets 8/14 · Bultos 27/80 · ADR 0/2 · Temperatura 2–8 °C ✓                             │
│ Distancia 145 km · Duración 5 h 40 min · 8 paquetes · 3 clientes · 4 paradas             │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Comportamiento del itinerario

Cada tarjeta representa una **visita**, por lo que una misma dirección puede aparecer varias veces:

```text
① A · Depósito — Carga inicial
② C · Cliente X — Entrega
③ D · Cliente Y — Entrega y recogida
④ F · Centro logístico — Descarga
⑤ A · Depósito — Retorno
```

Las tarjetas pueden:

- Arrastrarse y soltarse.
- Marcarse como fijas.
- Duplicarse para una segunda visita al mismo lugar.
- Mostrar alertas de capacidad y ventanas horarias.
- Expandirse para mostrar operaciones.
- Ser optimizadas sin modificar las visitas fijas.

---

# Panel de detalle de parada

Al seleccionar una parada se abre un panel lateral:

```text
┌─────────────────────────────────────────────────────┐
│ Parada 3 de 4                                  [×]  │
│ Cliente Y · Av. Principal 123                       │
│ ETA 12:20 · Ventana 12:00–13:00 · 20 min           │
│ Estado: PENDIENTE                                   │
├─────────────────────────────────────────────────────┤
│ [Operaciones] [Restricciones] [Eventos] [Lugar]     │
├─────────────────────────────────────────────────────┤
│ OPERACIONES                                         │
│                                                     │
│ ↓ Entregar · TRK002                                 │
│   Cliente Y · 18 kg                                 │
│   Requiere: escaneo, firma y fotografía             │
│   Estado: Pendiente                                 │
│   [Ver paquete]                                     │
│                                                     │
│ ↑ Recoger · TRK004                                  │
│   Destino final: F · 22 kg                          │
│   Requiere: escaneo                                 │
│   Estado: Pendiente                                 │
│   [Ver paquete]                                     │
│                                                     │
│ + Agregar operación                                 │
│   Recoger · Entregar · Inspeccionar · Transferir    │
│   Documentos · Descanso · Combustible · Otra        │
├─────────────────────────────────────────────────────┤
│ CARGA DESPUÉS DE LA PARADA                          │
│ Peso:    1,120 kg                                   │
│ Volumen: 7.8 m³                                     │
│ Pallets: 7                                          │
├─────────────────────────────────────────────────────┤
│ [Editar parada] [Marcar fija] [Eliminar]            │
└─────────────────────────────────────────────────────┘
```

## Pestaña “Restricciones”

```text
Restricciones
────────────────────────────────────
● Ventana horaria       12:00–13:00
● Requiere frío         2–8 °C
● Acceso restringido    Vehículos < 4 m
○ Evitar escaleras      Restricción blanda
● Requiere montacargas

[+ Agregar restricción]
```

## Pestaña “Eventos”

Durante la planificación muestra los cambios del plan:

```text
Eventos
────────────────────────────────────────
11:05  Parada agregada por Ana Torres
11:08  TRK004 asociado para recogida
11:12  Parada movida de posición 4 a 3
11:15  Optimización v3 aplicada
```

---

# Asignación de recursos

Se presenta como el siguiente paso del mismo flujo:

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Crear viaje · 2. Recursos                     [Volver al itinerario] │
├──────────────────────────────────┬───────────────────────────────────┤
│ VEHÍCULO                         │ CAPACIDADES                       │
│                                  │                                   │
│ [ABC-123 · Volvo FH          ▼]  │ Peso       1,250 / 3,500 kg  36% │
│ Estado: Disponible               │ Volumen    8.2 / 20 m³       41% │
│ Refrigeración: Sí                │ Pallets    8 / 14             57% │
│ ADR: Clases 2, 3 y 8             │ Bultos     27 / 80            34% │
│                                  │ ADR         0 / 2              0% │
│ Remolque                         │                                   │
│ [REM-009 · Refrigerado       ▼]  │ ✓ Capacidad válida               │
├──────────────────────────────────┼───────────────────────────────────┤
│ CONDUCTORES                      │ DISPONIBILIDAD                    │
│                                  │                                   │
│ Principal [Carlos Gómez      ▼]  │ ✓ Licencia vigente               │
│ Relevo    [Luis Pérez        ▼]  │ ✓ Sin viajes simultáneos         │
│                                  │ ⚠ Descanso requerido a las 14:00 │
├──────────────────────────────────┴───────────────────────────────────┤
│ Salida: [12/06/2026] [08:00] · Regreso estimado: [15:40]            │
│                                                     [Continuar →]   │
└──────────────────────────────────────────────────────────────────────┘
```

---

# Pantalla final de revisión

Antes de programar el viaje:

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Revisar viaje · VJ-2026-0042                     LISTO PARA PROGRAMAR│
├────────────────────────────────────┬─────────────────────────────────┤
│ RESUMEN                            │ VALIDACIONES                    │
│                                    │                                 │
│ Ruta           A → C → D → F       │ ✓ Recogidas antes de entregas  │
│ Paradas        4                    │ ✓ Capacidad válida             │
│ Operaciones    12                   │ ✓ Ventanas horarias            │
│ Paquetes       8                    │ ✓ Vehículo compatible          │
│ Clientes       3                    │ ✓ Licencias vigentes           │
│ Distancia      145 km               │ ⚠ Descanso a las 14:00         │
│ Duración       5 h 40 min           │                                 │
│ Vehículo       ABC-123              │ 0 errores · 1 advertencia      │
│ Conductor      Carlos Gómez         │                                 │
│ Plan           Versión 3            │ [Ver todas las validaciones]   │
│ Optimización   OR-Tools             │                                 │
├────────────────────────────────────┴─────────────────────────────────┤
│ ITINERARIO                                                           │
│ ① A 08:00  Cargar 3        ② C 10:45 Entregar 2                    │
│ ③ D 12:20  Entregar 1 / Recoger 1                                  │
│ ④ F 15:30  Entregar 5                                                │
├──────────────────────────────────────────────────────────────────────┤
│ [Guardar borrador] [Crear otra versión] [Optimizar] [Programar viaje]│
└──────────────────────────────────────────────────────────────────────┘
```

Al programarlo:

```text
✓ Viaje VJ-2026-0042 programado

Plan aplicado:       Versión 3
Paradas generadas:   4
Operaciones:         12
Paquetes asignados:  8
Conductor notificado
Aplicación sincronizada

[Ver viaje] [Descargar manifiesto] [Ir a viajes programados]
```

---

# Pantalla del viaje en curso

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ VJ-2026-0042 · EN CURSO            Plan v3 · Último GPS hace 20 segundos   │
│ ABC-123 · Carlos Gómez              [Chat] [Incidencia] [Más acciones ▾]    │
├──────────────────────────────────────────┬──────────────────────────────────┤
│ MAPA                                     │ PROGRESO                         │
│                                          │                                  │
│ A ✓────C ✓────●────D────F                │ ✓ 1. A · Completada             │
│             vehículo                     │ ✓ 2. C · Completada             │
│                                          │ ● 3. D · Próxima · ETA 12:20   │
│ Velocidad: 64 km/h                       │ ○ 4. F · Pendiente              │
│ Batería GPS: 82%                         │                                  │
│ Conexión: En línea                       │ [Ver itinerario completo]        │
├──────────────────────────────────────────┴──────────────────────────────────┤
│ OPERACIÓN                                                                  │
│ 8 paquetes · 3 entregados · 4 en tránsito · 1 pendiente de recogida        │
│ 6/12 operaciones completadas · 1 incidencia abierta                        │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ ALERTAS                       │ EVENTOS RECIENTES                           │
│ ⚠ ETA D +12 min              │ 10:50 TRK001 entregado y firmado           │
│ ⚠ Descanso próximo           │ 10:51 Evidencia fotográfica capturada      │
│                               │ 11:02 Vehículo salió de C                   │
└───────────────────────────────┴─────────────────────────────────────────────┘
```

---

# Aplicación final del conductor

La app no expone conceptos técnicos como versiones, restricciones o custodia. Trabaja con acciones simples por parada.

```text
┌───────────────────────────────┐
│ Parada 3 de 4                 │
│ Cliente Y                     │
│ Av. Principal 123             │
│                               │
│ ETA 12:20 · 14.5 km           │
│ Ventana 12:00–13:00           │
│                               │
│ Operaciones                   │
│ ↓ Entregar 1 paquete          │
│ ↑ Recoger 1 paquete           │
│ ✍ Obtener firma              │
│ 📷 Tomar fotografía          │
│                               │
│ [Iniciar navegación]          │
│ [Confirmar llegada]           │
└───────────────────────────────┘
```

Después de confirmar llegada:

```text
┌───────────────────────────────┐
│ Cliente Y · EN PROCESO        │
│                               │
│ 1. Paquetes a entregar        │
│    ○ TRK002       [Escanear]  │
│                               │
│ 2. Paquetes a recoger         │
│    ○ TRK004       [Escanear]  │
│                               │
│ 3. Evidencias                 │
│    ○ Firma                    │
│    ○ Fotografía               │
│                               │
│ [Registrar incidencia]        │
│ [Finalizar parada]            │
└───────────────────────────────┘
```

Si una entrega falla:

```text
No se pudo completar la entrega

Motivo:
[ Cliente ausente             ▼ ]

Observación:
[ No respondió al teléfono...   ]

[Tomar fotografía]
[Reprogramar intento]
[Confirmar intento fallido]
```

Esto crea una nueva **ejecución fallida**, pero mantiene la misma operación pendiente para otro intento.

---

## Navegación final

```text
Dashboard
├── Envíos
│   ├── Nuevo envío
│   ├── Todos los envíos
│   └── Paquetes
├── Planificación
│   ├── Crear viaje
│   ├── Viajes programados
│   ├── Rutas plantilla
│   ├── Optimización
│   └── Restricciones
├── Operación
│   ├── Viajes en curso
│   ├── Mapa en vivo
│   ├── Paradas
│   ├── Incidencias
│   └── Eventos
├── Flota
│   ├── Vehículos
│   ├── Conductores
│   ├── Capacidades
│   └── Mantenimiento
├── Clientes
├── Integraciones
└── Reportes
```

La pantalla principal sigue siendo sencilla: **paquetes, mapa e itinerario**. Los conceptos empresariales —ejecuciones, evidencias, custodia, restricciones, optimizaciones y eventos— aparecen solo cuando el usuario abre el detalle correspondiente.