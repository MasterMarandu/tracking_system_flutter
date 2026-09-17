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

/// El dashboard es una máquina de estados: TODO lo visible se deriva del
/// `tripState`. Regla de oro (evita el bug de "pantalla en ruta con dato
/// pre-viaje"): si el estado es preTrip, la UI NO habla de "en camino", ni de
/// "llegada estimada", ni de distancia GPS, ni de "iniciar entrega".
class DashboardActiveBody extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripStateProvider);
    // ¿El viaje ya arrancó? Solo entonces la UI puede hablar de distancia/ETA GPS
    // y de "próxima parada". En preTrip/paused/completed no hay tracking en vivo.
    final enRuta = tripState == TripState.inRoute ||
        tripState == TripState.geofenceEntry ||
        tripState == TripState.delivering;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Card única del viaje: en preTrip muestra origen→destino + gate;
          // en ruta muta a "próxima parada" con métricas reales.
          SliverToBoxAdapter(
            child: _TripCard(
              tripData: tripData,
              tripState: tripState,
              enRuta: enRuta,
              isChecklistComplete: isChecklistComplete,
            ),
          ),
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

/// Card del viaje. Una sola instancia que cambia según el estado — nunca dos
/// cards repitiendo el mismo destino.
class _TripCard extends StatelessWidget {
  final TripData tripData;
  final TripState tripState;
  final bool enRuta;
  final bool isChecklistComplete;

  const _TripCard({
    required this.tripData,
    required this.tripState,
    required this.enRuta,
    required this.isChecklistComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera de marca: degradado + código + conteo de paradas.
            // (Sin foto stock: no aporta dato operativo y baja contraste.)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    tripData.tripCode.isNotEmpty
                        ? tripData.tripCode
                        : 'Viaje activo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${tripData.stopsProgress}/${tripData.totalStops} ${tripData.totalStops == 1 ? 'parada' : 'paradas'}',
                      style: const TextStyle(
                        color: AppColors.textPrimaryLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: enRuta
                  ? _EnRutaBody(tripData: tripData, tripState: tripState)
                  : _PreViajeBody(
                      tripData: tripData,
                      isChecklistComplete: isChecklistComplete,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PRE-VIAJE: origen (punto 0 · SALIDA) → destino (ENTREGA), sin km/ETA GPS
/// (el viaje no arrancó), y el gate de "antes de salir" (checklist → iniciar).
class _PreViajeBody extends StatelessWidget {
  final TripData tripData;
  final bool isChecklistComplete;

  const _PreViajeBody({
    required this.tripData,
    required this.isChecklistComplete,
  });

  @override
  Widget build(BuildContext context) {
    final origin =
        tripData.originName.isNotEmpty ? tripData.originName : 'Origen';
    final dest = tripData.destinationName.isNotEmpty
        ? tripData.destinationName
        : (tripData.nextStopName.isNotEmpty ? tripData.nextStopName : 'Destino');
    final salidaProg =
        tripData.departureTime.isNotEmpty ? tripData.departureTime : null;

    if (tripData.totalStops == 0) {
      return _EmptyStopsNotice();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline origen → destino (nodo de salida + nodo de entrega).
        _TimelineNode(
          leading: _RingNode(color: AppColors.primary),
          badge: 'SALIDA',
          badgeColor: AppColors.textSecondaryLight,
          name: origin,
          subtitle: salidaProg != null ? 'Salida prog. $salidaProg' : 'Punto de salida',
          showConnector: true,
        ),
        _TimelineNode(
          leading: _DotNode(color: AppColors.error),
          badge: 'ENTREGA',
          badgeColor: AppColors.primary,
          name: dest,
          subtitle: [
            if (tripData.nextStopAddress.isNotEmpty) tripData.nextStopAddress,
            if (tripData.packages > 0)
              '${tripData.packages} paquete${tripData.packages == 1 ? '' : 's'}',
          ].join(' · '),
          showConnector: false,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.line),
        const SizedBox(height: 14),
        // Gate: qué falta antes de salir. Sin stepper de parada (aún no arrancó).
        const Text(
          'ANTES DE SALIR',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSubtleLight,
          ),
        ),
        const SizedBox(height: 10),
        _GateRow(
          index: 1,
          label: 'Checklist del vehículo',
          status: isChecklistComplete ? 'Completado' : 'Pendiente',
          done: isChecklistComplete,
        ),
        const SizedBox(height: 8),
        _GateRow(
          index: 2,
          label: 'Iniciar viaje',
          status: isChecklistComplete ? 'Listo' : 'Bloqueado',
          done: false,
          blocked: !isChecklistComplete,
        ),
      ],
    );
  }
}

/// EN RUTA: próxima parada con distancia/ETA reales + stepper de 4 pasos.
class _EnRutaBody extends StatelessWidget {
  final TripData tripData;
  final TripState tripState;

  const _EnRutaBody({required this.tripData, required this.tripState});

  @override
  Widget build(BuildContext context) {
    final a = tripData.etaArrivalTime;
    final arrivalString = a != null
        ? '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final stopName = tripData.nextStopName.isNotEmpty
        ? tripData.nextStopName
        : (tripData.destinationName.isNotEmpty
            ? tripData.destinationName
            : 'Destino');

    // Paso activo del stepper según el estado real.
    final activeStep = tripState == TripState.delivering
        ? 3
        : tripState == TripState.geofenceEntry
            ? 2
            : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
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
            Text(
              '${tripData.stopsProgress + 1} de ${tripData.totalStops}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on, size: 18, color: AppColors.textPrimaryLight),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                stopName,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryLight,
                ),
              ),
            ),
          ],
        ),
        if (tripData.nextStopAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 1),
            child: Text(
              tripData.nextStopAddress,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
        const SizedBox(height: 18),
        // 3 números grandes: distancia · restan · ETA (solo con viaje iniciado).
        Row(
          children: [
            _BigMetric(
              value: tripData.distance != null
                  ? '${tripData.distance!.toStringAsFixed(1)} km'
                  : '—',
              label: 'distancia',
            ),
            _BigMetricDivider(),
            _BigMetric(
              value: tripData.etaMinutes != null ? '${tripData.etaMinutes} min' : '—',
              label: 'restan',
            ),
            _BigMetricDivider(),
            _BigMetric(value: arrivalString, label: 'ETA'),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1, color: AppColors.line),
        const SizedBox(height: 16),
        // Stepper de PARADA (solo en ruta): En camino → Llegada → Entrega → Completado.
        _DeliverySteps(activeStep: activeStep, packages: tripData.packages),
      ],
    );
  }
}

