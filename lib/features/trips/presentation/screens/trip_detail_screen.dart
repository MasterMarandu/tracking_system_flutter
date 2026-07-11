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

  double get progress =>
      stops > 0 ? (completedStops / stops).clamp(0.0, 1.0) : 0.0;
  int get packagesDelivered =>
      (packages - packagesRemaining).clamp(0, packages);
}

// ==================== REPOSITORY ====================

class TripDetailRepository {
  final SupabaseClient _client;

  TripDetailRepository(this._client);

  Future<TripDetail> fetchTripDetail(String tripId) async {
    final viajeResult = await _client
        .from('operations_viajes')
        .select('''
          id, codigo, estado, hora_real_salida, hora_programada_llegada,
          km_estimados, distancia_real_km,
          operations_rutas (origen, destino, nombre),
          operations_viajes_vehiculos (
            fleet_vehiculos (matricula, marca, modelo)
          )
        ''')
        .eq('id', tripId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    if (viajeResult == null) throw Exception('Viaje no encontrado');

    final viaje = viajeResult;

    final checkpoints = await _client
        .from('operations_checkpoints')
        .select('''
          id, estado, parada_id,
          operations_paradas (nombre, direccion, latitud, longitud, orden, eta_minutos)
        ''')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: true);

    final paquetes = await _client
        .from('operations_viajes_paquetes')
        .select('id, estado, parada_id')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null);

    final stopsList = <TripStop>[];
    int order = 1;
    for (final cp in checkpoints) {
      final parada = cp['operations_paradas'] as Map<String, dynamic>?;
      final estado = cp['estado'] as String? ?? 'pendiente';
      final checkpointId = cp['id'] as String;
      final paradaId = cp['parada_id'] as String?;

      int pkgCount = 0;
      if (paradaId != null) {
        pkgCount = paquetes.where((p) => p['parada_id'] == paradaId).length;
      }

      stopsList.add(
        TripStop(
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
        ),
      );
    }

    stopsList.sort((a, b) => a.order.compareTo(b.order));

    String vehicleText = 'Sin asignar';
    final vehiculosAsignados = viaje['operations_viajes_vehiculos'] as List?;
    if (vehiculosAsignados != null && vehiculosAsignados.isNotEmpty) {
      final vh =
          vehiculosAsignados.first['fleet_vehiculos'] as Map<String, dynamic>?;
      if (vh != null) {
        final parts = <String>[];
        if (vh['matricula'] != null) parts.add(vh['matricula'] as String);
        if (vh['marca'] != null) parts.add(vh['marca'] as String);
        if (vh['modelo'] != null) parts.add(vh['modelo'] as String);
        if (parts.isNotEmpty) vehicleText = parts.join(' · ');
      }
    }

    final ruta = viaje['operations_rutas'] as Map<String, dynamic>?;
    final origin = ruta?['origen'] as String? ?? 'Origen';
    final destination = ruta?['destino'] as String? ?? 'Destino';
    final paquetesRestantes = paquetes
        .where((p) => p['estado'] != 'entregado')
        .length;

    final conductorResult = await _client
        .from('operations_viajes_conductores')
        .select('''
          conductor_id,
          fleet_conductores (licencia, core_usuarios (nombre, apellido))
        ''')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    String driverText = 'Sin asignar';
    if (conductorResult != null) {
      final conductor =
          conductorResult['fleet_conductores'] as Map<String, dynamic>?;
      if (conductor != null) {
        final usuario = conductor['core_usuarios'] as Map<String, dynamic>?;
        if (usuario != null) {
          final nombre = usuario['nombre'] as String? ?? '';
          final apellido = usuario['apellido'] as String? ?? '';
          final licencia = conductor['licencia'] as String? ?? '';
          driverText = '$nombre $apellido'.trim();
          if (licencia.isNotEmpty) driverText += ' · $licencia';
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
      completedStops: stopsList
          .where((s) => s.status == StopStatus.completed)
          .length,
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
      default:
        return StopStatus.pending;
    }
  }
}

// ==================== PROVIDERS ====================

final tripDetailRepositoryProvider = Provider<TripDetailRepository>((ref) {
  return TripDetailRepository(SupabaseConfig.client);
});

final tripDetailProvider = FutureProvider.family
    .autoDispose<TripDetail, String>((ref, tripId) async {
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

class _TripDetailScreenState extends ConsumerState<TripDetailScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    try {
      await ref.refresh(tripDetailProvider(widget.tripId).future);
      if (mounted) setState(() => _lastUpdated = DateTime.now());
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tripDetailProvider(widget.tripId));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const _LoadingView(),
        error: (_, __) => _ErrorView(onRetry: _refresh),
        data: (detail) {
          _animCtrl.forward();
          _lastUpdated ??= DateTime.now();
          return FadeTransition(
            opacity: _fadeIn,
            child: _TripContent(
              detail: detail,
              lastUpdated: _lastUpdated,
              onRefresh: _refresh,
            ),
          );
        },
      ),
    );
  }
}

