import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/log_service.dart';
import 'package:tracking_system_app/features/sync/data/local_cache.dart';

/// Foreground/background GPS uploader.
///
/// Corre en un isolate separado: sobrevive al cerrar la UI (Android FGS).
/// El contexto del viaje se lee de [LocalCache] (no se comparte memoria con la UI).
class BackgroundService {
  static BackgroundService? _instance;
  static BackgroundService get instance =>
      _instance ??= BackgroundService._();

  BackgroundService._();

  static const notificationChannelId = AppConstants.notificationChannelId;
  static const notificationId = 888;

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _configured = false;

  Future<bool> get isRunning => _service.isRunning();

  /// Debe llamarse una vez desde [main] antes de [runApp].
  Future<void> initialize() async {
    if (_configured) return;

    final notifications = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      notificationChannelId,
      AppConstants.notificationChannelName,
      description: AppConstants.notificationChannelDescription,
      importance: Importance.low,
    );

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: gpsBackgroundOnStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: AppConstants.appName,
        initialNotificationContent: 'Seguimiento GPS activo',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: gpsBackgroundOnStart,
        onBackground: gpsBackgroundOnIosBackground,
      ),
    );

    _configured = true;
    LogService.instance.info('BackgroundService configurado');
  }

  /// Arranca el servicio. El contexto del viaje debe estar ya en [LocalCache].
  Future<bool> start() async {
    try {
      if (!_configured) {
        await initialize();
      }

      final running = await _service.isRunning();
      if (running) {
        // Avisar al isolate que recargue contexto (p. ej. cambio de viaje).
        _service.invoke('reloadContext');
        LogService.instance.info('BackgroundService ya corría → reloadContext');
        return true;
      }

      final started = await _service.startService();
      LogService.instance.info(
        started
            ? 'BackgroundService iniciado'
            : 'BackgroundService no pudo iniciar',
      );
      return started;
    } catch (e, st) {
      LogService.instance.error('BackgroundService.start error', e, st);
      return false;
    }
  }

  Future<void> stop() async {
    try {
      final running = await _service.isRunning();
      if (!running) return;
      _service.invoke('stop');
      LogService.instance.info('BackgroundService stop invocado');
    } catch (e, st) {
      LogService.instance.error('BackgroundService.stop error', e, st);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Isolate entrypoints (top-level, @pragma vm:entry-point)
// ═══════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
Future<bool> gpsBackgroundOnIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // iOS background fetch: ciclo corto; el tracking continuo depende de
  // UIBackgroundModes=location + permisos Always.
  await _uploadOnceFromCache();
  return true;
}

@pragma('vm:entry-point')
void gpsBackgroundOnStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) async {
      await _setTrackingActive(false);
      await service.stopSelf();
    });

    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    // Asegurar modo foreground + tipo location
    service.setAsForegroundService();
  } else {
    service.on('stop').listen((_) async {
      await _setTrackingActive(false);
      await service.stopSelf();
    });
  }

  var reloadRequested = false;
  service.on('reloadContext').listen((_) {
    reloadRequested = true;
  });

  // Supabase en este isolate (sesión se restaura del storage local).
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 1),
    );
  } catch (_) {
    // Puede estar ya inicializado si el isolate se reutiliza.
  }

  CachedTripContext? ctx = await _loadActiveContext();
  if (ctx == null) {
    // Sin viaje activo: no quedarse vivo tras boot.
    await service.stopSelf();
    return;
  }

  final uuid = const Uuid();
  var lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      if (reloadRequested) {
        reloadRequested = false;
        ctx = await _loadActiveContext();
        if (ctx == null) {
          timer.cancel();
          await service.stopSelf();
          return;
        }
      }

      final active = await _isTrackingActive();
      if (!active) {
        timer.cancel();
        await service.stopSelf();
        return;
      }

      if (ctx == null) {
        ctx = await _loadActiveContext();
        if (ctx == null) {
          timer.cancel();
          await service.stopSelf();
          return;
        }
      }

      final position = await _readPosition();
      if (position == null) {
        _updateNotification(service, 'GPS sin señal');
        return;
      }

      // Evitar spam si el SO despierta el timer más seguido de lo esperado.
      final now = DateTime.now();
      if (now.difference(lastSentAt).inSeconds < 8) return;
      lastSentAt = now;

      final ok = await _sendOrBuffer(
        ctx: ctx!,
        position: position,
        uuid: uuid,
      );

      final speedKmh = (position.speed * 3.6).clamp(0, 999).toStringAsFixed(0);
      _updateNotification(
        service,
        ok
            ? 'GPS · ${position.latitude.toStringAsFixed(4)}, '
                '${position.longitude.toStringAsFixed(4)} · $speedKmh km/h'
            : 'GPS en buffer offline',
      );

      // Notificar a la UI si está viva (best-effort).
      service.invoke('trackingData', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': now.toIso8601String(),
        'uploaded': ok,
        'tripId': ctx!.tripId,
      });
    } catch (e) {
      _updateNotification(service, 'Error GPS: reintentando…');
    }
  });
}

