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

bool _needsGpsWarning(GpsSignalQuality quality) {
  return switch (quality) {
    GpsSignalQuality.none ||
    GpsSignalQuality.poor ||
    GpsSignalQuality.weak => true,
    _ => false,
  };
}

// ==================== DESIGN TOKENS ====================

class _T {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static const double rMd = 14;
  static const double rXl = 28;

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
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color neutral = Color(0xFF64748B);
  static const Color bg = Color(0xFFF8FAFC);

  static Color alpha(Color c, double a) => c.withValues(alpha: a);

  static List<BoxShadow> shadowSm = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowLg = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.1),
      blurRadius: 30,
      offset: const Offset(0, 10),
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
  final ValueNotifier<GpsSignalQuality> _gpsQuality =
      ValueNotifier(GpsService.instance.currentSignalQuality);
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pulseAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOutCubic));

    _sub = GpsService.instance.positionStream.listen((p) {
      final s = p.speed * 3.6;
      _speed.value = s.isFinite ? s.clamp(0.0, 250.0).toDouble() : null;
      _gpsQuality.value = GpsService.instance.currentSignalQuality;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _speed.dispose();
    _gpsQuality.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bootstrapProvider);
    final tracking = LocationService.instance.isActive;

    return Scaffold(
      backgroundColor: _T.bg,
      body: async.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(bootstrapProvider),
        ),
        data: (boot) {
          if (boot?.trip == null) return const _NoTripView();
          return ValueListenableBuilder<GpsSignalQuality>(
            valueListenable: _gpsQuality,
            builder: (context, gpsQ, _) {
              return _ActiveView(
                bootstrap: boot!,
                gpsQuality: gpsQ,
                isTracking: tracking,
                speedNotifier: _speed,
                onToggleTraffic: () =>
                    setState(() => _showTraffic = !_showTraffic),
                pulseAnim: _pulseAnim,
              );
            },
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
  final VoidCallback onToggleTraffic;
  final Animation<double> pulseAnim;

  const _ActiveView({
    required this.bootstrap,
    required this.gpsQuality,
    required this.isTracking,
    required this.speedNotifier,
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
          top: topPad + 66,
          left: _T.lg,
          right: _T.lg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: _RouteFloatingCard(trip: bootstrap.trip!)),
              const SizedBox(width: _T.md),
              _MapControls(),
            ],
          ),
        ),

        DraggableScrollableSheet(
          initialChildSize: 0.40,
          minChildSize: 0.18,
          maxChildSize: 0.90,
          snap: true,
          snapSizes: const [0.18, 0.40, 0.90],
          builder: (ctx, ctrl) => _BottomSheet(
            scrollController: ctrl,
            bootstrap: bootstrap,
            speedNotifier: speedNotifier,
            gpsQuality: gpsQuality,
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
    final topPad = MediaQuery.of(context).padding.top;
    final hasGps = gpsQuality != GpsSignalQuality.none;

    // FIX #2: Tracking label distingue GPS sin señal
    final trackingLabel = !isTracking
        ? 'Pausado'
        : !hasGps
            ? 'Sin GPS'
            : 'En vivo';

    final trackingColor = !isTracking
        ? _T.neutral
        : !hasGps
            ? _T.danger
            : _T.accent;

    final trackingIcon = !isTracking
        ? Icons.sensors_off_rounded
        : !hasGps
            ? Icons.sync_problem_rounded
            : Icons.sensors_rounded;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: Colors.white.withValues(alpha: 0.85),
          padding: EdgeInsets.only(
            top: topPad + _T.sm,
            bottom: _T.sm + 2,
            left: _T.lg,
            right: _T.lg,
          ),
          child: Row(
            children: [
              _StatusBadge(
                icon: Icons.gps_fixed_rounded,
                label: _gpsLabel(gpsQuality),
                color: _gpsColor(gpsQuality),
              ),
              const SizedBox(width: _T.sm),
              _StatusBadge(
                icon: trackingIcon,
                label: trackingLabel,
                color: trackingColor,
              ),
              const Spacer(),
              // FIX #3: Batería eliminada — no hay servicio real
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
        color: _T.alpha(color, 0.08),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: _T.alpha(color, 0.15), width: 1),
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
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.2,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.all(_T.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_T.rMd),
          boxShadow: _T.shadowSm,
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 8, color: _T.success),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: _T.neutral.withValues(alpha: 0.2),
                    ),
                  ),
                  const Icon(Icons.circle, size: 8, color: _T.danger),
                ],
              ),
              const SizedBox(width: _T.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TimeDetail(
                      label: 'Salida',
                      time: _formatClock(trip.departureTime),
                    ),
                    const SizedBox(height: _T.sm + 2),
                    _TimeDetail(
                      label: 'Llegada est.',
                      time: _formatClock(trip.estimatedArrival),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeDetail extends StatelessWidget {
  final String label;
  final String time;

  const _TimeDetail({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: _T.fCaption,
            fontWeight: FontWeight.w800,
            color: _T.neutral,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          time,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: _T.primary,
          ),
        ),
      ],
    );
  }
}

