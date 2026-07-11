import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tracking_system_app/core/services/gps_service.dart';
import 'package:tracking_system_app/core/services/location_service.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';

// ==================== HELPERS ====================

String _formatClock(String? value) {
  if (value == null) return '--:--';
  final date = DateTime.tryParse(value);
  if (date == null) return '--:--';
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

// ==================== DESIGN TOKENS ====================

class _T {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static const double rMd = 12;
  static const double rXl = 24;

  static const double fCaption = 12;
  static const double fBody = 14;
  static const double fBodyLg = 16;
  static const double fTitle = 18;
  static const double fHeadline = 24;

  static const Color primary = Color(0xFF0F172A);
  static const Color accent = Color(0xFF2563EB);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color neutral = Color(0xFF64748B);
  static const Color bg = Color(0xFFF1F5F9);

  static Color alpha(Color c, double a) => c.withValues(alpha: a);

  static List<BoxShadow> shadow = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.08),
      blurRadius: 15,
      offset: const Offset(0, 4),
    ),
  ];
}

// ==================== SCREEN ====================

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with SingleTickerProviderStateMixin {
  bool _showTraffic = false;
  StreamSubscription? _sub;
  final ValueNotifier<double?> _speed = ValueNotifier(null);
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeOut),
    );

    _sub = GpsService.instance.positionStream.listen((p) {
      final s = p.speed * 3.6;
      _speed.value = s.isFinite ? s.clamp(0, 250) : null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _speed.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bootstrapProvider);
    final gpsQ = GpsService.instance.currentSignalQuality;
    final tracking = LocationService.instance.isActive;

    return Scaffold(
      backgroundColor: _T.bg,
      body: async.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(
          error: e,
          onRetry: () => ref.invalidate(bootstrapProvider),
        ),
        data: (boot) {
          if (boot?.trip == null) return const _NoTripView();
          return _ActiveView(
            bootstrap: boot!,
            gpsQuality: gpsQ,
            isTracking: tracking,
            speedNotifier: _speed,
            showTraffic: _showTraffic,
            onToggleTraffic: () => setState(() => _showTraffic = !_showTraffic),
            pulseAnim: _pulseAnim,
          );
        },
      ),
    );
  }
}

// ==================== ACTIVE VIEW ====================

class _ActiveView extends StatelessWidget {
  final DriverBootstrap bootstrap;
  final GpsSignalQuality gpsQuality;
  final bool isTracking;
  final ValueNotifier<double?> speedNotifier;
  final bool showTraffic;
  final VoidCallback onToggleTraffic;
  final Animation<double> pulseAnim;

  const _ActiveView({
    required this.bootstrap,
    required this.gpsQuality,
    required this.isTracking,
    required this.speedNotifier,
    required this.showTraffic,
    required this.onToggleTraffic,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final hasGps = gpsQuality != GpsSignalQuality.none;
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Positioned.fill(
          child: _MapLayer(hasGps: hasGps, pulseAnim: pulseAnim),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopOverlay(gpsQuality: gpsQuality, isTracking: isTracking),
        ),

        Positioned(
          top: topPad + 70,
          left: _T.lg,
          child: _RouteFloatingCard(trip: bootstrap.trip!),
        ),

        Positioned(
          right: _T.lg,
          top: topPad + 70,
          child: _MapControls(
            showTraffic: showTraffic,
            onToggleTraffic: onToggleTraffic,
          ),
        ),

        DraggableScrollableSheet(
          initialChildSize: 0.38,
          minChildSize: 0.15,
          maxChildSize: 0.9,
          snap: true,
          builder: (ctx, ctrl) => _BottomSheet(
            scrollController: ctrl,
            bootstrap: bootstrap,
            speedNotifier: speedNotifier,
            hasGps: hasGps,
          ),
        ),
      ],
    );
  }
}

// ==================== STATUS BAR (GLASSMORPHISM) ====================

class _TopOverlay extends StatelessWidget {
  final GpsSignalQuality gpsQuality;
  final bool isTracking;