Future<void> _updateNotification(ServiceInstance service, String content) async {
  if (service is! AndroidServiceInstance) return;
  if (!await service.isForegroundService()) return;
  service.setForegroundNotificationInfo(
    title: AppConstants.appName,
    content: content,
  );
}

Future<CachedTripContext?> _loadActiveContext() async {
  try {
    final active = await _isTrackingActive();
    if (!active) return null;
    final cache = await LocalCache.create();
    return cache.loadTripContext();
  } catch (_) {
    return null;
  }
}

Future<bool> _isTrackingActive() async {
  try {
    final cache = await LocalCache.create();
    return cache.isGpsTrackingActive();
  } catch (_) {
    return false;
  }
}

Future<void> _setTrackingActive(bool active) async {
  try {
    final cache = await LocalCache.create();
    await cache.setGpsTrackingActive(active);
  } catch (_) {}
}

Future<Position?> _readPosition() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  } catch (_) {
    return null;
  }
}

/// Un ciclo de upload (iOS background fetch).
Future<void> _uploadOnceFromCache() async {
  try {
    final ctx = await _loadActiveContext();
    if (ctx == null) return;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      );
    } catch (_) {}

    final position = await _readPosition();
    if (position == null) return;
    await _sendOrBuffer(ctx: ctx, position: position, uuid: const Uuid());
  } catch (_) {}
}

/// true si se subió a Supabase; false si quedó en buffer local.
Future<bool> _sendOrBuffer({
  required CachedTripContext ctx,
  required Position position,
  required Uuid uuid,
}) async {
  final recordedAt = DateTime.now().toUtc();
  final dataGps = _buildGpsRow(
    empresaId: ctx.empresaId,
    viajeId: ctx.tripId,
    vehiculoId: ctx.vehiculoId,
    conductorId: ctx.conductorId,
    position: position,
    online: true,
    recordedAt: recordedAt,
  );
  final dataUltima = _buildUltimaRow(
    empresaId: ctx.empresaId,
    viajeId: ctx.tripId,
    vehiculoId: ctx.vehiculoId,
    conductorId: ctx.conductorId,
    position: position,
    online: true,
  );

  try {
    final client = Supabase.instance.client;
    // Sin sesión no tiene sentido insertar (RLS).
    if (client.auth.currentSession == null) {
      await _bufferPoint(ctx, position, uuid, recordedAt);
      return false;
    }

    await client.from('tracking_gps').insert(dataGps);
    await client.from('tracking_ultima_posicion').upsert(
          dataUltima,
          onConflict: 'vehiculo_id',
        );
    unawaited(_flushGpsBuffer(client));
    return true;
  } catch (_) {
    await _bufferPoint(ctx, position, uuid, recordedAt);
    return false;
  }
}

Future<void> _bufferPoint(
  CachedTripContext ctx,
  Position position,
  Uuid uuid,
  DateTime recordedAt,
) async {
  try {
    final cache = await LocalCache.create();
    await cache.enqueueGpsPoint(
      BufferedGpsPoint(
        id: uuid.v4(),
        empresaId: ctx.empresaId,
        viajeId: ctx.tripId,
        vehiculoId: ctx.vehiculoId,
        conductorId: ctx.conductorId,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speedMps: position.speed,
        heading: position.heading,
        recordedAt: recordedAt,
      ),
    );
  } catch (_) {}
}

Future<void> _flushGpsBuffer(SupabaseClient client) async {
  try {
    final cache = await LocalCache.create();
    final pending = await cache.loadGpsBuffer();
    if (pending.isEmpty) return;

    final remaining = <BufferedGpsPoint>[];
    for (var i = 0; i < pending.length; i++) {
      final point = pending[i];
      try {
        await client.from('tracking_gps').insert(point.toTrackingGpsInsert());
        if (i == pending.length - 1) {
          final nowUtc = DateTime.now().toUtc().toIso8601String();
          await client.from('tracking_ultima_posicion').upsert(
            {
              'vehiculo_id': point.vehiculoId,
              'empresa_id': point.empresaId,
              'viaje_id': point.viajeId,
              'conductor_id': point.conductorId,
              'latitud': point.lat,
              'longitud': point.lng,
              'ubicacion': 'POINT(${point.lng} ${point.lat})',
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
      } catch (_) {
        remaining.addAll(pending.sublist(i));
        break;
      }
    }

    if (remaining.isEmpty) {
      await cache.clearGpsBuffer();
    } else {
      await cache.replaceGpsBuffer(remaining);
    }
  } catch (_) {}
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
  return {
    'empresa_id': empresaId,
    'viaje_id': viajeId,
    'vehiculo_id': vehiculoId,
    'conductor_id': conductorId,
    'latitud': position.latitude,
    'longitud': position.longitude,
    'ubicacion': 'POINT(${position.longitude} ${position.latitude})',
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
  return {
    'vehiculo_id': vehiculoId,
    'empresa_id': empresaId,
    'viaje_id': viajeId,
    'conductor_id': conductorId,
    'latitud': position.latitude,
    'longitud': position.longitude,
    'ubicacion': 'POINT(${position.longitude} ${position.latitude})',
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