// ==================== MAP CONTROLS ====================

class _MapControls extends StatelessWidget {
  const _MapControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Mi ubicación',
          child: _MapCircleButton(icon: Icons.my_location_rounded, onTap: null),
        ),
        const SizedBox(height: _T.sm),
        // FIX #6: Traffic deshabilitado hasta integrar mapa real
        Tooltip(
          message: 'Disponible al integrar mapa',
          child: _MapCircleButton(
            icon: Icons.traffic_rounded,
            isActive: false,
            onTap: null,
          ),
        ),
        const SizedBox(height: _T.sm),
        Tooltip(
          message: 'Capas del mapa',
          child: _MapCircleButton(icon: Icons.layers_rounded, onTap: null),
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

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: _T.shadowSm,
        ),
        child: Material(
          color: isActive ? _T.accent : Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                color: isActive ? Colors.white : _T.primary,
                size: 20,
              ),
            ),
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
      color: const Color(0xFFF1F5F9),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _VectorMapPainter())),

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
                        width: 90 * v,
                        height: 90 * v,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _T.accent.withValues(alpha: 0.15 * (1 - v)),
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
                              color: _T.accent.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
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
                  vertical: _T.xs + 1,
                ),
                decoration: BoxDecoration(
                  color: _T.primary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  'Ubicación simulada — mapa en desarrollo',
                  style: TextStyle(
                    fontSize: _T.fCaption,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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

class _VectorMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final parkPaint = Paint()..color = const Color(0xFFE2F0D9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.1, size.height * 0.2, 120, 150),
        const Radius.circular(20),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.6, size.height * 0.5, 200, 100),
        const Radius.circular(20),
      ),
      parkPaint,
    );

    final riverPaint = Paint()
      ..color = const Color(0xFFD4E6F1)
      ..strokeWidth = 32
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      Path()
        ..moveTo(-50, size.height * 0.8)
        ..cubicTo(
          size.width * 0.3,
          size.height * 0.75,
          size.width * 0.5,
          size.height * 0.95,
          size.width + 50,
          size.height * 0.9,
        ),
      riverPaint,
    );

    final streetPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(0, size.height * 0.15 * i),
        Offset(size.width, size.height * 0.15 * i),
        streetPaint,
      );
    }
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(size.width * 0.25 * i, 0),
        Offset(size.width * 0.25 * i, size.height),
        streetPaint,
      );
    }

    final hwShadow = Paint()
      ..color = _T.accent.withValues(alpha: 0.1)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final hw = Paint()
      ..color = _T.accent.withValues(alpha: 0.45)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final hwPath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.35)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.25,
        size.width * 0.5,
        size.height * 0.45,
        size.width * 0.78,
        size.height * 0.38,
      );

    canvas.drawPath(hwPath, hwShadow);
    canvas.drawPath(hwPath, hw);

    _drawMarker(
      canvas,
      Offset(size.width * 0.15, size.height * 0.35),
      _T.success,
    );
    _drawMarker(
      canvas,
      Offset(size.width * 0.78, size.height * 0.38),
      _T.danger,
    );
  }

  void _drawMarker(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      15,
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawCircle(center, 7, Paint()..color = color);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== BOTTOM SHEET ====================

class _BottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final DriverBootstrap bootstrap;
  final ValueNotifier<double?> speedNotifier;
  final GpsSignalQuality gpsQuality;

  const _BottomSheet({
    required this.scrollController,
    required this.bootstrap,
    required this.speedNotifier,
    required this.gpsQuality,
  });

  @override
  Widget build(BuildContext context) {
    final currentStop = bootstrap.currentStop;
    final trip = bootstrap.trip!;
    final botPad = MediaQuery.of(context).padding.bottom;
    final showGpsWarning = _needsGpsWarning(gpsQuality);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(_T.rXl)),
        boxShadow: _T.shadowLg,
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          left: _T.lg,
          right: _T.lg,
          top: _T.sm,
          bottom: botPad + 72 + _T.xxl,
        ),
        children: [
          const _Handle(),

          // FIX #4: GPS alert para poor/weak también
          if (showGpsWarning) ...[
            _GpsAlert(quality: gpsQuality),
            const SizedBox(height: _T.md),
          ],

          _NextStopHero(currentStop: currentStop, trip: trip),

          const SizedBox(height: _T.lg),
          _MetricsGrid(
            speedNotifier: speedNotifier,
            currentStop: currentStop,
            hasGps: gpsQuality != GpsSignalQuality.none,
          ),

          if (currentStop?.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: _T.lg),
            _CustomerCard(customerName: currentStop!.customerName!),
          ],

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
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        decoration: BoxDecoration(
          color: _T.neutral.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

// ==================== GPS ALERT ====================

class _GpsAlert extends StatelessWidget {
  final GpsSignalQuality quality;
  const _GpsAlert({required this.quality});

  @override
  Widget build(BuildContext context) {
    final isNone = quality == GpsSignalQuality.none;

    return Container(
      padding: const EdgeInsets.all(_T.md),
      decoration: BoxDecoration(
        color: _T.alpha(_T.danger, 0.08),
        borderRadius: BorderRadius.circular(_T.rMd),
        border: Border.all(color: _T.alpha(_T.danger, 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            isNone ? Icons.gps_off_rounded : Icons.gps_not_fixed_rounded,
            color: _T.danger,
            size: 18,
          ),
          const SizedBox(width: _T.sm),
          Expanded(
            child: Text(
              isNone
                  ? 'Sin señal GPS — ubicación actual no disponible'
                  : 'Señal GPS débil — la ubicación puede ser imprecisa',
              style: const TextStyle(
                color: _T.danger,
                fontWeight: FontWeight.w700,
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
  final BootstrapTrip trip;

  const _NextStopHero({required this.currentStop, required this.trip});

  @override
  Widget build(BuildContext context) {
    if (currentStop == null) {
      return Container(
        padding: const EdgeInsets.all(_T.lg),
        decoration: BoxDecoration(
          color: _T.alpha(_T.success, 0.08),
          borderRadius: BorderRadius.circular(_T.rMd),
          border: Border.all(color: _T.alpha(_T.success, 0.15)),
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
                    '¡Todas las paradas completas!',
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

    final total = trip.totalStops ?? 0;
    final done = trip.stopsProgress ?? 0;
    final name =
        currentStop!.name.isNotEmpty ? currentStop!.name : 'Sin nombre';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _NextStopBadge(),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _T.alpha(_T.neutral, 0.06),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                '$done de $total',
                style: const TextStyle(
                  fontSize: _T.fCaption,
                  fontWeight: FontWeight.w800,
                  color: _T.neutral,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: _T.md),
        Text(
          name,
          style: const TextStyle(
            fontSize: _T.fHeadline,
            fontWeight: FontWeight.w900,
            color: _T.primary,
            letterSpacing: -0.5,
          ),
        ),
        if (currentStop!.address.isNotEmpty) ...[
          const SizedBox(height: _T.xs),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: _T.neutral,
              ),
              const SizedBox(width: _T.xs),
              Expanded(
                child: Text(
                  currentStop!.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: _T.fBody,
                    color: _T.neutral,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: _T.md),
        _ProgressBar(done: done, total: total),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    // FIX #1: clamp().toDouble()
    final double progress =
        total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Progreso del viaje',
              style: TextStyle(
                fontSize: _T.fCaption,
                fontWeight: FontWeight.w700,
                color: _T.neutral,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: _T.fCaption,
                fontWeight: FontWeight.w900,
                color: _T.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: _T.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: _T.alpha(_T.neutral, 0.1),
            valueColor: const AlwaysStoppedAnimation(_T.accent),
          ),
        ),
      ],
    );
  }
}

class _NextStopBadge extends StatelessWidget {
  const _NextStopBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _T.warningLight,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation_rounded, size: 12, color: _T.warning),
          const SizedBox(width: 4),
          Text(
            'PRÓXIMA PARADA',
            style: TextStyle(
              fontSize: _T.fCaption,
              fontWeight: FontWeight.w900,
              color: _T.warning,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== METRICS GRID ====================

class _MetricsGrid extends StatelessWidget {
  final ValueNotifier<double?> speedNotifier;
  final BootstrapCurrentStop? currentStop;
  final bool hasGps;

  const _MetricsGrid({
    required this.speedNotifier,
    required this.currentStop,
    required this.hasGps,
  });

  @override
  Widget build(BuildContext context) {
    final hasEta = currentStop?.etaMinutes != null;
    final hasDist = currentStop?.distanceKm != null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: ValueListenableBuilder<double?>(
              valueListenable: speedNotifier,
              builder: (context, spd, _) {
                final noData = !hasGps || spd == null;
                return _MetricCard(
                  label: 'Velocidad',
                  value: noData ? '--' : spd.toStringAsFixed(0),
                  unit: noData ? '' : 'km/h',
                  icon: Icons.speed_rounded,
                  isPrimary: true,
                  muted: noData,
                );
              },
            ),
          ),
          const SizedBox(width: _T.sm),
          Expanded(
            child: _MetricCard(
              label: 'ETA',
              value: hasEta ? '${currentStop!.etaMinutes}' : '--',
              unit: hasEta ? 'min' : '',
              icon: Icons.timer_outlined,
              muted: !hasEta,
            ),
          ),
          const SizedBox(width: _T.sm),
          Expanded(
            child: _MetricCard(
              label: 'Distancia',
              value: hasDist ? currentStop!.distanceKm!.toStringAsFixed(1) : '--',
              unit: hasDist ? 'km' : '',
              icon: Icons.map_outlined,
              muted: !hasDist,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool isPrimary;
  final bool muted;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.isPrimary = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? _T.neutral
        : isPrimary
            ? _T.accent
            : _T.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _T.sm, vertical: _T.md),
      decoration: BoxDecoration(
        color: muted
            ? _T.alpha(_T.neutral, 0.05)
            : isPrimary
                ? _T.alpha(_T.accent, 0.05)
                : _T.alpha(_T.neutral, 0.05),
        borderRadius: BorderRadius.circular(_T.rMd),
        border: Border.all(
          color: isPrimary && !muted
              ? _T.alpha(_T.accent, 0.2)
              : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: _T.alpha(color, 0.65)),
          const SizedBox(height: _T.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isPrimary ? 26 : 19,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      unit,
                      style: TextStyle(
                        fontSize: _T.fCaption,
                        fontWeight: FontWeight.w700,
                        color: _T.alpha(color, 0.65),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // FIX #5: Label siempre visible
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _T.fCaption,
              fontWeight: FontWeight.w700,
              color: _T.alpha(color, 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== CUSTOMER CARD ====================

class _CustomerCard extends StatelessWidget {
  final String customerName;

  const _CustomerCard({required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.md),
      decoration: BoxDecoration(
        color: _T.alpha(_T.neutral, 0.04),
        borderRadius: BorderRadius.circular(_T.rMd),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _T.alpha(_T.accent, 0.1),
            child: Text(
              customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: _T.fTitle,
                fontWeight: FontWeight.w900,
                color: _T.accent,
              ),
            ),
          ),
          const SizedBox(width: _T.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: _T.fBodyLg,
                    fontWeight: FontWeight.w700,
                    color: _T.primary,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Cliente asignado',
                  style: TextStyle(
                    fontSize: _T.fCaption,
                    color: _T.neutral,
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: 0.45,
            child: IconButton(
              onPressed: null,
              icon: const Icon(Icons.call_rounded, color: _T.success),
              style: IconButton.styleFrom(
                backgroundColor: _T.alpha(_T.success, 0.1),
              ),
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
    if (currentStop == null) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: 'Próximamente',
                child: _SecondaryButton(
                  icon: Icons.qr_code_scanner,
                  label: 'Escanear',
                  onTap: null,
                ),
              ),
            ),
            const SizedBox(width: _T.sm),
            Expanded(
              child: Tooltip(
                message: 'Próximamente',
                child: _SecondaryButton(
                  icon: Icons.navigation_rounded,
                  label: 'Navegar',
                  onTap: null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: _T.md),
        // FIX #8: Confirmar deshabilitado sin backend
        SizedBox(
          width: double.infinity,
          height: 52,
          child: _PrimaryButton(
            label: 'Confirmar llegada',
            onTap: null,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.check_circle_rounded),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _T.success,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _T.alpha(_T.success, 0.35),
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_T.rMd),
        ),
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
      child: SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: _T.primary,
            side: const BorderSide(color: Colors.black12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_T.rMd),
            ),
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
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

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
            // FIX #10: Mensaje amigable, no técnico
            const Text(
              'No pudimos cargar la información del viaje. '
              'Verifica tu conexión e inténtalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _T.fBody,
                color: _T.neutral,
                height: 1.4,
              ),
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