class _EmptyStopsNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
}

/// Nodo del timeline pre-viaje (círculo hueco o punto lleno + badge + textos).
class _TimelineNode extends StatelessWidget {
  final Widget leading;
  final String badge;
  final Color badgeColor;
  final String name;
  final String subtitle;
  final bool showConnector;

  const _TimelineNode({
    required this.leading,
    required this.badge,
    required this.badgeColor,
    required this.name,
    required this.subtitle,
    required this.showConnector,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              leading,
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 16 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryLight,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondaryLight,
                      ),
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

class _RingNode extends StatelessWidget {
  final Color color;
  const _RingNode({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        color: Colors.white,
      ),
    );
  }
}

class _DotNode extends StatelessWidget {
  final Color color;
  const _DotNode({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Fila del gate "antes de salir" (número + label + estado).
class _GateRow extends StatelessWidget {
  final int index;
  final String label;
  final String status;
  final bool done;
  final bool blocked;

  const _GateRow({
    required this.index,
    required this.label,
    required this.status,
    required this.done,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = done
        ? AppColors.success
        : blocked
            ? AppColors.textSubtleLight
            : AppColors.amber;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.success
                : AppColors.primary.withValues(alpha: 0.10),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: blocked
                  ? AppColors.textSubtleLight
                  : AppColors.textPrimaryLight,
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: statusColor,
          ),
        ),
      ],
    );
  }
}

class _BigMetric extends StatelessWidget {
  final String value;
  final String label;
  const _BigMetric({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryLight,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.line);
}

/// Stepper horizontal de los 4 pasos de la parada. `activeStep` es 1-based.
class _DeliverySteps extends StatelessWidget {
  final int activeStep;
  final int packages;
  const _DeliverySteps({required this.activeStep, required this.packages});

  @override
  Widget build(BuildContext context) {
    final labels = ['En camino', 'Llegada', 'Entrega', 'Completado'];
    final details = [
      '',
      '',
      '$packages paquete${packages == 1 ? '' : 's'}',
      '',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: _StepColumn(
              index: i + 1,
              label: labels[i],
              detail: details[i],
              done: (i + 1) < activeStep,
              active: (i + 1) == activeStep,
            ),
          ),
          if (i < 3)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: 18,
                height: 2,
                color: (i + 1) < activeStep
                    ? AppColors.primary
                    : AppColors.lineStrong,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepColumn extends StatelessWidget {
  final int index;
  final String label;
  final String detail;
  final bool done;
  final bool active;
  const _StepColumn({
    required this.index,
    required this.label,
    required this.detail,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final on = done || active;
    final color = on ? AppColors.primary : AppColors.lineStrong;
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.primary : AppColors.textSubtleLight,
          ),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSubtleLight,
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: PrimaryActionButton(
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
            ref.read(tripStateProvider.notifier).setState(TripState.inRoute);
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
        onPause: () =>
            ref.read(tripStateProvider.notifier).setState(TripState.paused),
        onResume: () =>
            ref.read(tripStateProvider.notifier).setState(TripState.inRoute),
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

/// "Resumen del día": entregas del viaje actual. Un solo denominador
/// (stopsProgress/totalStops), sin gamificación sobre datos contradictorios.
class _DaySummaryCard extends StatelessWidget {
  final TripData tripData;
  const _DaySummaryCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final done = tripData.deliveredCount;
    final total = tripData.totalStops;
    final pending = (total - done).clamp(0, total);
    final ratio = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del día',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Entregas',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryLight,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$done / $total',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: AppColors.line,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  total == 0
                      ? 'Sin paradas en este viaje'
                      : '$done ${done == 1 ? 'completada' : 'completadas'} · $pending pendiente${pending == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
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
