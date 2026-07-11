import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';

// ==================== MODELS ====================

enum StopStatus { completed, inProgress, pending, llego }

class TripStop {
  final String id;
  final String checkpointId;
  final String? name;
  final String? address;
  final double? lat;
  final double? lng;
  final StopStatus status;
  final int order;
  final int? etaMinutes;
  final int packages;

  const TripStop({
    required this.id,
    required this.checkpointId,
    this.name,
    this.address,
    this.lat,
    this.lng,
    required this.status,
    required this.order,
    this.etaMinutes,
    this.packages = 0,
  });
}

class TripDetail {
  final String id;
  final String code;
  final String origin;
  final String destination;
  final String? originDetail;
  final String? destinationDetail;
  final String status;
  final double? totalDistance;
  final double? remainingDistance;
  final int stops;
  final int completedStops;
  final int packages;
  final int packagesRemaining;
  final String vehicle;
  final String driver;
  final DateTime? departureTime;
  final DateTime? estimatedArrival;
  final List<TripStop> stopsList;

  const TripDetail({
    required this.id,
    required this.code,
    required this.origin,
    required this.destination,
    this.originDetail,
    this.destinationDetail,
    required this.status,
    this.totalDistance,
    this.remainingDistance,
    required this.stops,
    required this.completedStops,
    required this.packages,
    required this.packagesRemaining,
    required this.vehicle,
    required this.driver,
    this.departureTime,
    this.estimatedArrival,
    required this.stopsList,
  });
}

// ==================== REPOSITORY ====================

class TripDetailRepository {
  final SupabaseClient _client;

  TripDetailRepository(this._client);

  Future<TripDetail> fetchTripDetail(String tripId) async {
    // 1. Obtener el viaje con sus relaciones
    final viajeResult = await _client
        .from('operations_viajes')
        .select('''
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
        ''')
        .eq('id', tripId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    if (viajeResult == null) {
      throw Exception('Viaje no encontrado');
    }

    final viaje = viajeResult;

    // 2. Obtener checkpoints
    final checkpoints = await _client
        .from('operations_checkpoints')
        .select('''
          id,
          estado,
          parada_id,
          operations_paradas (nombre, direccion, latitud, longitud, orden, eta_minutos)
        ''')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: true);

    // 3. Obtener paquetes
    final paquetes = await _client
        .from('operations_viajes_paquetes')
        .select('id, estado, parada_id')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null);

    // 4. Construir lista de paradas
    final stopsList = <TripStop>[];
    int order = 1;
    for (final cp in checkpoints) {
      final parada = cp['operations_paradas'] as Map<String, dynamic>?;
      final estado = cp['estado'] as String? ?? 'pendiente';
      final checkpointId = cp['id'] as String;
      final paradaId = cp['parada_id'] as String?;

      // Contar paquetes para esta parada
      int pkgCount = 0;
      if (paradaId != null) {
        pkgCount = paquetes
            .where((p) => p['parada_id'] == paradaId)
            .length;
      }

      stopsList.add(TripStop(
        id: paradaId ?? checkpointId,
        checkpointId: checkpointId,
        name: parada?['nombre'] as String? ?? 'Sin nombre',
        address: parada?['direccion'] as String?,
        lat: (parada?['latitud'] as num?)?.toDouble(),
        lng: (parada?['longitud'] as num?)?.toDouble(),
        status: _mapStopStatus(estado),
        order: order++,
        etaMinutes: parada?['eta_minutos'] as int?,
        packages: pkgCount,
      ));
    }

    // Ordenar por orden de la parada
    stopsList.sort((a, b) => a.order.compareTo(b.order));

    // 5. Vehículo
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

    // 6. Ruta
    final ruta = viaje['operations_rutas'] as Map<String, dynamic>?;
    final origin = ruta?['origen'] as String? ?? 'Origen';
    final destination = ruta?['destino'] as String? ?? 'Destino';

    // 7. Paquetes restantes
    final paquetesRestantes = paquetes
        .where((p) => p['estado'] != 'entregado')
        .length;