// ==================== MAIN CONTENT ====================

class _TripContent extends StatelessWidget {
  final TripDetail detail;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const _TripContent({
    required this.detail,
    required this.lastUpdated,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Collapsing App Bar ──
          _TripSliverAppBar(detail: detail, onRefresh: onRefresh),

          // ── Route summary ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _RouteSummaryCard(detail: detail),
            ),
          ),

          // ── Metrics ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(child: _MetricsStrip(detail: detail)),
          ),

          // ── Progress ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(child: _ProgressSection(detail: detail)),
          ),

          // ── Itinerary header ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionLabel(
                title: 'Itinerario',
                badge: '${detail.stops}',
              ),
            ),
          ),

          // ── Stops list ──
          if (detail.stopsList.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: const SliverToBoxAdapter(child: _EmptyStops()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverList.builder(
                itemCount: detail.stopsList.length,
                itemBuilder: (context, i) => _StopTile(
                  stop: detail.stopsList[i],
                  index: i + 1,
                  total: detail.stopsList.length,
                ),
              ),
            ),

          // ── Operation details ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionLabel(title: 'Detalles de operación'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(child: _DetailsCard(detail: detail)),
          ),

          // ── Last updated ──
          if (lastUpdated != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _LastUpdatedLabel(time: lastUpdated!),
              ),
            ),

          // ── Bottom spacing ──
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ==================== SLIVER APP BAR ====================

class _TripSliverAppBar extends StatelessWidget {
  final TripDetail detail;
  final VoidCallback onRefresh;

  const _TripSliverAppBar({required this.detail, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusStyle = _resolveStatusStyle(scheme, detail.status);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 120,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.maybePop(context),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onRefresh,
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14, right: 16),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                detail.code,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _CompactStatusPill(style: statusStyle),
          ],
        ),
      ),
    );
  }
}

class _CompactStatusPill extends StatelessWidget {
  final _StatusStyle style;
  const _CompactStatusPill({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: style.containerColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.foreground,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: style.foreground,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ROUTE SUMMARY ====================

class _RouteSummaryCard extends StatelessWidget {
  final TripDetail detail;
  const _RouteSummaryCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final routeName = detail.originDetail?.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (routeName != null && routeName.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.alt_route_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    routeName,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Origin
          _EndpointRow(type: _EndpointType.origin, text: detail.origin),

          // Connector
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              children: List.generate(
                3,
                (_) => Container(
                  width: 2,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),

          // Destination
          _EndpointRow(
            type: _EndpointType.destination,
            text: detail.destination,
          ),
        ],
      ),
    );
  }
}

enum _EndpointType { origin, destination }

class _EndpointRow extends StatelessWidget {
  final _EndpointType type;
  final String text;