  const _TopOverlay({required this.gpsQuality, required this.isTracking});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.white.withValues(alpha: 0.8),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + _T.sm,
            bottom: _T.sm,
            left: _T.lg,
            right: _T.lg,
          ),
          child: Row(
            children: [
              _StatusBadge(
                icon: Icons.gps_fixed,
                label: _gpsLabel(gpsQuality),
                color: _gpsColor(gpsQuality),
              ),
              const SizedBox(width: _T.sm),
              _StatusBadge(
                icon: isTracking ? Icons.sensors : Icons.sensors_off,
                label: isTracking ? 'En vivo' : 'Pausado',
                color: isTracking ? _T.accent : _T.neutral,
              ),
              const Spacer(),
              _StatusBadge(
                icon: Icons.battery_std_rounded,
                label: '—',
                color: _T.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _gpsLabel(GpsSignalQuality q) => switch (q) {
    GpsSignalQuality.excellent => 'Excelente',
    GpsSignalQuality.good => 'Buena',
    GpsSignalQuality.medium => 'Media',
    GpsSignalQuality.poor => 'Débil',
    GpsSignalQuality.weak => 'Débil',
    GpsSignalQuality.none => 'Sin señal',
  };

  Color _gpsColor(GpsSignalQuality q) => switch (q) {
    GpsSignalQuality.excellent || GpsSignalQuality.good => _T.success,
    GpsSignalQuality.medium => _T.warning,
    _ => _T.danger,
  };
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _T.alpha(color, 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _T.alpha(color, 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: _T.fCaption,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ROUTE FLOATING CARD ====================

class _RouteFloatingCard extends StatelessWidget {
  final BootstrapTrip trip;
  const _RouteFloatingCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_T.rMd),
        boxShadow: _T.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimePoint(
            color: _T.success,
            time: _formatClock(trip.departureTime),
            label: 'Salida',
          ),
          const SizedBox(height: _T.sm),
          _TimePoint(
            color: _T.danger,
            time: _formatClock(trip.estimatedArrival),
            label: 'ETA',
          ),
        ],
      ),
    );
  }
}

class _TimePoint extends StatelessWidget {
  final Color color;
  final String time;
  final String label;

  const _TimePoint({
    required this.color,
    required this.time,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: _T.neutral),
            ),
            Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==================== MAP CONTROLS ====================

class _MapControls extends StatelessWidget {
  final bool showTraffic;
  final VoidCallback onToggleTraffic;

  const _MapControls({
    required this.showTraffic,
    required this.onToggleTraffic,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapCircleButton(icon: Icons.my_location, onTap: null),
        const SizedBox(height: _T.sm),
        _MapCircleButton(
          icon: Icons.traffic,
          isActive: showTraffic,
          onTap: onToggleTraffic,
        ),
      ],
    );
  }
}

class _MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;

  const _MapCircleButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive ? _T.accent : Colors.white,
            shape: BoxShape.circle,
            boxShadow: _T.shadow,
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.white : _T.primary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ==================== MAP LAYER ====================

class _MapLayer extends StatelessWidget {
  final bool hasGps;
  final Animation<double> pulseAnim;