    // 8. Conductor (de la asignación)
    final conductorResult = await _client
        .from('operations_viajes_conductores')
        .select('''
          conductor_id,
          fleet_conductores (licencia, core_usuarios (nombre, apellido))
        ''')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    String driverText = '—';
    if (conductorResult != null) {
      final conductor = conductorResult['fleet_conductores'] as Map<String, dynamic>?;
      if (conductor != null) {
        final usuario = conductor['core_usuarios'] as Map<String, dynamic>?;
        if (usuario != null) {
          final nombre = usuario['nombre'] as String? ?? '';
          final apellido = usuario['apellido'] as String? ?? '';
          final licencia = conductor['licencia'] as String? ?? '';
          driverText = '$nombre $apellido · $licencia'.trim();
        }
      }
    }

    return TripDetail(
      id: tripId,
      code: viaje['codigo'] as String? ?? '—',
      origin: origin,
      destination: destination,
      originDetail: ruta?['nombre'] as String?,
      destinationDetail: null,
      status: viaje['estado'] as String? ?? 'programado',
      totalDistance: (viaje['km_estimados'] as num?)?.toDouble(),
      remainingDistance: (viaje['distancia_real_km'] as num?)?.toDouble(),
      stops: stopsList.length,
      completedStops: stopsList.where((s) => s.status == StopStatus.completed).length,
      packages: paquetes.length,
      packagesRemaining: paquetesRestantes,
      vehicle: vehicleText,
      driver: driverText,
      departureTime: viaje['hora_real_salida'] != null
          ? DateTime.tryParse(viaje['hora_real_salida'] as String)
          : null,
      estimatedArrival: viaje['hora_programada_llegada'] != null
          ? DateTime.tryParse(viaje['hora_programada_llegada'] as String)
          : null,
      stopsList: stopsList,
    );
  }

  StopStatus _mapStopStatus(String estado) {
    switch (estado) {
      case 'completado':
        return StopStatus.completed;
      case 'llego':
        return StopStatus.llego;
      case 'en_proceso':
        return StopStatus.inProgress;
      case 'pendiente':
      default:
        return StopStatus.pending;
    }
  }
}

// ==================== PROVIDER ====================

final tripDetailRepositoryProvider = Provider<TripDetailRepository>((ref) {
  return TripDetailRepository(SupabaseConfig.client);
});

final tripDetailProvider =
    FutureProvider.family.autoDispose<TripDetail, String>((ref, tripId) async {
  final repo = ref.watch(tripDetailRepositoryProvider);
  return repo.fetchTripDetail(tripId);
});

