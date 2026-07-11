import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/gps_service.dart';
import 'package:tracking_system_app/core/services/log_service.dart';

/// Servicio que envía la posición GPS del vehículo a Supabase
class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  final SupabaseClient _client = SupabaseConfig.client;
  final GpsService _gps = GpsService.instance;

  StreamSubscription<Position>? _gpsSubscription;
  Timer? _sendTimer;
  bool _isActive = false;
  bool get isActive => _isActive;

  String? _activeTripId;
  String? _activeVehicleId;
  String? _activeConductorId;
  String? _activeEmpresaId;

  /// Inicia el envío de posición GPS para un viaje
  Future<void> startTracking({
    required String tripId,
    required String vehicleId,
    required String conductorId,
    required String empresaId,
  }) async {
    if (_isActive) {
      LogService.instance.info('LocationService ya está activo, reiniciando...');
      await stopTracking();
    }

    _activeTripId = tripId;
    _activeVehicleId = vehicleId;
    _activeConductorId = conductorId;
    _activeEmpresaId = empresaId;
    _isActive = true;

    LogService.instance.info('═══════════════════════════════════════');
    LogService.instance.info('📍 LocationService iniciado');
    LogService.instance.info('   trip: $tripId');
    LogService.instance.info('   vehicle: $vehicleId');
    LogService.instance.info('   conductor: $conductorId');
    LogService.instance.info('   empresa: $empresaId');
    LogService.instance.info('═══════════════════════════════════════');

    // Verificar permisos
    final hasPermission = await _gps.checkPermissions();
    if (!hasPermission) {
      LogService.instance.error('❌ Sin permisos de GPS');
      // Continuar igual con posición por defecto (para emuladores)
    }

    // Intentar obtener posición real
    Position? initialPos;
    try {
      initialPos = await _gps.getCurrentPosition();
      if (initialPos != null) {
        LogService.instance.info('📍 Posición inicial: ${initialPos.latitude}, ${initialPos.longitude}');
      } else {
        LogService.instance.info('⚠️ No se pudo obtener posición GPS (usando fallback)');
      }
    } catch (e) {
      LogService.instance.info('⚠️ Error al obtener posición GPS: $e');
    }

    // Si no hay posición real, usar Asunción como fallback (para emuladores)
    if (initialPos == null) {
      initialPos = Position(
        latitude: -25.2637,
        longitude: -57.5759,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      LogService.instance.info('📍 Usando posición fallback: Asunción, Paraguay');
    }

    // Enviar posición inicial
    await _sendPosition(initialPos);

    // Intentar iniciar el stream GPS (puede fallar en emuladores)
    try {
      await _gps.startTracking();
      LogService.instance.info('📍 GPS tracking iniciado (stream activo)');

      // Escuchar cambios de posición
      _gpsSubscription = _gps.positionStream.listen(
        (position) {
          LogService.instance.info('📍 Nueva posición: ${position.latitude}, ${position.longitude}');
          _sendPosition(position);
        },
        onError: (error) {
          LogService.instance.error('❌ Error en stream GPS', error);
        },
      );
    } catch (e) {
      LogService.instance.info('⚠️ No se pudo iniciar stream GPS: $e (usando timer solamente)');
    }

    // Timer de respaldo: enviar posición cada 10 segundos (incluso sin stream)
    _sendTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        if (!_isActive) return;
        final pos = _gps.lastPosition ?? initialPos;
        if (pos != null) {
          await _sendPosition(pos);
        }
      },
    );

    LogService.instance.info('✅ LocationService completamente activo');
  }

  /// Detiene el envío de posición GPS
  Future<void> stopTracking() async {
    if (!_isActive) return;

    LogService.instance.info('LocationService detenido');

    _isActive = false;
    _activeTripId = null;
    _activeVehicleId = null;
    _activeConductorId = null;
    _activeEmpresaId = null;

    await _gpsSubscription?.cancel();
    _gpsSubscription = null;

    _sendTimer?.cancel();
    _sendTimer = null;

    await _gps.stopTracking();
  }

  /// Envía la posición actual a Supabase
  Future<void> _sendPosition(Position position) async {
    if (!_isActive) return;
    if (_activeTripId == null || _activeVehicleId == null) return;
    if (_activeConductorId == null || _activeEmpresaId == null) return;

    try {
      // Construir WKT para PostGIS: POINT(longitud latitud)
      final ubicacionWkt = 'POINT(${position.longitude} ${position.latitude})';

      // Datos completos para tracking_gps (tabla histórica)
      final dataGps = {
        'empresa_id': _activeEmpresaId,
        'viaje_id': _activeTripId,
        'vehiculo_id': _activeVehicleId,
        'conductor_id': _activeConductorId,
        'latitud': position.latitude,
        'longitud': position.longitude,
        'ubicacion': ubicacionWkt,
        'precision_m': position.accuracy,
        'altitud': position.altitude,
        'velocidad_kmh': position.speed * 3.6, // m/s a km/h
        'rumbo': position.heading,
        'bateria': 100, // TODO: obtener del device
        'internet': true,
        'gps': true,
        'satelites': 0, // TODO: obtener del GPS
      };

      // Datos para tracking_ultima_posicion (tabla cache - sin altitud)
      final dataUltima = {
        'vehiculo_id': _activeVehicleId,
        'empresa_id': _activeEmpresaId,
        'viaje_id': _activeTripId,
        'conductor_id': _activeConductorId,
        'latitud': position.latitude,
        'longitud': position.longitude,
        'ubicacion': ubicacionWkt,
        'precision_m': position.accuracy,
        'velocidad_kmh': position.speed * 3.6,
        'rumbo': position.heading,
        'bateria': 100,
        'internet': true,
        'gps': true,
        'satelites': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      LogService.instance.info('📤 Enviando GPS a Supabase...');

      // 1. Insertar en tracking_gps (histórico - tiene todas las columnas)
      await _client.from('tracking_gps').insert(dataGps);
      LogService.instance.info('✅ GPS insertado en tracking_gps');

      // 2. Upsert en tracking_ultima_posicion (cache - solo columnas que existen)
      await _client.from('tracking_ultima_posicion').upsert(
        dataUltima,
        onConflict: 'vehiculo_id',
      );
      LogService.instance.info('✅ Última posición actualizada');

      LogService.instance.debug(
        'GPS enviado: ${position.latitude}, ${position.longitude}',
      );
    } catch (e, st) {
      LogService.instance.error('❌ Error al enviar GPS', e);
      LogService.instance.error('Stack', st);
    }
  }

  void dispose() {
    stopTracking();
  }
}