  const _MapLayer({required this.hasGps, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE2E8F0),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MapGridPainter())),

          if (hasGps)
            Center(
              child: AnimatedBuilder(
                animation: pulseAnim,
                builder: (context, _) {
                  final v = pulseAnim.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100 * v,
                        height: 100 * v,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _T.accent.withValues(alpha: 0.2 * (1 - v)),
                        ),
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _T.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: _T.accent.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          Positioned(
            bottom: _T.xxl,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _T.md,
                  vertical: _T.xs,
                ),
                decoration: BoxDecoration(
                  color: _T.alpha(Colors.black, 0.45),
                  borderRadius: BorderRadius.circular(_T.rMd),
                ),
                child: const Text(
                  'Mapa en desarrollo',
                  style: TextStyle(
                    fontSize: _T.fCaption,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== BOTTOM SHEET ====================

class _BottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final DriverBootstrap bootstrap;
  final ValueNotifier<double?> speedNotifier;
  final bool hasGps;

  const _BottomSheet({
    required this.scrollController,
    required this.bootstrap,
    required this.speedNotifier,
    required this.hasGps,
  });

  @override
  Widget build(BuildContext context) {
    final currentStop = bootstrap.currentStop;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(_T.rXl)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          left: _T.lg,
          right: _T.lg,
          top: _T.sm,
          bottom: botPad + _T.xxl,
        ),
        children: [
          const _Handle(),

          if (!hasGps) ...[
            const _GpsAlert(),
            const SizedBox(height: _T.sm),
          ],

          _NextStopHero(currentStop: currentStop),

          const SizedBox(height: _T.lg),
          _MetricsGrid(speedNotifier: speedNotifier, currentStop: currentStop),

          const SizedBox(height: _T.xl),
          _ActionSection(currentStop: currentStop),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

// ==================== GPS ALERT ====================

class _GpsAlert extends StatelessWidget {
  const _GpsAlert();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.md),
      decoration: BoxDecoration(
        color: _T.alpha(_T.danger, 0.1),
        borderRadius: BorderRadius.circular(_T.rMd),
      ),
      child: const Row(
        children: [
          Icon(Icons.gps_off, color: _T.danger, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Señal GPS débil — última posición conocida',
              style: TextStyle(
                color: _T.danger,
                fontWeight: FontWeight.bold,
                fontSize: _T.fBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== NEXT STOP HERO ====================

class _NextStopHero extends StatelessWidget {
  final BootstrapCurrentStop? currentStop;
  const _NextStopHero({required this.currentStop});

  @override
  Widget build(BuildContext context) {
    if (currentStop == null) {
      return Container(
        padding: const EdgeInsets.all(_T.lg),
        decoration: BoxDecoration(
          color: _T.alpha(_T.success, 0.1),
          borderRadius: BorderRadius.circular(_T.rMd),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _T.success, size: 24),
            SizedBox(width: _T.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paradas completadas',
                    style: TextStyle(
                      fontSize: _T.fBodyLg,
                      fontWeight: FontWeight.bold,
                      color: _T.success,
                    ),
                  ),
                  Text(
                    'Dirígete al destino final',
                    style: TextStyle(fontSize: _T.fBody, color: _T.success),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: _T.danger, size: 20),
            const SizedBox(width: _T.sm),
            const Text(
              'PRÓXIMA PARADA',
              style: TextStyle(
                fontSize: _T.fCaption,
                fontWeight: FontWeight.w800,
                color: _T.neutral,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: _T.sm),
        Text(
          currentStop!.name,
          style: const TextStyle(
            fontSize: _T.fHeadline,
            fontWeight: FontWeight.w900,
            color: _T.primary,
          ),
        ),
        if (currentStop!.address.isNotEmpty)
          Text(
            currentStop!.address,
            style: const TextStyle(fontSize: _T.fBody, color: _T.neutral),
          ),
      ],
    );
  }
}

// ==================== METRICS GRID ====================

class _MetricsGrid extends StatelessWidget {
  final ValueNotifier<double?> speedNotifier;
  final BootstrapCurrentStop? currentStop;

  const _MetricsGrid({
    required this.speedNotifier,
    required this.currentStop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ValueListenableBuilder<double?>(
            valueListenable: speedNotifier,
            builder: (context, spd, _) {
              final noData = spd == null;
              return _MetricCard(
                label: 'Velocidad',
                value: noData ? '--' : spd.toStringAsFixed(0),
                unit: noData ? '' : 'km/h',
                icon: Icons.speed,
                isPrimary: true,
              );
            },
          ),
        ),
        const SizedBox(width: _T.sm),
        Expanded(
          child: _MetricCard(
            label: 'ETA',
            value: currentStop?.etaMinutes != null
                ? '${currentStop!.etaMinutes}'
                : '--',
            unit: currentStop?.etaMinutes != null ? 'min' : '',
            icon: Icons.timer,
          ),
        ),
        const SizedBox(width: _T.sm),
        Expanded(
          child: _MetricCard(
            label: 'Dist.',
            value: currentStop?.distanceKm != null
                ? currentStop!.distanceKm!.toStringAsFixed(1)
                : '--',
            unit: currentStop?.distanceKm != null ? 'km' : '',
            icon: Icons.map,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool isPrimary;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPrimary ? _T.accent : _T.primary;

    return Container(
      padding: const EdgeInsets.all(_T.md),
      decoration: BoxDecoration(
        color: isPrimary ? _T.alpha(_T.accent, 0.05) : _T.bg,
        borderRadius: BorderRadius.circular(_T.rMd),
        border: isPrimary
            ? Border.all(color: _T.alpha(_T.accent, 0.2))
            : null,
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: _T.alpha(color, 0.6)),
          const SizedBox(height: _T.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: isPrimary ? 28 : 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                fontSize: 10,
                color: _T.alpha(color, 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== ACTION SECTION ====================

class _ActionSection extends StatelessWidget {
  final BootstrapCurrentStop? currentStop;

  const _ActionSection({required this.currentStop});

  @override
  Widget build(BuildContext context) {
    if (currentStop == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                icon: Icons.qr_code_scanner,
                label: 'Escanear',
                onTap: null,
              ),
            ),
            const SizedBox(width: _T.md),
            Expanded(
              flex: 2,
              child: _PrimaryButton(
                label: 'Confirmar llegada',
                onTap: () => _confirmArrival(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmArrival(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar llegada'),
        content: const Text('¿Confirmás que llegaste al destino?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Llegada confirmada'),
                  backgroundColor: _T.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_T.rMd),
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: _T.success),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _T.success,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_T.rMd),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _T.primary,
          side: const BorderSide(color: Colors.black12),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_T.rMd),
          ),
        ),
      ),
    );
  }
}

// ==================== EMPTY / LOADING / ERROR ====================

class _NoTripView extends StatelessWidget {
  const _NoTripView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_T.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 72, color: _T.neutral),
            const SizedBox(height: _T.lg),
            const Text(
              'No hay viaje activo',
              style: TextStyle(
                fontSize: _T.fTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _T.sm),
            const Text(
              'Iniciá un viaje desde la sección de Viajes\npara ver el tracking en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _T.fBodyLg,
                color: _T.neutral,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
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
        padding: const EdgeInsets.all(_T.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 72,
              color: _T.danger,
            ),
            const SizedBox(height: _T.lg),
            const Text(
              'Error al cargar',
              style: TextStyle(
                fontSize: _T.fTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _T.sm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: _T.fBody, color: _T.neutral),
            ),
            const SizedBox(height: _T.xl),
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
