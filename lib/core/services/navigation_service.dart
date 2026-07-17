import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/gps_service.dart';
import 'package:tracking_system_app/core/services/location_service.dart';

/// Resultado de la operación de navegación
class NavigationResult {
  final bool success;
  final String? error;
  final bool gpsStarted;
  final bool alreadyActive;

  const NavigationResult({
    required this.success,
    this.error,
    this.gpsStarted = false,
    this.alreadyActive = false,
  });

  static const ready = NavigationResult(success: true, alreadyActive: true);
  static const gpsFailed = NavigationResult(
    success: true,
    gpsStarted: false,
    error: 'GPS no disponible',
  );
}

/// Servicio compartido para abrir la navegación de un viaje.
/// Usado tanto por el Dashboard ("Navegar") como por Mis Viajes ("Continuar").
class NavigationService {
  static NavigationService? _instance;
  static NavigationService get instance => _instance ??= NavigationService._();
  NavigationService._();

  final SupabaseClient _client = SupabaseConfig.client;

  /// Abre la navegación para un viaje específico.
  ///
  /// [tripId] - ID del viaje a navegar
  /// [activateTrip] - Si true, cambia el estado del viaje a 'en_curso'
  ///                  (para viajes programados). Si false, solo abre el
  ///                  mapa manteniendo el estado actual (para "Continuar").
  ///
  /// Retorna [NavigationResult] con el resultado de la operación.
  Future<NavigationResult> openNavigation({
    required String tripId,
    bool activateTrip = false,
  }) async {
    // 1. Verificar GPS
    final hasPermission = await GpsService.instance.checkPermissions();
    if (!hasPermission) {
      return const NavigationResult(
        success: false,
        error: 'Activa el GPS para comenzar la navegación.',
      );
    }

    // 2. Obtener contexto del viaje (empresa, conductor, vehículo)
    final ctx = await _getTripContext(tripId);
    if (ctx == null) {
      return const NavigationResult(
        success: false,
        error: 'No se pudo obtener la información del viaje.',
      );
    }

    // 3. Iniciar/reiniciar GPS tracking (siempre con el viaje actual)
    // LocationService.startTracking ya reinicia si estaba activo.
    bool gpsStarted = false;
    try {
      await LocationService.instance.startTracking(
        tripId: ctx.tripId,
        vehicleId: ctx.vehiculoId,
        conductorId: ctx.conductorId,
        empresaId: ctx.empresaId,
      );
      gpsStarted = LocationService.instance.isActive;
    } catch (e) {
      debugPrint('NavigationService GPS start error: $e');
      gpsStarted = false;
    }

    // 4. Activar viaje si se solicita (programado -> en_curso)
    // Timestamps en UTC (mismo criterio que LocationService / Postgres timestamptz).
    if (activateTrip) {
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await _client.from('operations_viajes').update({
        'estado': 'en_curso',
        'hora_real_salida': nowUtc,
        'updated_at': nowUtc,
      }).eq('id', tripId);
    }

    return NavigationResult(
      success: true,
      gpsStarted: gpsStarted,
    );
  }

  /// Pausa un viaje y detiene el tracking GPS.
  Future<void> pauseTrip(String tripId) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await _client.from('operations_viajes').update({
      'estado': 'pausado',
      'updated_at': nowUtc,
    }).eq('id', tripId);

    await LocationService.instance.stopTracking();
  }

  /// Reanuda un viaje pausado y reinicia el tracking GPS.
  Future<NavigationResult> resumeTrip(String tripId) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await _client.from('operations_viajes').update({
      'estado': 'en_curso',
      'updated_at': nowUtc,
    }).eq('id', tripId);

    return openNavigation(tripId: tripId, activateTrip: false);
  }

  /// Obtiene el contexto necesario para iniciar tracking de un viaje.
  Future<_TripContext?> _getTripContext(String tripId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final coreUser = await _client
          .from('core_usuarios')
          .select('id, empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      if (coreUser == null) return null;

      final results = await Future.wait([
        _client
            .from('fleet_conductores')
            .select('id')
            .eq('usuario_id', coreUser['id'])
            .filter('deleted_at', 'is', null)
            .maybeSingle(),
        _client
            .from('operations_viajes_vehiculos')
            .select('vehiculo_id')
            .eq('viaje_id', tripId)
            .filter('deleted_at', 'is', null)
            .maybeSingle(),
      ]);

      final conductor = results[0] as Map<String, dynamic>?;
      final vehiculo = results[1] as Map<String, dynamic>?;
      if (conductor == null || vehiculo == null) return null;

      return _TripContext(
        tripId: tripId,
        empresaId: coreUser['empresa_id'] as String,
        conductorId: conductor['id'] as String,
        vehiculoId: vehiculo['vehiculo_id'] as String,
      );
    } catch (e) {
      debugPrint('NavigationService._getTripContext error: $e');
      return null;
    }
  }
}

class _TripContext {
  final String tripId;
  final String empresaId;
  final String conductorId;
  final String vehiculoId;

  const _TripContext({
    required this.tripId,
    required this.empresaId,
    required this.conductorId,
    required this.vehiculoId,
  });
}
