import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/navigation_service.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';

// ==================== DESIGN TOKENS ====================

class _T {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double rMd = 14;
  static const double rXl = 24;
  static const double fCaption = 11;
  static const double fBody = 13;
  static const double fBodyLg = 15;
  static const double fTitle = 17;
  static const double fHeadline = 22;
  static const Color primary = Color(0xFF0F172A);
  static const Color accent = Color(0xFF2563EB);
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralBg = Color(0xFFF1F5F9);
  static const Color bg = Color(0xFFF8FAFC);
  static Color alpha(Color c, double a) => c.withValues(alpha: a);
  static List<BoxShadow> shadowSm = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}

// ==================== MODELS ====================

enum TripStatus { inProgress, completed, scheduled, paused }

class TripData {
  final String id, code, origin, destination, vehicle, driver;
  final String? destinationDetail;
  final int packages, stops, completedStops;
  final double? progress;
  final String distance, eta;
  final TripStatus status;
  final DateTime? departureTime, estimatedArrival;

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
  });
}

// ==================== REPOSITORY (1 SOLA CONSULTA) ====================

class TripsRepository {
  final SupabaseClient _client;
  TripsRepository(this._client);

  Future<List<TripData>> fetchTrips() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('No hay sesión activa');

    final coreUser = await _client
        .from('core_usuarios')
        .select('id')
        .eq('auth_user_id', user.id)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (coreUser == null) return [];

    final cond = await _client
        .from('fleet_conductores')
        .select('id, licencia')
        .eq('usuario_id', coreUser['id'])
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (cond == null) return [];

    // CONSULTA MAESTRA: viajes + rutas + vehículos + checkpoints + paquetes en 1 solo viaje de red
    final data = await _client
        .from('operations_viajes_conductores')
        .select('''
          viaje:operations_viajes!inner (
            id, codigo, estado, hora_real_salida, hora_programada_llegada, km_estimados,
            ruta:operations_rutas (origen, destino, nombre),
            vehiculos:operations_viajes_vehiculos ( v:fleet_vehiculos (matricula, marca, modelo) ),
            checkpoints:operations_checkpoints ( estado ),
            paquetes:operations_viajes_paquetes ( id, estado )
          )
        ''')
        .eq('conductor_id', cond['id'])
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false);

    return (data as List).map((item) {
      final v = item['viaje'] as Map<String, dynamic>;
      final ruta = v['ruta'] as Map<String, dynamic>?;
      final checkpoints = v['checkpoints'] as List? ?? [];
      final paquetes = v['paquetes'] as List? ?? [];
      final vehs = v['vehiculos'] as List? ?? [];

      final totalStops = checkpoints.length;
      final doneStops =
          checkpoints.where((c) => c['estado'] == 'completado').length;
      final pendingPkgs =
          paquetes.where((p) => p['estado'] != 'entregado').length;

      String vehicleText = 'Sin asignar';
      if (vehs.isNotEmpty) {
        final vh = vehs.first['v'] as Map<String, dynamic>?;
        if (vh != null) {
          vehicleText = [
            vh['matricula'],
            vh['marca'],
            vh['modelo'],
          ].where((e) => e != null && (e as String).isNotEmpty).join(' · ');
        }
      }

      final km = (v['km_estimados'] as num?)?.toDouble();
      final estadoStr = v['estado'] as String? ?? 'programado';

      return TripData(
        id: v['id'] as String,
        code: v['codigo'] ?? '--',
        origin: ruta?['origen'] as String? ?? 'Origen',
        destination: ruta?['destino'] as String? ?? 'Destino',
        destinationDetail: ruta?['nombre'] as String?,
        packages: pendingPkgs,
        progress: totalStops > 0
            ? (doneStops / totalStops).clamp(0.0, 1.0).toDouble()
            : null,
        distance: km != null ? '${km.toStringAsFixed(0)} km' : '--',
        eta: _formatEta(estadoStr, v['hora_programada_llegada'] as String?),
        vehicle: vehicleText,
        driver: cond['licencia'] ?? '--',
        stops: totalStops,
        completedStops: doneStops,
        status: _mapStatus(estadoStr),
        departureTime: v['hora_real_salida'] != null
            ? DateTime.tryParse(v['hora_real_salida'] as String)
            : null,
        estimatedArrival: v['hora_programada_llegada'] != null
            ? DateTime.tryParse(v['hora_programada_llegada'] as String)
            : null,
      );
    }).toList();
  }

  TripStatus _mapStatus(String s) => switch (s) {
    'en_curso' => TripStatus.inProgress,
    'completado' => TripStatus.completed,
    'pausado' => TripStatus.paused,
    _ => TripStatus.scheduled,
  };

  String _formatEta(String status, String? iso) {
    if (status == 'completado') return 'Finalizado';
    if (iso == null) return status == 'programado' ? 'Programado' : '--';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--';
    }
  }
}

