import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/location_service.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';

// ==================== MODELS ====================

enum TripStatus { inProgress, completed, scheduled, paused }

class TripData {
  final String id;
  final String code;
  final String origin;
  final String destination;
  final String? destinationDetail;
  final int packages;
  final double? progress;
  final String distance;
  final String eta;
  final String vehicle;
  final String driver;
  final int stops;
  final int completedStops;
  final TripStatus status;
  final DateTime? departureTime;
  final DateTime? estimatedArrival;
  final double? totalDistance;
  final double? remainingDistance;

  TripData({
    required this.id,
    required this.code,
    required this.origin,
    required this.destination,
    this.destinationDetail,
    required this.packages,
    this.progress,
    required this.distance,
    required this.eta,
    required this.vehicle,
    required this.driver,
    required this.stops,
    required this.completedStops,
    required this.status,
    this.departureTime,
    this.estimatedArrival,
    this.totalDistance,
    this.remainingDistance,
  });
}

class TripContext {
  final String tripId;
  final String empresaId;
  final String conductorId;
  final String vehiculoId;

  const TripContext({
    required this.tripId,
    required this.empresaId,
    required this.conductorId,
    required this.vehiculoId,
  });
}

// ==================== REPOSITORY ====================

class TripsRepository {
  final SupabaseClient _client;

  TripsRepository(this._client);

