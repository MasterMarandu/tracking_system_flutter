import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';

/// Datos del viaje activo del conductor, usados tanto por Dashboard como por Mis Viajes.
class ActiveTripData {
  final String id;
  final String code;
  final String status; // programado, en_curso, pausado, completado
  final String? departureTime;
  final String? estimatedArrival;
  final double? totalDistance;
  final double? remainingDistance;
  final int totalStops;
  final int completedStops;
  final int pendingPackages;
  final double progressPercent;
  final String? origin;
  final String? destination;
  final String? routeName;
  final String? vehiclePlate;
  final String? vehicleBrand;
  final String? vehicleModel;
  final String conductorId;
  final String empresaId;
  final String? vehiculoId;

  const ActiveTripData({
    required this.id,
    required this.code,
    required this.status,
    this.departureTime,
    this.estimatedArrival,
    this.totalDistance,
    this.remainingDistance,
    required this.totalStops,
    required this.completedStops,
    required this.pendingPackages,
    required this.progressPercent,
    this.origin,
    this.destination,
    this.routeName,
    this.vehiclePlate,
    this.vehicleBrand,
    this.vehicleModel,
    required this.conductorId,
    required this.empresaId,
    this.vehiculoId,
  });

  bool get isActive => status == 'en_curso' || status == 'pausado' || status == 'programado';
  bool get isCompleted => status == 'completado' || status == 'cancelado';
}

/// Servicio compartido para obtener el viaje activo del conductor.
/// Usa la misma lógica de consulta para Dashboard y Mis Viajes.
class CurrentTripService {
  static CurrentTripService? _instance;
  static CurrentTripService get instance => _instance ??= CurrentTripService._();
  CurrentTripService._();

  final SupabaseClient _client = SupabaseConfig.client;

  /// Obtiene el conductor y empresa del usuario actual.
  Future<_DriverContext?> _getDriverContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final coreUser = await _client
        .from('core_usuarios')
        .select('id, empresa_id')
        .eq('auth_user_id', user.id)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (coreUser == null) return null;

    final cond = await _client
        .from('fleet_conductores')
        .select('id')
        .eq('usuario_id', coreUser['id'])
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (cond == null) return null;

