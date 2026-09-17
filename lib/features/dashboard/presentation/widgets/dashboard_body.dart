import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/theme/app_colors.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/common_widgets.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/primary_action_button.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/checklist_sheet.dart';
import 'package:tracking_system_app/features/dashboard/providers/trip_state_provider.dart';

class DashboardActiveBody extends StatelessWidget {
  final TripData tripData;
  final List<ChecklistItem> checklistItems;
  final DeliveryStep deliveryStep;
  final bool isChecklistComplete;
  final DriverBootstrap? bootstrap;

  final VoidCallback onNavigate;
  final VoidCallback onArriveManually;
  final VoidCallback onStartDelivery;
  final VoidCallback onContinueDelivery;
  final VoidCallback onRefresh;
  final ValueChanged<List<ChecklistItem>> onChecklistChanged;

  const DashboardActiveBody({
    super.key,
    required this.tripData,
    required this.checklistItems,
    required this.deliveryStep,
    required this.isChecklistComplete,
    required this.bootstrap,
    required this.onNavigate,
    required this.onArriveManually,
    required this.onStartDelivery,
    required this.onContinueDelivery,
    required this.onRefresh,
    required this.onChecklistChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Card principal del viaje: banner de carretera + itinerario + métricas.
          SliverToBoxAdapter(child: _TripHeroCard(tripData: tripData)),
          // Próxima parada (destacada) — solo si hay parada activa.
          if (tripData.nextStopName.isNotEmpty)
            SliverToBoxAdapter(child: _NextStopCard(tripData: tripData)),
          SliverToBoxAdapter(
            child: _PrimaryActionSection(
              tripData: tripData,
              deliveryStep: deliveryStep,
              isChecklistComplete: isChecklistComplete,
              checklistItems: checklistItems,
              onNavigate: onNavigate,
              onArriveManually: onArriveManually,
              onStartDelivery: onStartDelivery,
              onContinueDelivery: onContinueDelivery,
              onChecklistChanged: onChecklistChanged,
            ),
          ),
          SliverToBoxAdapter(child: _QuickActionsSection()),
          SliverToBoxAdapter(child: _DaySummaryCard(tripData: tripData)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Card principal: banner de carretera con código + conteo de paradas, y debajo
/// el itinerario (timeline origen → destino) con la fila de métricas.
class _TripHeroCard extends StatelessWidget {
  final TripData tripData;
  const _TripHeroCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final a = tripData.etaArrivalTime;
    final arrivalString = a != null
        ? '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Banner: carretera pintada + chip código + conteo paradas ──
            SizedBox(
              height: 132,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _RoadBanner(),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CodeChip(
                          code: tripData.tripCode.isNotEmpty
                              ? tripData.tripCode
                              : 'Viaje activo',
                        ),
                        const Spacer(),
                        _StopsPill(
                          progress: tripData.stopsProgress,
                          total: tripData.totalStops,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Itinerario: timeline origen → destino ──
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              child: _Itinerary(tripData: tripData),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.line),
            // ── Fila de métricas ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Row(
                children: [
                  _Metric(
                    icon: Icons.route,
                    value: tripData.distance != null
                        ? '${tripData.distance!.toStringAsFixed(1)} km'
                        : '—',
                    label: 'Distancia',
                  ),
                  _Metric(
                    icon: Icons.schedule,
                    value: tripData.etaMinutes != null
                        ? '${tripData.etaMinutes} min'
                        : '—',
                    label: 'Tiempo est.',
                  ),
                  _Metric(
                    icon: Icons.access_time,
                    value: arrivalString,
                    label: 'Llegada est.',
                  ),
                  _Metric(
                    icon: Icons.inventory_2_outlined,
                    value: '${tripData.packages}',
                    label: 'Paquetes',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip del código de viaje sobre el banner (con icono de camión).
class _CodeChip extends StatelessWidget {
  final String code;
  const _CodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastilla "N/M paradas" sobre el banner.
class _StopsPill extends StatelessWidget {
  final int progress;
  final int total;
  const _StopsPill({required this.progress, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        '$progress / $total paradas',
        style: const TextStyle(
          color: AppColors.textPrimaryLight,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Itinerario tipo timeline: origen (nodo 1) → destino (nodo 2), con línea
/// conectora, estados, ETA y distancia. Con los datos actuales son 2 nodos
/// (origen + destino); la parada actual se resalta en "Próxima parada".
class _Itinerary extends StatelessWidget {
  final TripData tripData;
  const _Itinerary({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final a = tripData.etaArrivalTime;
    final arrivalString = a != null
        ? '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final origin =
        tripData.originName.isNotEmpty ? tripData.originName : 'Origen';
    final dest = tripData.destinationName.isNotEmpty
        ? tripData.destinationName
        : (tripData.nextStopName.isNotEmpty
            ? tripData.nextStopName
            : 'Destino');

    if (tripData.totalStops == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.amberLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Este viaje no tiene paradas configuradas.',
                style: TextStyle(color: AppColors.amber, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _ItineraryNode(
          index: 1,
          badge: 'EN CAMINO',
          badgeColor: AppColors.primary,
          name: origin,
          subtitle: 'Punto de salida',
          etaLabel: 'Salida',
          etaValue: tripData.departureTime.isNotEmpty
              ? tripData.departureTime
              : '—',
          etaSub: tripData.etaMinutes != null
              ? '${tripData.etaMinutes} min'
              : null,
          trailingChip: tripData.distance != null
              ? '${tripData.distance!.toStringAsFixed(1)} km'
              : null,
          trailingIcon: Icons.near_me,
          showConnector: true,
          done: tripData.stopsProgress > 0,
        ),
        _ItineraryNode(
          index: 2,
          badge: 'SIGUIENTE',
          badgeColor: AppColors.textSecondaryLight,
          name: dest,
          subtitle: tripData.nextStopAddress.isNotEmpty
              ? tripData.nextStopAddress
              : (tripData.customerName.isNotEmpty
                  ? tripData.customerName
                  : 'Entrega'),
          etaLabel: 'Llegada est.',
          etaValue: arrivalString,
          etaSub: null,
          trailingChip: tripData.packages > 0
              ? '${tripData.packages} paquete${tripData.packages == 1 ? '' : 's'}'
              : null,
          trailingIcon: Icons.inventory_2_outlined,
          showConnector: false,
          done: false,
        ),
      ],
    );
  }
}

/// Un nodo del timeline: círculo numerado + línea conectora, con badge,
/// nombre/subtítulo, chip de carga y bloque de ETA a la derecha.
class _ItineraryNode extends StatelessWidget {
  final int index;
  final String badge;
  final Color badgeColor;
  final String name;
  final String subtitle;
  final String etaLabel;
  final String etaValue;
  final String? etaSub;
  final String? trailingChip;
  final IconData trailingIcon;
  final bool showConnector;
  final bool done;

  const _ItineraryNode({
    required this.index,
    required this.badge,
    required this.badgeColor,
    required this.name,
    required this.subtitle,
    required this.etaLabel,
    required this.etaValue,
    required this.etaSub,
    required this.trailingChip,
    required this.trailingIcon,
    required this.showConnector,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final nodeColor = badge == 'EN CAMINO' ? AppColors.primary : AppColors.lineStrong;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Columna del timeline: círculo + conector.
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Contenido central.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 18 : 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 9.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      if (trailingChip != null) ...[
                        const SizedBox(width: 8),
                        Icon(trailingIcon, size: 13, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            trailingChip!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 15, color: AppColors.textPrimaryLight),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18, top: 1),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Bloque ETA a la derecha.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                etaLabel,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSubtleLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                etaValue,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              if (etaSub != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule,
                        size: 11, color: AppColors.textSubtleLight),
                    const SizedBox(width: 3),
                    Text(
                      etaSub!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSubtleLight,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right,
              size: 18, color: AppColors.textSubtleLight),
        ],
      ),
    );
  }
}

/// Métrica individual de la fila inferior (icono en círculo + valor + label).
class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Metric({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryLight,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo pintado que evoca una carretera al atardecer (sin depender de assets).
class _RoadBanner extends StatelessWidget {
  const _RoadBanner();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RoadPainter());
  }
}

class _RoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cielo (verde de marca → tono cálido hacia el horizonte).
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.primaryDark, AppColors.primaryLight],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sky);

    // Halo del sol cerca del horizonte.
    final sun = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE9B0).withValues(alpha: 0.75),
          const Color(0xFFFFE9B0).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(w * 0.72, h * 0.42), radius: h * 0.55));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sun);

    // Campo (parte inferior, verde más oscuro).
    final fieldPath = Path()
      ..moveTo(0, h * 0.62)
      ..lineTo(w, h * 0.55)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final field = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2E5E4E), Color(0xFF16382E)],
      ).createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.45));
    canvas.drawPath(fieldPath, field);