  /// Obtiene todos los viajes del conductor logueado
  Future<List<TripData>> fetchTrips() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No hay sesión activa');
    }

    // 1. Obtener el conductor del usuario
    final conductorResult = await _client
        .from('fleet_conductores')
        .select('id, usuario_id, empresa_id, licencia, estado')
        .eq('usuario_id', (
          await _client
              .from('core_usuarios')
              .select('id')
              .eq('auth_user_id', user.id)
              .filter('deleted_at', 'is', null)
              .maybeSingle()
        )?['id'])
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    if (conductorResult == null) {
      return [];
    }

    final conductorId = conductorResult['id'] as String;

    // 2. Obtener los viajes asignados al conductor
    final viajesAsignados = await _client
        .from('operations_viajes_conductores')
        .select('''
          viaje_id,
          operations_viajes!inner (
            id,
            codigo,
            estado,
            hora_real_salida,
            hora_programada_llegada,
            km_estimados,
            distancia_real_km,
            operations_rutas (origen, destino, nombre),
            operations_viajes_vehiculos (
              fleet_vehiculos (matricula, marca, modelo)
            )
          )
        ''')
        .eq('conductor_id', conductorId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false);

    // 3. Para cada viaje, obtener los checkpoints y paquetes
    final trips = <TripData>[];

    for (final va in viajesAsignados) {
      final viaje = va['operations_viajes'] as Map<String, dynamic>;
      final viajeId = viaje['id'] as String;

      // Checkpoints
      final checkpoints = await _client
          .from('operations_checkpoints')
          .select('id, estado')
          .eq('viaje_id', viajeId)
          .filter('deleted_at', 'is', null);

      final totalStops = checkpoints.length;
      final completedStops = checkpoints
          .where((c) => c['estado'] == 'completado')
          .length;
      final progress = totalStops > 0 ? completedStops / totalStops : 0.0;

      // Paquetes
      final paquetes = await _client
          .from('operations_viajes_paquetes')
          .select('id')
          .eq('viaje_id', viajeId)
          .filter('deleted_at', 'is', null)
          .neq('estado', 'entregado');

      // Vehículo
      String vehicleText = 'Sin vehículo';
      final vehiculosAsignados = viaje['operations_viajes_vehiculos'] as List?;
      if (vehiculosAsignados != null && vehiculosAsignados.isNotEmpty) {
        final vh = vehiculosAsignados.first['fleet_vehiculos'] as Map<String, dynamic>?;
        if (vh != null) {
          final parts = <String>[];
          if (vh['matricula'] != null) parts.add(vh['matricula'] as String);
          if (vh['marca'] != null) parts.add(vh['marca'] as String);
          if (vh['modelo'] != null) parts.add(vh['modelo'] as String);
          if (parts.isNotEmpty) vehicleText = parts.join(' - ');
        }
      }

      // Ruta
      final ruta = viaje['operations_rutas'] as Map<String, dynamic>?;
      final origin = ruta?['origen'] as String? ?? 'Origen';
      final destination = ruta?['destino'] as String? ?? 'Destino';

      // Estado
      final estadoStr = viaje['estado'] as String? ?? 'programado';
      final status = _mapStatus(estadoStr);

      // Distancia y ETA
      final kmEstimados = (viaje['km_estimados'] as num?)?.toDouble();
      final distanceText = kmEstimados != null
          ? '${kmEstimados.toStringAsFixed(1)} km'
          : '—';

      final etaText = _formatEta(status, viaje);

      trips.add(TripData(
        id: viajeId,
        code: viaje['codigo'] as String? ?? '—',
        origin: origin,
        destination: destination,
        destinationDetail: ruta?['nombre'] as String?,
        packages: paquetes.length,
        progress: totalStops > 0 ? progress : null,
        distance: distanceText,
        eta: etaText,
        vehicle: vehicleText,
        driver: conductorResult['licencia'] as String? ?? '—',
        stops: totalStops,
        completedStops: completedStops,
        status: status,
        departureTime: viaje['hora_real_salida'] != null
            ? DateTime.tryParse(viaje['hora_real_salida'] as String)
            : null,
        estimatedArrival: viaje['hora_programada_llegada'] != null
            ? DateTime.tryParse(viaje['hora_programada_llegada'] as String)
            : null,
        totalDistance: kmEstimados,
        remainingDistance: (viaje['distancia_real_km'] as num?)?.toDouble(),
      ));
    }

    return trips;
  }

  /// Inicia un viaje cambiando su estado a 'en_curso'
  Future<void> startTrip(String tripId) async {
    try {
      await _client
          .from('operations_viajes')
          .update({
            'estado': 'en_curso',
            'hora_real_salida': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId)
          .filter('deleted_at', 'is', null);
    } catch (e) {
      throw Exception('Error al iniciar viaje: $e');
    }
  }

  /// Obtiene el contexto necesario para iniciar tracking GPS
  /// Retorna: empresaId, conductorId, vehiculoId
  Future<TripContext?> getTripContext(String tripId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    // Obtener usuario
    final coreUser = await _client
        .from('core_usuarios')
        .select('id, empresa_id')
        .eq('auth_user_id', user.id)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (coreUser == null) return null;

    // Obtener conductor
    final conductor = await _client
        .from('fleet_conductores')
        .select('id')
        .eq('usuario_id', coreUser['id'])
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (conductor == null) return null;

    // Obtener vehículo asignado al viaje
    final vehiculoAsignado = await _client
        .from('operations_viajes_vehiculos')
        .select('vehiculo_id')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (vehiculoAsignado == null) return null;

    return TripContext(
      tripId: tripId,
      empresaId: coreUser['empresa_id'] as String,
      conductorId: conductor['id'] as String,
      vehiculoId: vehiculoAsignado['vehiculo_id'] as String,
    );
  }

  /// Pausa un viaje cambiando su estado a 'pausado'
  Future<void> pauseTrip(String tripId) async {
    try {
      await _client
          .from('operations_viajes')
          .update({
            'estado': 'pausado',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId)
          .filter('deleted_at', 'is', null);
    } catch (e) {
      throw Exception('Error al pausar viaje: $e');
    }
  }

  /// Reanuda un viaje cambiando su estado a 'en_curso'
  Future<void> resumeTrip(String tripId) async {
    try {
      await _client
          .from('operations_viajes')
          .update({
            'estado': 'en_curso',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId)
          .filter('deleted_at', 'is', null);
    } catch (e) {
      throw Exception('Error al reanudar viaje: $e');
    }
  }

  TripStatus _mapStatus(String estado) {
    switch (estado) {
      case 'en_curso':
        return TripStatus.inProgress;
      case 'completado':
      case 'cancelado':
        return TripStatus.completed;
      case 'programado':
      case 'aceptado':
        return TripStatus.scheduled;
      case 'pausado':
        return TripStatus.paused;
      default:
        return TripStatus.scheduled;
    }
  }

  String _formatEta(TripStatus status, Map<String, dynamic> viaje) {
    if (status == TripStatus.completed) {
      return 'Completado';
    }

    final horaProgramada = viaje['hora_programada_llegada'] as String?;
    if (horaProgramada != null) {
      try {
        final dt = DateTime.parse(horaProgramada);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    if (status == TripStatus.scheduled) {
      return 'Programado';
    }

    return '—';
  }
}

// ==================== PROVIDER ====================

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(SupabaseConfig.client);
});

final tripsListProvider = FutureProvider.autoDispose<List<TripData>>((ref) async {
  // Refrescar cuando cambia el bootstrap (login/logout)
  ref.watch(bootstrapProvider);
  final repo = ref.watch(tripsRepositoryProvider);
  return repo.fetchTrips();
});

// ==================== MAIN SCREEN ====================

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Viajes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(tripsListProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: 'Activos'),
            Tab(text: 'Completados'),
            Tab(text: 'Programados'),
          ],
        ),
      ),
      body: tripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(tripsListProvider),
        ),
        data: (trips) {
          final active = trips
              .where((t) =>
                  t.status == TripStatus.inProgress ||
                  t.status == TripStatus.paused)
              .toList();
          final completed = trips
              .where((t) => t.status == TripStatus.completed)
              .toList();
          final scheduled = trips
              .where((t) => t.status == TripStatus.scheduled)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tripsListProvider);
              await ref.read(tripsListProvider.future);
            },
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTripList(active, 'No tienes viajes activos'),
                _buildTripList(completed, 'No tienes viajes completados'),
                _buildTripList(scheduled, 'No tienes viajes programados'),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleTripAction(TripData trip) async {
    final repo = ref.read(tripsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    debugPrint('🎯 _handleTripAction: ${trip.code}, status: ${trip.status}');

    try {
      switch (trip.status) {
        case TripStatus.scheduled:
          // Iniciar viaje
          await repo.startTrip(trip.id);
          // Obtener contexto e iniciar tracking GPS
          final context = await repo.getTripContext(trip.id);
          if (context != null) {
            await LocationService.instance.startTracking(
              tripId: context.tripId,
              vehicleId: context.vehiculoId,
              conductorId: context.conductorId,
              empresaId: context.empresaId,
            );
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text('Viaje ${trip.code} iniciado - GPS activo'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refrescar la lista
          ref.invalidate(tripsListProvider);
          break;
        case TripStatus.inProgress:
          // Mostrar opciones (pausar o ir al detalle)
          debugPrint('🎯 Mostrando bottom sheet para viaje en curso');
          await _showInProgressOptions(trip);
          debugPrint('🎯 Bottom sheet cerrado');
          break;
        case TripStatus.paused:
          // Reanudar
          await repo.resumeTrip(trip.id);
          final context = await repo.getTripContext(trip.id);
          if (context != null) {
            await LocationService.instance.startTracking(
              tripId: context.tripId,
              vehicleId: context.vehiculoId,
              conductorId: context.conductorId,
              empresaId: context.empresaId,
            );
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text('Viaje ${trip.code} reanudado - GPS activo'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          ref.invalidate(tripsListProvider);
          break;
        case TripStatus.completed:
          // Solo ver detalle
          messenger.showSnackBar(
            SnackBar(
              content: Text('Viaje ${trip.code} completado'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          break;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showInProgressOptions(TripData trip) async {
    final repo = ref.read(tripsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Viaje ${trip.code}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.gps_fixed, color: Colors.green),
              title: const Text('Reanudar GPS'),
              subtitle: const Text('Reiniciar el envío de ubicación'),
              onTap: () => Navigator.pop(ctx, 'resume_gps'),
            ),
            ListTile(
              leading: const Icon(Icons.pause_circle, color: Colors.orange),
              title: const Text('Pausar viaje'),
              subtitle: const Text('Detener temporalmente el viaje'),
              onTap: () => Navigator.pop(ctx, 'pause'),
            ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.blue),
              title: const Text('Ver detalles'),
              subtitle: const Text('Información del viaje en curso'),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (action == 'resume_gps') {
      try {
        // Reiniciar el GPS con el contexto del viaje
        final tripContext = await repo.getTripContext(trip.id);
        if (tripContext != null) {
          await LocationService.instance.startTracking(
            tripId: tripContext.tripId,
            vehicleId: tripContext.vehiculoId,
            conductorId: tripContext.conductorId,
            empresaId: tripContext.empresaId,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text('GPS reanudado para ${trip.code}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('No se pudo obtener el contexto del viaje'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'pause') {
      try {
        await repo.pauseTrip(trip.id);
        await LocationService.instance.stopTracking();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Viaje ${trip.code} pausado - GPS detenido'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.invalidate(tripsListProvider);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'detail') {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Detalle de ${trip.code}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildTripList(List<TripData> trips, String emptyMessage) {
    if (trips.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return _TripCard(
          trip: trips[index],
          onTap: () {
            // Navegar al detalle del viaje
            context.push('/trips/${trips[index].id}');
          },
          onAction: () => _handleTripAction(trips[index]),
        );
      },
    );
  }
}

// ==================== ERROR VIEW ====================

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar tus viajes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== COMPONENTS ====================

class _TripCard extends StatelessWidget {
  final TripData trip;
  final VoidCallback? onTap;
  final VoidCallback? onAction;

  const _TripCard({required this.trip, this.onTap, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _getStatusColor(trip.status, theme);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: trip.status == TripStatus.inProgress
            ? BorderSide(color: statusColor.withOpacity(0.5), width: 1.5)
            : BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // --- HEADER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.code,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(
                    status: trip.status,
                    color: statusColor,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            // --- TIMELINE / DESTINATION ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green, width: 2),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 2,
                            color: theme.colorScheme.outlineVariant,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.red, width: 2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.origin,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            trip.destination,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          if (trip.destinationDetail != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              trip.destinationDetail!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- PROGRESS BAR ---
            if (trip.progress != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: trip.progress,
                        minHeight: 8,
                        backgroundColor: theme.colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(trip.progress! * 100).toInt()}% completado',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${trip.completedStops} de ${trip.stops} paradas',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // --- STATS ROW ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _TripStat(
                    icon: Icons.inventory_2,
                    value: '${trip.packages}',
                    label: 'Paquetes',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _TripStat(
                    icon: Icons.route,
                    value: trip.distance,
                    label: 'Distancia',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _TripStat(
                    icon: Icons.schedule,
                    value: trip.eta,
                    label: trip.status == TripStatus.completed
                        ? 'Duración'
                        : 'ETA',
                  ),
                ],
              ),
            ),

            // --- VEHICLE & DRIVER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceVariant.withOpacity(0.3)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trip.vehicle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.badge,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trip.driver,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- ACTIONS (BUTTON) ---
            if (trip.status == TripStatus.inProgress ||
                trip.status == TripStatus.scheduled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: Icon(
                    trip.status == TripStatus.inProgress
                        ? Icons.navigation
                        : Icons.play_arrow,
                    size: 20,
                  ),
                  label: Text(
                    trip.status == TripStatus.inProgress
                        ? 'CONTINUAR VIAJE'
                        : 'INICIAR VIAJE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: trip.status == TripStatus.inProgress
                        ? theme.colorScheme.primary
                        : null,
                    foregroundColor: trip.status == TripStatus.inProgress
                        ? theme.colorScheme.onPrimary
                        : null,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: trip.status == TripStatus.inProgress ? 2 : 0,
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(TripStatus status, ThemeData theme) {
    switch (status) {
      case TripStatus.inProgress:
        return theme.colorScheme.primary;
      case TripStatus.completed:
        return Colors.green;
      case TripStatus.scheduled:
        return Colors.orange;
      case TripStatus.paused:
        return Colors.grey;
    }
  }
}

// ==================== SUB-WIDGETS ====================

class _StatusChip extends StatelessWidget {
  final TripStatus status;
  final Color color;
  final bool isDark;

  const _StatusChip({
    required this.status,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    switch (status) {
      case TripStatus.inProgress:
        label = 'En Curso';
        break;
      case TripStatus.completed:
        label = 'Completado';
        break;
      case TripStatus.scheduled:
        label = 'Programado';
        break;
      case TripStatus.paused:
        label = 'Pausado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _TripStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