    return _DriverContext(
      conductorId: cond['id'] as String,
      empresaId: coreUser['empresa_id'] as String,
    );
  }

  /// Consulta unificada: obtiene el viaje activo prioritario del conductor.
  ///
  /// Prioridad: en_curso > pausado > programado.
  /// Mis mismos filtros y orden para Dashboard y Mis Viajes.
  Future<ActiveTripData?> fetchActiveTrip() async {
    final ctx = await _getDriverContext();
    if (ctx == null) return null;

    try {
      // CONSULTA MAESTRA: una sola consulta con joins
      final data = await _client
          .from('operations_viajes_conductores')
          .select('''
            viaje:operations_viajes!inner (
              id, codigo, estado, hora_real_salida, hora_programada_llegada,
              km_estimados, distancia_real_km,
              ruta:operations_rutas (origen, destino, nombre),
              vehiculos:operations_viajes_vehiculos (
                v:fleet_vehiculos (matricula, marca, modelo)
              ),
              checkpoints:operations_checkpoints ( estado ),
              paquetes:operations_viajes_paquetes ( id, estado )
            )
          ''')
          .eq('conductor_id', ctx.conductorId)
          .filter('deleted_at', 'is', null);

      if (data.isEmpty) return null;

      // Filtrar solo viajes activos y ordenar por prioridad
      final activeTrips = (data as List)
          .map((item) => item['viaje'] as Map<String, dynamic>)
          .where((v) {
            final estado = v['estado'] as String? ?? '';
            return estado == 'en_curso' ||
                estado == 'pausado' ||
                estado == 'programado';
          })
          .toList()
        ..sort((a, b) {
          final orderA = _priorityOrder(a['estado'] as String? ?? '');
          final orderB = _priorityOrder(b['estado'] as String? ?? '');
          return orderA.compareTo(orderB);
        });

      if (activeTrips.isEmpty) return null;

      final v = activeTrips.first;
      final checkpoints = v['checkpoints'] as List? ?? [];
      final paquetes = v['paquetes'] as List? ?? [];
      final vehs = v['vehiculos'] as List? ?? [];
      final ruta = v['ruta'] as Map<String, dynamic>?;

      final totalStops = checkpoints.length;
      final doneStops =
          checkpoints.where((c) => c['estado'] == 'completado').length;
      final pendingPkgs =
          paquetes.where((p) => p['estado'] != 'entregado').length;
      final progress =
          totalStops > 0 ? (doneStops / totalStops).clamp(0.0, 1.0).toDouble() : 0.0;

      String? plate, brand, model;
      if (vehs.isNotEmpty) {
        final vh = vehs.first['v'] as Map<String, dynamic>?;
        if (vh != null) {
          plate = vh['matricula'] as String?;
          brand = vh['marca'] as String?;
          model = vh['modelo'] as String?;
        }
      }

      return ActiveTripData(
        id: v['id'] as String,
        code: (v['codigo'] as String?) ?? '--',
        status: (v['estado'] as String?) ?? 'programado',
        departureTime: v['hora_real_salida'] as String?,
        estimatedArrival: v['hora_programada_llegada'] as String?,
        totalDistance: (v['km_estimados'] as num?)?.toDouble(),
        remainingDistance: (v['distancia_real_km'] as num?)?.toDouble(),
        totalStops: totalStops,
        completedStops: doneStops,
        pendingPackages: pendingPkgs,
        progressPercent: progress,
        origin: ruta?['origen'] as String?,
        destination: ruta?['destino'] as String?,
        routeName: ruta?['nombre'] as String?,
        vehiclePlate: plate,
        vehicleBrand: brand,
        vehicleModel: model,
        conductorId: ctx.conductorId,
        empresaId: ctx.empresaId,
        vehiculoId: vehs.isNotEmpty
            ? (vehs.first['vehiculo_id'] as String?)
            : null,
      );
    } catch (e) {
      debugPrint('CurrentTripService.fetchActiveTrip error: $e');
      return null;
    }
  }

  /// Obtiene todos los viajes del conductor (para la pantalla Mis Viajes).
  Future<List<ActiveTripData>> fetchAllTrips() async {
    final ctx = await _getDriverContext();
    if (ctx == null) return [];

    try {
      final data = await _client
          .from('operations_viajes_conductores')
          .select('''
            viaje:operations_viajes!inner (
              id, codigo, estado, hora_real_salida, hora_programada_llegada,
              km_estimados, distancia_real_km,
              ruta:operations_rutas (origen, destino, nombre),
              vehiculos:operations_viajes_vehiculos (
                v:fleet_vehiculos (matricula, marca, modelo)
              ),
              checkpoints:operations_checkpoints ( estado ),
              paquetes:operations_viajes_paquetes ( id, estado )
            )
          ''')
          .eq('conductor_id', ctx.conductorId)
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: false);

      return (data as List).map((item) {
        final v = item['viaje'] as Map<String, dynamic>;
        final checkpoints = v['checkpoints'] as List? ?? [];
        final paquetes = v['paquetes'] as List? ?? [];
        final vehs = v['vehiculos'] as List? ?? [];
        final ruta = v['ruta'] as Map<String, dynamic>?;

        final totalStops = checkpoints.length;
        final doneStops =
            checkpoints.where((c) => c['estado'] == 'completado').length;
        final pendingPkgs =
            paquetes.where((p) => p['estado'] != 'entregado').length;
        final progress = totalStops > 0
            ? (doneStops / totalStops).clamp(0.0, 1.0).toDouble()
            : 0.0;

        String? plate, brand, model;
        if (vehs.isNotEmpty) {
          final vh = vehs.first['v'] as Map<String, dynamic>?;
          if (vh != null) {
            plate = vh['matricula'] as String?;
            brand = vh['marca'] as String?;
            model = vh['modelo'] as String?;
          }
        }

        return ActiveTripData(
          id: v['id'] as String,
          code: (v['codigo'] as String?) ?? '--',
          status: (v['estado'] as String?) ?? 'programado',
          departureTime: v['hora_real_salida'] as String?,
          estimatedArrival: v['hora_programada_llegada'] as String?,
          totalDistance: (v['km_estimados'] as num?)?.toDouble(),
          remainingDistance: (v['distancia_real_km'] as num?)?.toDouble(),
          totalStops: totalStops,
          completedStops: doneStops,
          pendingPackages: pendingPkgs,
          progressPercent: progress,
          origin: ruta?['origen'] as String?,
          destination: ruta?['destino'] as String?,
          routeName: ruta?['nombre'] as String?,
          vehiclePlate: plate,
          vehicleBrand: brand,
          vehicleModel: model,
          conductorId: ctx.conductorId,
          empresaId: ctx.empresaId,
          vehiculoId: vehs.isNotEmpty
              ? (vehs.first['vehiculo_id'] as String?)
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('CurrentTripService.fetchAllTrips error: $e');
      return [];
    }
  }

  int _priorityOrder(String estado) => switch (estado) {
    'en_curso' => 1,
    'pausado' => 2,
    'programado' => 3,
    _ => 99,
  };
}

class _DriverContext {
  final String conductorId;
  final String empresaId;
  const _DriverContext({required this.conductorId, required this.empresaId});
}