  const _EndpointRow({required this.type, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOrigin = type == _EndpointType.origin;

    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOrigin
                ? const Color(0xFF16A34A).withOpacity(0.15)
                : const Color(0xFFDC2626).withOpacity(0.15),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOrigin
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOrigin ? 'Origen' : 'Destino',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== METRICS ====================

class _MetricsStrip extends StatelessWidget {
  final TripDetail detail;
  const _MetricsStrip({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.straighten_rounded,
            value: detail.totalDistance != null
                ? '${detail.totalDistance!.toStringAsFixed(0)} km'
                : '—',
            label: 'Distancia',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            icon: Icons.schedule_rounded,
            value: _fmtTime(detail.estimatedArrival),
            label: 'Llegada est.',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            icon: Icons.inventory_2_outlined,
            value: detail.packages == 0
                ? '—'
                : '${detail.packagesDelivered}/${detail.packages}',
            label: 'Paquetes',
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ==================== PROGRESS ====================

class _ProgressSection extends StatelessWidget {
  final TripDetail detail;
  const _ProgressSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (detail.progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Progreso',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: detail.progress >= 1.0
                      ? const Color(0xFF16A34A)
                      : scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: detail.progress,
              minHeight: 8,
              backgroundColor: scheme.outlineVariant.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation(
                detail.progress >= 1.0
                    ? const Color(0xFF16A34A)
                    : scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${detail.completedStops} de ${detail.stops} paradas',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (detail.packages > 0)
                Text(
                  '${detail.packagesDelivered}/${detail.packages} entregados',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== SECTION LABEL ====================

class _SectionLabel extends StatelessWidget {
  final String title;
  final String? badge;

  const _SectionLabel({required this.title, this.badge});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ==================== STOP TILE ====================

class _StopTile extends StatelessWidget {
  final TripStop stop;
  final int index;
  final int total;

  const _StopTile({
    required this.stop,
    required this.index,
    required this.total,
  });

  bool get _isLast => index == total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _resolveStopStyle(scheme, stop.status);
    final isCurrent =
        stop.status == StopStatus.inProgress || stop.status == StopStatus.llego;

    return Padding(
      padding: EdgeInsets.only(bottom: _isLast ? 0 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Timeline column ──
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  _StopIndicator(stop: stop, index: index, style: style),
                  if (!_isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: stop.status == StopStatus.completed
                              ? const Color(0xFF16A34A).withOpacity(0.4)
                              : scheme.outlineVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Content card ──
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? scheme.primaryContainer.withOpacity(0.5)
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCurrent
                        ? scheme.primary.withOpacity(0.4)
                        : scheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + status
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            stop.name ?? 'Sin nombre',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: stop.status == StopStatus.completed
                                      ? scheme.onSurfaceVariant
                                      : null,
                                  decoration:
                                      stop.status == StopStatus.completed
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: scheme.onSurfaceVariant,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CompactStatusPill(style: style),
                      ],
                    ),

                    // Address
                    if (stop.address != null &&
                        stop.address!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        stop.address!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Meta tags
                    if (stop.etaMinutes != null || stop.packages > 0) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (stop.etaMinutes != null)
                            _TagChip(
                              icon: Icons.schedule_rounded,
                              text: '${stop.etaMinutes} min',
                            ),
                          if (stop.packages > 0)
                            _TagChip(
                              icon: Icons.inventory_2_outlined,
                              text: '${stop.packages} pkg',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopIndicator extends StatelessWidget {
  final TripStop stop;
  final int index;
  final _StatusStyle style;

  const _StopIndicator({
    required this.stop,
    required this.index,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: style.markerBg,
        border: stop.status == StopStatus.pending
            ? Border.all(color: scheme.outlineVariant, width: 1.5)
            : null,
        boxShadow:
            (stop.status == StopStatus.inProgress ||
                stop.status == StopStatus.llego)
            ? [
                BoxShadow(
                  color: style.foreground.withOpacity(0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(child: _markerContent(context)),
    );
  }

  Widget _markerContent(BuildContext context) {
    switch (stop.status) {
      case StopStatus.completed:
        return const Icon(Icons.check_rounded, size: 16, color: Colors.white);
      case StopStatus.inProgress:
        return const Icon(
          Icons.local_shipping_rounded,
          size: 15,
          color: Colors.white,
        );
      case StopStatus.llego:
        return const Icon(
          Icons.location_on_rounded,
          size: 15,
          color: Colors.white,
        );
      case StopStatus.pending:
        return Text(
          '$index',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
    }
  }
}

class _TagChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TagChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== DETAILS CARD ====================

class _DetailsCard extends StatelessWidget {
  final TripDetail detail;
  const _DetailsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final rows = <_DetailRow>[
      _DetailRow(Icons.local_shipping_outlined, 'Vehículo', detail.vehicle),
      _DetailRow(Icons.person_outline_rounded, 'Conductor', detail.driver),
      if (detail.departureTime != null)
        _DetailRow(
          Icons.logout_rounded,
          'Salida real',
          _fmtDateTime(detail.departureTime!),
        ),
      if (detail.estimatedArrival != null)
        _DetailRow(
          Icons.flag_outlined,
          'Llegada est.',
          _fmtDateTime(detail.estimatedArrival!),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _DetailRowWidget(row: rows[i]),
            if (i < rows.length - 1)
              Divider(
                height: 1,
                indent: 60,
                color: scheme.outlineVariant.withOpacity(0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);
}

class _DetailRowWidget extends StatelessWidget {
  final _DetailRow row;
  const _DetailRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(row.icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  row.value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== LAST UPDATED ====================

class _LastUpdatedLabel extends StatelessWidget {
  final DateTime time;
  const _LastUpdatedLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');

    return Center(
      child: Text(
        'Última actualización · $h:$m',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant.withOpacity(0.6),
        ),
      ),
    );
  }
}

// ==================== EMPTY / LOADING / ERROR ====================

class _EmptyStops extends StatelessWidget {
  const _EmptyStops();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Sin paradas asignadas',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Aparecerán aquí cuando se configuren en la ruta.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator.adaptive(),
          SizedBox(height: 16),
          Text('Cargando viaje…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión e intenta nuevamente.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== STATUS STYLE SYSTEM ====================

class _StatusStyle {
  final String label;
  final Color foreground;
  final Color containerColor;
  final Color markerBg;

  const _StatusStyle({
    required this.label,
    required this.foreground,
    required this.containerColor,
    required this.markerBg,
  });
}

_StatusStyle _resolveStatusStyle(ColorScheme scheme, String status) {
  switch (status.toLowerCase()) {
    case 'en_curso':
    case 'en_proceso':
    case 'activo':
      return _StatusStyle(
        label: 'En curso',
        foreground: scheme.primary,
        containerColor: scheme.primaryContainer,
        markerBg: scheme.primary,
      );
    case 'completado':
      return _StatusStyle(
        label: 'Completado',
        foreground: const Color(0xFF16A34A),
        containerColor: const Color(0xFF16A34A).withOpacity(0.12),
        markerBg: const Color(0xFF16A34A),
      );
    case 'pausado':
      return _StatusStyle(
        label: 'Pausado',
        foreground: const Color(0xFFD97706),
        containerColor: const Color(0xFFD97706).withOpacity(0.12),
        markerBg: const Color(0xFFD97706),
      );
    case 'cancelado':
      return _StatusStyle(
        label: 'Cancelado',
        foreground: scheme.error,
        containerColor: scheme.errorContainer,
        markerBg: scheme.error,
      );
    default:
      return _StatusStyle(
        label: 'Programado',
        foreground: scheme.onSurfaceVariant,
        containerColor: scheme.surfaceContainerHighest,
        markerBg: scheme.surfaceContainerHighest,
      );
  }
}

_StatusStyle _resolveStopStyle(ColorScheme scheme, StopStatus status) {
  switch (status) {
    case StopStatus.completed:
      return _StatusStyle(
        label: 'Completada',
        foreground: const Color(0xFF16A34A),
        containerColor: const Color(0xFF16A34A).withOpacity(0.12),
        markerBg: const Color(0xFF16A34A),
      );
    case StopStatus.inProgress:
      return _StatusStyle(
        label: 'En curso',
        foreground: scheme.primary,
        containerColor: scheme.primaryContainer,
        markerBg: scheme.primary,
      );
    case StopStatus.llego:
      return _StatusStyle(
        label: 'Llegó',
        foreground: scheme.primary,
        containerColor: scheme.primaryContainer,
        markerBg: scheme.primary,
      );
    case StopStatus.pending:
      return _StatusStyle(
        label: 'Pendiente',
        foreground: scheme.onSurfaceVariant,
        containerColor: scheme.surfaceContainerHighest,
        markerBg: scheme.surfaceContainerLow,
      );
  }
}

// ==================== FORMATTERS ====================

String _fmtTime(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _fmtDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} · ${_fmtTime(l)}';
}
