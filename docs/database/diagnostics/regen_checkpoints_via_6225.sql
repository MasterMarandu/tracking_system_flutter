-- ============================================================================
-- REGENERAR CHECKPOINTS para VIA-6225
-- El viaje existe pero no tiene checkpoints generados
-- ============================================================================

-- 1. Previsualizar qué se va a generar (rollback con ROLLBACK;)
BEGIN;

-- 2. Ver el viaje y su ruta
SELECT
    v.id          AS viaje_id,
    v.codigo,
    v.estado,
    v.ruta_id,
    r.nombre      AS ruta_nombre
FROM operations_viajes v
LEFT JOIN operations_rutas r ON r.id = v.ruta_id
WHERE v.codigo = 'VIA-6225';

-- 3. Ver las paradas de la ruta asociada
SELECT
    p.id,
    p.orden,
    p.nombre,
    p.direccion,
    p.latitud,
    p.longitud,
    p.tipo,
    p.eta_minutos
FROM operations_paradas p
WHERE p.ruta_id = (
    SELECT ruta_id FROM operations_viajes WHERE codigo = 'VIA-6225'
)
AND p.deleted_at IS NULL
ORDER BY p.orden;

-- 4. Insertar checkpoints para cada parada de la ruta
INSERT INTO operations_checkpoints (
    empresa_id,
    viaje_id,
    parada_id,
    estado,
    latitud,
    longitud
)
SELECT
    v.empresa_id,
    v.id,
    p.id,
    'pendiente',
    p.latitud,
    p.longitud
FROM operations_viajes v
JOIN operations_paradas p ON p.ruta_id = v.ruta_id
WHERE v.codigo = 'VIA-6225'
  AND v.deleted_at IS NULL
  AND p.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM operations_checkpoints oc
      WHERE oc.viaje_id = v.id
        AND oc.parada_id = p.id
        AND oc.deleted_at IS NULL
  )
ORDER BY p.orden;

-- 5. Verificar
SELECT
    oc.id,
    oc.estado,
    p.orden,
    p.nombre
FROM operations_checkpoints oc
JOIN operations_paradas p ON p.id = oc.parada_id
WHERE oc.viaje_id = (SELECT id FROM operations_viajes WHERE codigo = 'VIA-6225')
  AND oc.deleted_at IS NULL
ORDER BY p.orden;

-- Si todo está bien: COMMIT;
-- Si algo falló: ROLLBACK;
ROLLBACK;  -- Cambiá a COMMIT; cuando estés seguro