// ==================== SCREEN ====================

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto-refresh cada 30 segundos mientras la pantalla está activa
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        ref.invalidate(tripDetailProvider(widget.tripId));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(tripDetailProvider(widget.tripId));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Viaje'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(tripDetailProvider(widget.tripId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
        data: (detail) => _buildContent(context, ref, detail, colorScheme),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, TripDetail detail, ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: () async {
        // ignore: unused_result
        ref.refresh(tripDetailProvider(widget.tripId));
        await ref.read(tripDetailProvider(widget.tripId).future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _TripHeader(detail: detail),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _StatsRow(detail: detail),
                  const SizedBox(height: 24),
                  _SectionTitle(title: 'Paradas (${detail.stopsList.length})'),
                  const SizedBox(height: 12),
                  if (detail.stopsList.isEmpty)
                    const _EmptyStops()
                  else
                    ...List.generate(detail.stopsList.length, (i) {
                      return _StopTile(
                        stop: detail.stopsList[i],
                        index: i + 1,
                        isLast: i == detail.stopsList.length - 1,
                      );
                    }),
                  const SizedBox(height: 24),
                  _TripInfo(detail: detail),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== COMPONENTS ====================

class _TripHeader extends StatelessWidget {
  final TripDetail detail;

  const _TripHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  detail.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: detail.status),
            ],
          ),
          const SizedBox(height: 16),
          _RouteRow(
            icon: Icons.circle,
            color: Colors.green,
            label: 'Origen',
            value: detail.origin,
            detail: detail.originDetail,
          ),
          const SizedBox(height: 12),
          _RouteRow(
            icon: Icons.location_on,
            color: Colors.red,
            label: 'Destino',
            value: detail.destination,
            detail: detail.destinationDetail,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? detail;

  const _RouteRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'en_curso':
        bgColor = colorScheme.primary;
        textColor = colorScheme.onPrimary;
        label = 'En Curso';
        break;
      case 'completado':
        bgColor = Colors.green;
        textColor = Colors.white;
        label = 'Completado';
        break;
      case 'pausado':
        bgColor = Colors.orange;
        textColor = Colors.white;
        label = 'Pausado';
        break;
      case 'programado':
      default:
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade700;
        label = 'Programado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final TripDetail detail;

  const _StatsRow({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.route,
            label: 'Distancia',
            value: detail.totalDistance != null
                ? '${detail.totalDistance!.toStringAsFixed(1)} km'
                : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            icon: Icons.access_time,
            label: 'Tiempo',
            value: detail.estimatedArrival != null
                ? '${detail.estimatedArrival!.hour.toString().padLeft(2, '0')}:${detail.estimatedArrival!.minute.toString().padLeft(2, '0')}'
                : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            icon: Icons.inventory_2,
            label: 'Paquetes',
            value: '${detail.packagesRemaining}/${detail.packages}',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EmptyStops extends StatelessWidget {
  const _EmptyStops();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.location_off,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sin paradas asignadas',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final TripStop stop;
  final int index;
  final bool isLast;

  const _StopTile({
    required this.stop,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color circleColor;
    IconData? icon;
    bool showCheck = false;

    switch (stop.status) {
      case StopStatus.completed:
        circleColor = Colors.green;
        showCheck = true;
        break;
      case StopStatus.llego:
      case StopStatus.inProgress:
        circleColor = colorScheme.primary;
        icon = Icons.radio_button_checked;
        break;
      case StopStatus.pending:
        circleColor = colorScheme.outline;
        break;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stop.status == StopStatus.completed
                        ? Colors.green
                        : stop.status == StopStatus.pending
                            ? colorScheme.surfaceContainerHighest
                            : colorScheme.primary,
                    border: stop.status == StopStatus.pending
                        ? Border.all(color: colorScheme.outline)
                        : null,
                  ),
                  child: Center(
                    child: showCheck
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : icon != null
                            ? Icon(icon, size: 18, color: Colors.white)
                            : Text(
                                '$index',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: stop.status == StopStatus.completed
                          ? Colors.green
                          : colorScheme.outlineVariant,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name ?? 'Sin nombre',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: stop.status == StopStatus.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (stop.address != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stop.address!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (stop.etaMinutes != null) ...[
                        Icon(Icons.schedule, size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${stop.etaMinutes} min',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (stop.packages > 0) ...[
                        Icon(Icons.inventory_2, size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${stop.packages} paquetes',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripInfo extends StatelessWidget {
  final TripDetail detail;

  const _TripInfo({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _InfoRow(icon: Icons.local_shipping, label: 'Vehículo', value: detail.vehicle),
            const Divider(height: 24),
            _InfoRow(icon: Icons.person, label: 'Conductor', value: detail.driver),
            if (detail.departureTime != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.login,
                label: 'Salida',
                value: '${detail.departureTime!.hour.toString().padLeft(2, '0')}:${detail.departureTime!.minute.toString().padLeft(2, '0')}',
              ),
            ],
            if (detail.estimatedArrival != null) ...[
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.flag,
                label: 'Llegada estimada',
                value: '${detail.estimatedArrival!.hour.toString().padLeft(2, '0')}:${detail.estimatedArrival!.minute.toString().padLeft(2, '0')}',
              ),
            ],
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.check_circle,
              label: 'Progreso',
              value: '${detail.completedStops}/${detail.stops} paradas',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

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
            Icon(Icons.cloud_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar el viaje',
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