// ==================== PROVIDERS ====================

final tripsRepositoryProvider = Provider<TripsRepository>(
  (ref) => TripsRepository(SupabaseConfig.client),
);

final tripsListProvider = FutureProvider.autoDispose<List<TripData>>((ref) {
  ref.watch(bootstrapProvider);
  return ref.watch(tripsRepositoryProvider).fetchTrips();
});

// ==================== SCREEN ====================

enum _Filter { active, completed, scheduled }

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});
  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  _Filter _filter = _Filter.active;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _actingTripId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsListProvider);

    return Scaffold(
      backgroundColor: _T.bg,
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          try {
            await ref.refresh(tripsListProvider.future);
          } catch (_) {
            // Silencioso: mantiene datos viejos si falla el refresh
          }
        },
        edgeOffset: 110,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              backgroundColor: Colors.white.withValues(alpha: 0.9),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              centerTitle: false,
              title: const Text(
                'Mis viajes',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _T.primary,
                  letterSpacing: -0.5,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: () => ref.invalidate(tripsListProvider),
                  icon: const Icon(Icons.refresh_rounded, color: _T.primary),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    _SearchField(
                      controller: _searchCtrl,
                      query: _query,
                      onClear: () => _searchCtrl.clear(),
                    ),
                    const SizedBox(height: 12),
                    _FilterPills(
                      filter: _filter,
                      onChanged: (f) => setState(() => _filter = f),
                      async: tripsAsync,
                    ),
                  ],
                ),
              ),
            ),
            tripsAsync.when(
              loading: () => const SliverToBoxAdapter(child: _SkeletonList()),
              error: (_, __) => SliverFillRemaining(
                child: _ErrorView(
                  onRetry: () => ref.invalidate(tripsListProvider),
                ),
              ),
              data: (all) {
                final filtered = _getFilteredTrips(all);
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyView(
                      filter: _filter,
                      hasQuery: _query.isNotEmpty,
                    ),
                  );
                }

                return SliverPadding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 120,
                    top: 4,
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _TripCardPremium(
                      trip: filtered[i],
                      index: i,
                      isActing: _actingTripId == filtered[i].id,
                      onTap: () => context.push('/trips/${filtered[i].id}'),
                      onAction: () => _handleAction(filtered[i]),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<TripData> _getFilteredTrips(List<TripData> all) {
    final byStatus = all.where((t) => switch (_filter) {
      _Filter.active =>
        t.status == TripStatus.inProgress || t.status == TripStatus.paused,
      _Filter.completed => t.status == TripStatus.completed,
      _Filter.scheduled => t.status == TripStatus.scheduled,
    }).toList();

    if (_query.isEmpty) return byStatus;
    return byStatus
        .where(
          (t) =>
              t.code.toLowerCase().contains(_query) ||
              t.destination.toLowerCase().contains(_query) ||
              t.origin.toLowerCase().contains(_query),
        )
        .toList();
  }

  Future<void> _handleAction(TripData trip) async {
    if (_actingTripId != null) return;
    setState(() => _actingTripId = trip.id);
    HapticFeedback.mediumImpact();

    final nav = NavigationService.instance;
    try {
      if (trip.status == TripStatus.scheduled) {
        // Iniciar viaje: activar + abrir mapa
        final result = await nav.openNavigation(
          tripId: trip.id,
          activateTrip: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.gpsStarted
                  ? 'Viaje ${trip.code} iniciado — GPS activo'
                  : result.success
                      ? 'Viaje ${trip.code} iniciado — GPS no disponible'
                      : result.error ?? 'Error al iniciar viaje',
            ),
            backgroundColor: result.gpsStarted
                ? _T.success
                : result.success
                    ? _T.warning
                    : _T.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        if (result.success) {
          ref.invalidate(tripsListProvider);
          if (mounted) context.go('/tracking');
          return;
        }
      } else if (trip.status == TripStatus.paused) {
        // Reanudar viaje pausado + abrir mapa
        final result = await nav.resumeTrip(trip.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? 'Viaje ${trip.code} reanudado'
                  : result.error ?? 'Error al reanudar viaje',
            ),
            backgroundColor: result.success ? _T.success : _T.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        if (result.success) {
          ref.invalidate(tripsListProvider);
          if (mounted) context.go('/tracking');
          return;
        }
      } else if (trip.status == TripStatus.inProgress) {
        // Continuar viaje: solo abrir mapa, sin cambiar estado
        final result = await nav.openNavigation(
          tripId: trip.id,
          activateTrip: false,
        );
        if (!mounted) return;
        if (result.success) {
          ref.invalidate(tripsListProvider);
          if (mounted) context.go('/tracking');
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Error al abrir navegación'),
            backgroundColor: _T.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      ref.invalidate(tripsListProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo actualizar el viaje'),
          backgroundColor: _T.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actingTripId = null);
    }
  }
}

// ==================== TRIP CARD (STAGGERED ANIMATION) ====================

class _TripCardPremium extends StatelessWidget {
  final TripData trip;
  final int index;
  final bool isActing;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _TripCardPremium({
    required this.trip,
    required this.index,
    required this.isActing,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig(trip.status);
    final isActive =
        trip.status == TripStatus.inProgress ||
        trip.status == TripStatus.paused;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + (index * 80)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutQuad,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: Semantics(
        container: true,
        label:
            'Viaje ${trip.code}, ${cfg.label}, de ${trip.origin} a ${trip.destination}',
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _T.shadowSm,
            border: Border.all(
              color: isActive
                  ? _T.alpha(cfg.color, 0.25)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(cfg),
                    const SizedBox(height: 16),
                    _buildRouteInfo(),
                    if (trip.progress != null) _buildProgressBar(cfg.color),
                    const SizedBox(height: 14),
                    _buildStats(),
                    if (isActive || trip.status == TripStatus.scheduled)
                      _buildActionButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_StatusCfg cfg) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _T.alpha(cfg.color, 0.08),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: _T.alpha(cfg.color, 0.15)),
            ),
            child: Text(
              trip.code,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: cfg.color,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          _DotStatus(color: cfg.color, label: cfg.label),
          const SizedBox(width: 8),
          Text(
            trip.eta,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _T.primary,
            ),
          ),
        ],
      );

  Widget _buildRouteInfo() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _T.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _T.alpha(_T.success, 0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              Container(
                width: 2,
                height: 28,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: _T.neutralBg,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _T.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ORIGEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _T.neutral,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  trip.origin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _T.primary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'DESTINO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _T.neutral,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  trip.destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _T.primary,
                    letterSpacing: -0.2,
                  ),
                ),
                if (trip.destinationDetail != null)
                  Text(
                    trip.destinationDetail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _T.neutral,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _T.neutralBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${trip.completedStops}/${trip.stops} paradas',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _T.neutral,
              ),
            ),
          ),
        ],
      );

  Widget _buildProgressBar(Color c) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: LinearProgressIndicator(
            value: trip.progress,
            minHeight: 5,
            backgroundColor: _T.neutralBg,
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
      );

  Widget _buildStats() => Row(
        children: [
          _MiniStat(
            icon: Icons.inventory_2_rounded,
            value: '${trip.packages}',
            label: 'Paquetes',
          ),
          Container(
            width: 1,
            height: 20,
            color: _T.neutralBg,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          _MiniStat(
            icon: Icons.route_rounded,
            value: trip.distance,
            label: 'Distancia',
          ),
          Container(
            width: 1,
            height: 20,
            color: _T.neutralBg,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          _MiniStat(
            icon: Icons.local_shipping_rounded,
            value: _shortVehicle(trip.vehicle),
            label: 'Vehículo',
          ),
        ],
      );

  Widget _buildActionButton() => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isActing ? null : onAction,
            icon: isActing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_actionIcon(trip.status), size: 20),
            label: Text(
              _actionLabel(trip.status),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _actionColor(trip.status),
              disabledBackgroundColor: _T.alpha(_actionColor(trip.status), 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );

  String _shortVehicle(String v) => v.split('·').first.trim();

  IconData _actionIcon(TripStatus s) => switch (s) {
    TripStatus.inProgress => Icons.navigation_rounded,
    TripStatus.paused => Icons.play_arrow_rounded,
    TripStatus.scheduled => Icons.play_arrow_rounded,
    _ => Icons.visibility_rounded,
  };

  String _actionLabel(TripStatus s) => switch (s) {
    TripStatus.inProgress => 'Continuar',
    TripStatus.paused => 'Reanudar',
    TripStatus.scheduled => 'Iniciar viaje',
    _ => 'Ver detalle',
  };

  Color _actionColor(TripStatus s) => switch (s) {
    TripStatus.paused => _T.warning,
    _ => _T.primary,
  };
}

// ==================== STATUS CONFIG ====================

class _StatusCfg {
  final String label;
  final Color color;
  const _StatusCfg(this.label, this.color);
}

_StatusCfg _statusConfig(TripStatus s) => switch (s) {
  TripStatus.inProgress => const _StatusCfg('En curso', _T.accent),
  TripStatus.paused => const _StatusCfg('Pausado', _T.warning),
  TripStatus.completed => const _StatusCfg('Completado', _T.success),
  TripStatus.scheduled => const _StatusCfg('Programado', _T.neutral),
};

// ==================== WIDGETS ====================

class _DotStatus extends StatelessWidget {
  final Color color;
  final String label;
  const _DotStatus({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _T.alpha(color, 0.08),
        borderRadius: BorderRadius.circular(50),
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
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: _T.neutral),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _T.primary,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _T.neutral,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onClear,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar por código o destino',
        hintStyle: const TextStyle(color: _T.neutral, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: _T.neutral,
          size: 20,
        ),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _T.accent),
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onChanged;
  final AsyncValue<List<TripData>> async;
  const _FilterPills({
    required this.filter,
    required this.onChanged,
    required this.async,
  });
  @override
  Widget build(BuildContext context) {
    final counts = async.maybeWhen(
      data: (all) => (
        active: all
            .where(
              (t) =>
                  t.status == TripStatus.inProgress ||
                  t.status == TripStatus.paused,
            )
            .length,
        completed: all.where((t) => t.status == TripStatus.completed).length,
        scheduled: all.where((t) => t.status == TripStatus.scheduled).length,
      ),
      orElse: () => (active: 0, completed: 0, scheduled: 0),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Pill(
            label: 'Activos',
            count: counts.active,
            selected: filter == _Filter.active,
            onTap: () => onChanged(_Filter.active),
          ),
          _Pill(
            label: 'Programados',
            count: counts.scheduled,
            selected: filter == _Filter.scheduled,
            onTap: () => onChanged(_Filter.scheduled),
          ),
          _Pill(
            label: 'Completados',
            count: counts.completed,
            selected: filter == _Filter.completed,
            onTap: () => onChanged(_Filter.completed),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _T.primary : Colors.white,
        borderRadius: BorderRadius.circular(50),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _T.neutral,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.2)
                        : _T.neutralBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : _T.neutral,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonList extends StatefulWidget {
  const _SkeletonList();
  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(
              3,
              (i) => _SkeletonCard(shimmer: t, delay: i * 0.15),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double shimmer;
  final double delay;
  const _SkeletonCard({required this.shimmer, required this.delay});

  @override
  Widget build(BuildContext context) {
    final v = ((shimmer + delay) % 1.0);
    final alpha = 0.04 + 0.06 * (1 - (2 * v - 1).abs());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ShimmerBox(w: 70, h: 22, alpha: alpha),
              const Spacer(),
              _ShimmerBox(w: 50, h: 18, alpha: alpha),
            ],
          ),
          const SizedBox(height: 16),
          _ShimmerBox(w: double.infinity, h: 14, alpha: alpha),
          const SizedBox(height: 8),
          _ShimmerBox(w: 200, h: 18, alpha: alpha),
          const SizedBox(height: 16),
          _ShimmerBox(w: double.infinity, h: 5, alpha: alpha),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _ShimmerBox(w: 60, h: 30, alpha: alpha)),
              const SizedBox(width: 12),
              Expanded(child: _ShimmerBox(w: 60, h: 30, alpha: alpha)),
              const SizedBox(width: 12),
              Expanded(child: _ShimmerBox(w: 60, h: 30, alpha: alpha)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double w;
  final double h;
  final double alpha;
  const _ShimmerBox({required this.w, required this.h, required this.alpha});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _T.neutral.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final _Filter filter;
  final bool hasQuery;
  const _EmptyView({required this.filter, required this.hasQuery});
  @override
  Widget build(BuildContext context) {
    final icon = switch (filter) {
      _Filter.active => Icons.directions_car_rounded,
      _Filter.completed => Icons.check_circle_outline_rounded,
      _Filter.scheduled => Icons.event_note_rounded,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: _T.shadowSm,
              ),
              child: Icon(icon, color: _T.neutral, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery ? 'Sin resultados' : 'No tienes viajes',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _T.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'Prueba con otro código o destino'
                  : 'Los viajes asignados aparecerán aquí',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _T.neutral,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: _T.neutral),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar tus viajes',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _T.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verifica tu conexión e intenta nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _T.neutral, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: FilledButton.styleFrom(
                backgroundColor: _T.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