    // Carretera en perspectiva (trapecio que converge al horizonte).
    final roadPath = Path()
      ..moveTo(w * 0.44, h * 0.58)
      ..lineTo(w * 0.56, h * 0.58)
      ..lineTo(w * 0.82, h)
      ..lineTo(w * 0.18, h)
      ..close();
    canvas.drawPath(roadPath, Paint()..color = const Color(0xFF2B2F33));

    // Línea central discontinua.
    final dash = Paint()
      ..color = const Color(0xFFF4D06A)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final t0 = 0.62 + i * 0.11;
      final t1 = t0 + 0.05;
      if (t1 > 1) break;
      dash.strokeWidth = 1.5 + i * 1.6;
      canvas.drawLine(
        Offset(w * 0.5, h * t0),
        Offset(w * 0.5, h * t1),
        dash,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NextStopCard extends StatelessWidget {
  final TripData tripData;
  const _NextStopCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final a = tripData.etaArrivalTime;
    final arrivalString = a != null
        ? '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.near_me, size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'PRÓXIMA PARADA',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on,
                            size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          tripData.distance != null
                              ? '${tripData.distance!.toStringAsFixed(1)} km'
                              : '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tripData.nextStopName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              if (tripData.nextStopAddress.isNotEmpty)
                Text(
                  tripData.nextStopAddress,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              const SizedBox(height: 16),
              // Mini-stepper de la entrega: En camino → Llegada → Entrega → Completado.
              _DeliverySteps(
                arrivalString: arrivalString,
                etaMinutes: tripData.etaMinutes,
                packages: tripData.packages,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini stepper horizontal de los 4 pasos de la entrega.
class _DeliverySteps extends StatelessWidget {
  final String arrivalString;
  final int? etaMinutes;
  final int packages;
  const _DeliverySteps({
    required this.arrivalString,
    required this.etaMinutes,
    required this.packages,
  });

  @override
  Widget build(BuildContext context) {
    final steps = <_StepData>[
      _StepData(
        index: 1,
        label: 'En camino',
        detail: etaMinutes != null ? '$etaMinutes min' : '—',
        icon: Icons.local_shipping,
        active: true,
      ),
      _StepData(
        index: 2,
        label: 'Llegada',
        detail: arrivalString,
        icon: Icons.location_on,
        active: false,
      ),
      _StepData(
        index: 3,
        label: 'Entrega',
        detail: '$packages paquete${packages == 1 ? '' : 's'}',
        icon: Icons.inventory_2_outlined,
        active: false,
      ),
      _StepData(
        index: 4,
        label: 'Completado',
        detail: '',
        icon: Icons.check_circle,
        active: false,
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(child: _StepColumn(step: steps[i])),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: 20,
                height: 2,
                color: AppColors.lineStrong,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepData {
  final int index;
  final String label;
  final String detail;
  final IconData icon;
  final bool active;
  const _StepData({
    required this.index,
    required this.label,
    required this.detail,
    required this.icon,
    required this.active,
  });
}

class _StepColumn extends StatelessWidget {
  final _StepData step;
  const _StepColumn({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = step.active ? AppColors.primary : AppColors.lineStrong;
    final labelColor =
        step.active ? AppColors.primary : AppColors.textSubtleLight;
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            '${step.index}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        if (step.detail.isNotEmpty)
          Text(
            step.detail,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSubtleLight,
            ),
          )
        else
          Icon(step.icon, size: 13, color: AppColors.lineStrong),
      ],
    );
  }
}

class _PrimaryActionSection extends ConsumerWidget {
  final TripData tripData;
  final DeliveryStep deliveryStep;
  final bool isChecklistComplete;
  final List<ChecklistItem> checklistItems;
  final VoidCallback onNavigate;
  final VoidCallback onArriveManually;
  final VoidCallback onStartDelivery;
  final VoidCallback onContinueDelivery;
  final ValueChanged<List<ChecklistItem>> onChecklistChanged;

  const _PrimaryActionSection({
    required this.tripData,
    required this.deliveryStep,
    required this.isChecklistComplete,
    required this.checklistItems,
    required this.onNavigate,
    required this.onArriveManually,
    required this.onStartDelivery,
    required this.onContinueDelivery,
    required this.onChecklistChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tripState = ref.watch(tripStateProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        children: [
          PrimaryActionButton(
            tripState: tripState,
            deliveryStep: deliveryStep,
            theme: theme,
            canStartTrip: isChecklistComplete,
            totalStops: tripData.totalStops,
            onPreTripChecklist: () => showChecklistSheet(
              context,
              items: checklistItems,
              onChanged: onChecklistChanged,
            ),
            onStartTrip: () {
              if (isChecklistComplete) {
                ref
                    .read(tripStateProvider.notifier)
                    .setState(TripState.inRoute);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Completa el checklist antes de iniciar'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onNavigate: onNavigate,
            onArriveManually: onArriveManually,
            onStartDelivery: onStartDelivery,
            onContinueDelivery: onContinueDelivery,
            onPause: () => ref
                .read(tripStateProvider.notifier)
                .setState(TripState.paused),
            onResume: () => ref
                .read(tripStateProvider.notifier)
                .setState(TripState.inRoute),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sigue los pasos para completar el viaje',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsSection extends ConsumerWidget {
  const _QuickActionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripStateProvider);
    final actions = _getContextualActions(tripState);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final itemWidth = (constraints.maxWidth - (spacing * 3)) / 4;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: actions
                .map((a) => SizedBox(
                      width: itemWidth,
                      child: QuickAction(
                          icon: a.icon,
                          label: a.label,
                          color: a.color,
                          onTap: a.onTap),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  List<ActionDef> _getContextualActions(TripState tripState) {
    switch (tripState) {
      case TripState.noTrip:
        return [ActionDef(Icons.info_outline, 'Info', Colors.blue, () {})];
      case TripState.preTrip:
        return [
          ActionDef(Icons.report_outlined, 'Incidencia', AppColors.accent, () {}),
        ];
      case TripState.inRoute:
      case TripState.geofenceEntry:
        return [
          ActionDef(Icons.qr_code_scanner, 'Escanear', AppColors.primary, () {}),
          ActionDef(Icons.report_outlined, 'Incidencia', AppColors.accent, () {}),
        ];
      case TripState.delivering:
        return [
          ActionDef(Icons.qr_code_scanner, 'Escanear', AppColors.primary, () {}),
          ActionDef(Icons.camera_alt, 'Foto', Colors.purple, () {}),
          ActionDef(Icons.report_outlined, 'Incidencia', AppColors.accent, () {}),
        ];
      case TripState.completed:
        return [ActionDef(Icons.summarize, 'Resumen', AppColors.primary, () {})];
      case TripState.paused:
        return [
          ActionDef(Icons.report_outlined, 'Incidencia', AppColors.accent, () {}),
          ActionDef(Icons.restaurant, 'Descanso', Colors.blue, () {}),
        ];
    }
  }
}

/// "Resumen del día" con barra de progreso de entregas y mensaje motivacional.
class _DaySummaryCard extends StatelessWidget {
  final TripData tripData;
  const _DaySummaryCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final done = tripData.deliveredCount;
    final total = tripData.deliveredCount + tripData.pendingCount;
    final pending = tripData.pendingCount;
    final ratio = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

    final now = DateTime.now();
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final dateLabel =
        'Hoy, ${now.day} ${months[now.month - 1]} ${now.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Resumen del día',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tu día',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryLight,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$done / $total entregas',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 9,
                    backgroundColor: AppColors.line,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      '$done ${done == 1 ? 'entrega completada' : 'entregas completadas'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.radio_button_unchecked,
                        size: 15, color: AppColors.textSubtleLight),
                    const SizedBox(width: 6),
                    Text(
                      '$pending pendiente${pending == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
                if (total > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.track_changes,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            done >= total
                                ? '¡Excelente! Completaste todas las entregas.'
                                : '¡Vas bien! $done de $total entregas completadas.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
