-- ============================================================================
-- DIAGNÓSTICO: Por qué el viaje VIA-6225 no aparece en la app del conductor
-- ============================================================================

-- 1. Datos del viaje
SELECT
    v.id,
    v.codigo,
    v.estado,
    v.empresa_id,
    v.deleted_at
FROM operations_viajes v
WHERE v.codigo = 'VIA-6225';

-- 2. Asignaciones del viaje (lo que muestra el panel)
SELECT
    ovc.id,
    ovc.viaje_id,
    ovc.conductor_id,
    ovc.estado       AS estado_asignacion,
    ovc.principal,
    ovc.deleted_at
FROM operations_viajes_conductores ovc
WHERE ovc.viaje_id = (SELECT id FROM operations_viajes WHERE codigo = 'VIA-6225');

-- 3. ¿Coincide el conductor_id con fleet_conductores?
SELECT
    fc.id,
    fc.usuario_id,
    fc.licencia,
    fc.estado,
    u.email,
    u.nombre || ' ' || u.apellido AS nombre_completo,
    u.auth_user_id,
    u.empresa_id
FROM fleet_conductores fc
JOIN core_usuarios u ON u.id = fc.usuario_id
WHERE fc.id IN (
    SELECT conductor_id
    FROM operations_viajes_conductores
    WHERE viaje_id = (SELECT id FROM operations_viajes WHERE codigo = 'VIA-6225')
);

-- 4. ¿Qué usuario está logueado en la app del conductor?
--    (reemplazá el email por el del conductor que está probando)
SELECT
    u.id              AS usuario_id,
    u.auth_user_id,
    u.nombre || ' ' || u.apellido AS nombre,
    u.email,
    u.empresa_id,
    u.activo,
    fc.id             AS flota_conductor_id
FROM core_usuarios u
LEFT JOIN fleet_conductores fc ON fc.usuario_id = u.id AND fc.deleted_at IS NULL
WHERE u.email = 'EMAIL_DEL_CONDUCTOR_AQUI'
  AND u.deleted_at IS NULL;

-- 5. Simulación de lo que hace la RPC get_driver_bootstrap()
--    (reemplazá el auth_user_id por el que te devuelva la consulta 4)
SELECT
    ov.id,
    ov.codigo,
    ov.estado,
    ovc.conductor_id,
    ovc.estado AS estado_asignacion
FROM operations_viajes ov
JOIN operations_viajes_conductores ovc ON ovc.viaje_id = ov.id
JOIN fleet_conductores fc ON fc.id = ovc.conductor_id
JOIN core_usuarios u ON u.id = fc.usuario_id
WHERE u.auth_user_id = 'AUTH_USER_ID_AQUI'
  AND ov.estado IN ('en_curso', 'programado', 'pausado')
  AND ov.deleted_at IS NULL
  AND ovc.deleted_at IS NULL
ORDER BY ov.created_at DESC;

-- 6. Checkpoints del viaje (la RPC los lee para progreso)
SELECT
    oc.id,
    oc.parada_id,
    oc.estado,
    oc.deleted_at
FROM operations_checkpoints oc
WHERE oc.viaje_id = (SELECT id FROM operations_viajes WHERE codigo = 'VIA-6225');
