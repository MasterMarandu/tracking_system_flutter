import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/background_service.dart';
import 'package:tracking_system_app/core/services/gps_service.dart';
import 'package:tracking_system_app/core/services/log_service.dart';
import 'package:tracking_system_app/features/sync/data/local_cache.dart';

/// Servicio que envía la posición GPS del vehículo a Supabase.
///
/// Preferencia: [BackgroundService] (sobrevive al cerrar la app).
/// Fallback: envío en el isolate de la UI si el servicio no arranca.
/// Sin red: acumula en buffer local y flushea al reconectar.
class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  final SupabaseClient _client = SupabaseConfig.client;
  final GpsService _gps = GpsService.instance;
  final _uuid = const Uuid();

  StreamSubscription<Position>? _gpsSubscription;
  Timer? _sendTimer;
  bool _isActive = false;
  bool get isActive => _isActive;

  /// true si el upload lo hace el isolate de background (no duplicar desde UI).
  bool _backgroundOwnsUpload = false;
  bool get backgroundOwnsUpload => _backgroundOwnsUpload;

  String? _activeTripId;
  String? _activeVehicleId;
  String? _activeConductorId;
  String? _activeEmpresaId;

  bool _flushing = false;

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
    _backgroundOwnsUpload = false;

    // Persistir contexto + flag para el isolate background / boot
    try {
      final cache = await LocalCache.create();
      await cache.saveTripContext(CachedTripContext(
        tripId: tripId,
        empresaId: empresaId,
        conductorId: conductorId,
        vehiculoId: vehicleId,
      ));
      await cache.setGpsTrackingActive(true);
    } catch (e) {
      LogService.instance.info('No se pudo guardar trip context: $e');
    }

    LogService.instance.info('═══════════════════════════════════════');
    LogService.instance.info('📍 LocationService iniciado');
    LogService.instance.info('   trip: $tripId');
    LogService.instance.info('   vehicle: $vehicleId');
    LogService.instance.info('═══════════════════════════════════════');

    final hasPermission = await _gps.checkPermissions();
    if (!hasPermission) {
      LogService.instance.error('❌ Sin permisos de GPS');
    } else {
      // Pedir "siempre" para tracking con app cerrada (best-effort).
      await _gps.requestBackgroundPermission();
    }

    // ── Background service (primario) ──
    try {
      _backgroundOwnsUpload = await BackgroundService.instance.start();
    } catch (e) {
      LogService.instance.info('BackgroundService no disponible: $e');
      _backgroundOwnsUpload = false;
    }

    LogService.instance.info(
      _backgroundOwnsUpload
          ? '✅ Upload GPS: BackgroundService (sobrevive al cerrar la app)'
          : '⚠️ Upload GPS: fallback en foreground (UI)',
    );

    Position? initialPos;
    try {
      initialPos = await _gps.getCurrentPosition();
    } catch (e) {
      LogService.instance.info('⚠️ Error al obtener posición GPS: $e');
    }

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
      LogService.instance.info('📍 Usando posición fallback: Asunción');
    }

    // Primer punto inmediato solo si el background no es el dueño del upload
    // (evita duplicar con el timer del isolate).
    if (!_backgroundOwnsUpload) {
      await _sendPosition(initialPos);
    }
    unawaited(flushGpsBuffer());

    // Stream GPS para UI (mapa) siempre; upload solo en fallback foreground.
    try {
      await _gps.startTracking();
      _gpsSubscription = _gps.positionStream.listen(
        (position) {
          if (!_backgroundOwnsUpload) {
            _sendPosition(position);
          }
        },
        onError: (error) {
          LogService.instance.error('❌ Error en stream GPS', error);
        },
      );
    } catch (e) {
      LogService.instance.info('⚠️ Stream GPS no disponible: $e');
    }

    if (!_backgroundOwnsUpload) {
      _sendTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) async {
          if (!_isActive || _backgroundOwnsUpload) return;
          final pos = _gps.lastPosition ?? initialPos;
          if (pos != null) {
            await _sendPosition(pos);
          }
        },
      );
    }

    LogService.instance.info('✅ LocationService completamente activo');
  }

  Future<void> stopTracking() async {
    if (!_isActive) {
      // Aun si la UI no tenía estado, apagar flag + servicio por si quedó colgado.
      try {
        final cache = await LocalCache.create();
        await cache.setGpsTrackingActive(false);
      } catch (_) {}
      await BackgroundService.instance.stop();
      return;
    }

    LogService.instance.info('LocationService detenido');

    _isActive = false;
    _backgroundOwnsUpload = false;
    _activeTripId = null;
    _activeVehicleId = null;
    _activeConductorId = null;
    _activeEmpresaId = null;

    await _gpsSubscription?.cancel();
    _gpsSubscription = null;

    _sendTimer?.cancel();
    _sendTimer = null;

    await _gps.stopTracking();

    try {
      final cache = await LocalCache.create();
      await cache.setGpsTrackingActive(false);
    } catch (_) {}

    await BackgroundService.instance.stop();
  }

  /// Envía posición; si falla, encola en buffer local.
  Future<void> _sendPosition(Position position) async {
    if (!_isActive) return;
    if (_activeTripId == null ||
        _activeVehicleId == null ||
        _activeConductorId == null ||
        _activeEmpresaId == null) {
      return;
    }

    final dataGps = _buildGpsRow(
      empresaId: _activeEmpresaId!,
      viajeId: _activeTripId!,
      vehiculoId: _activeVehicleId!,
      conductorId: _activeConductorId!,
      position: position,
      online: true,
      recordedAt: DateTime.now().toUtc(),
    );

    final dataUltima = _buildUltimaRow(
      empresaId: _activeEmpresaId!,
      viajeId: _activeTripId!,
      vehiculoId: _activeVehicleId!,
      conductorId: _activeConductorId!,
      position: position,
      online: true,
    );

    try {
      await _client.from('tracking_gps').insert(dataGps);
      await _client.from('tracking_ultima_posicion').upsert(
            dataUltima,
            onConflict: 'vehiculo_id',
          );
      LogService.instance.debug(
        'GPS enviado: ${position.latitude}, ${position.longitude}',
      );
      unawaited(flushGpsBuffer());
    } catch (e) {
      LogService.instance.info('GPS offline/error → buffer local: $e');
      await _bufferPoint(position);
    }
  }

  Future<void> _bufferPoint(Position position) async {
    if (_activeTripId == null ||
        _activeVehicleId == null ||
        _activeConductorId == null ||
        _activeEmpresaId == null) {
      return;
    }
    try {
      final cache = await LocalCache.create();
      await cache.enqueueGpsPoint(
        BufferedGpsPoint(
          id: _uuid.v4(),
          empresaId: _activeEmpresaId!,
          viajeId: _activeTripId!,
          vehiculoId: _activeVehicleId!,
          conductorId: _activeConductorId!,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speedMps: position.speed,
          heading: position.heading,
          recordedAt: DateTime.now().toUtc(),
        ),
      );
      final n = await cache.gpsBufferCount();
      LogService.instance.info('📦 GPS buffer: $n puntos pendientes');
    } catch (e) {
      LogService.instance.error('No se pudo bufferizar GPS', e);
    }
  }

  /// Sube puntos del buffer local a Supabase (FIFO, tope por lote).
  Future<int> flushGpsBuffer({int batchSize = 40}) async {
    if (_flushing) return 0;
    _flushing = true;
    var flushed = 0;
    try {
      final cache = await LocalCache.create();
      final pending = await cache.loadGpsBuffer();
      if (pending.isEmpty) return 0;

      LogService.instance.info('🔄 Flush GPS buffer: ${pending.length} puntos');

      final remaining = <BufferedGpsPoint>[];
      for (var i = 0; i < pending.length; i++) {
        final point = pending[i];
        try {
          await _client
              .from('tracking_gps')
              .insert(point.toTrackingGpsInsert());

          if (i == pending.length - 1 || (i + 1) % batchSize == 0) {
            final nowUtc = DateTime.now().toUtc().toIso8601String();
            final ubicacionWkt = 'POINT(${point.lng} ${point.lat})';
            await _client.from('tracking_ultima_posicion').upsert(
              {
                'vehiculo_id': point.vehiculoId,
                'empresa_id': point.empresaId,
                'viaje_id': point.viajeId,
                'conductor_id': point.conductorId,
                'latitud': point.lat,
                'longitud': point.lng,
                'ubicacion': ubicacionWkt,
                'precision_m': point.accuracy,
                'velocidad_kmh': (point.speedMps ?? 0) * 3.6,
                'rumbo': point.heading,
                'bateria': 100,
                'internet': true,
                'gps': true,
                'satelites': 0,
                'created_at': point.recordedAt.toUtc().toIso8601String(),
                'updated_at': nowUtc,
              },
              onConflict: 'vehiculo_id',
            );
          }
          flushed++;
        } catch (e) {
          remaining.addAll(pending.sublist(i));
          LogService.instance.info(
            'Flush GPS detenido en $i/$flushed enviados: $e',
          );
          break;
        }
      }

      if (remaining.isEmpty) {
        await cache.clearGpsBuffer();
      } else {
        await cache.replaceGpsBuffer(remaining);
      }

      LogService.instance.info('✅ GPS flush: $flushed enviados');
      return flushed;
    } catch (e) {
      LogService.instance.error('flushGpsBuffer error', e);
      return flushed;
    } finally {
      _flushing = false;
    }
  }

  Future<int> pendingGpsCount() async {
    try {
      final cache = await LocalCache.create();
      return cache.gpsBufferCount();
    } catch (_) {
      return 0;
    }
  }

  Map<String, dynamic> _buildGpsRow({
    required String empresaId,
    required String viajeId,
    required String vehiculoId,
    required String conductorId,
    required Position position,
    required bool online,
    required DateTime recordedAt,
  }) {
    final ubicacionWkt =
        'POINT(${position.longitude} ${position.latitude})';
    return {
      'empresa_id': empresaId,
      'viaje_id': viajeId,
      'vehiculo_id': vehiculoId,
      'conductor_id': conductorId,
      'latitud': position.latitude,
      'longitud': position.longitude,
      'ubicacion': ubicacionWkt,
      'precision_m': position.accuracy,
      'altitud': position.altitude,
      'velocidad_kmh': position.speed * 3.6,
      'rumbo': position.heading,
      'bateria': 100,
      'internet': online,
      'gps': true,
      'satelites': 0,
      'created_at': recordedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _buildUltimaRow({
    required String empresaId,
    required String viajeId,
    required String vehiculoId,
    required String conductorId,
    required Position position,
    required bool online,
  }) {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final ubicacionWkt =
        'POINT(${position.longitude} ${position.latitude})';
    return {
      'vehiculo_id': vehiculoId,
      'empresa_id': empresaId,
      'viaje_id': viajeId,
      'conductor_id': conductorId,
      'latitud': position.latitude,
      'longitud': position.longitude,
      'ubicacion': ubicacionWkt,
      'precision_m': position.accuracy,
      'velocidad_kmh': position.speed * 3.6,
      'rumbo': position.heading,
      'bateria': 100,
      'internet': online,
      'gps': true,
      'satelites': 0,
      'created_at': nowUtc,
      'updated_at': nowUtc,
    };
  }

  void dispose() {
    stopTracking();
  }
}
