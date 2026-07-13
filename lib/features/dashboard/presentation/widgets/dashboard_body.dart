import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _Header(tripData: tripData)),
          SliverToBoxAdapter(
              child: _TripSummaryCard(tripData: tripData)),
          if (tripData.nextStopName.isNotEmpty)
            SliverToBoxAdapter(child: _NextStopCard(tripData: tripData)),
          SliverToBoxAdapter(child: _PrimaryActionSection(
            tripData: tripData,
            deliveryStep: deliveryStep,
            isChecklistComplete: isChecklistComplete,
            checklistItems: checklistItems,
            onNavigate: onNavigate,
            onArriveManually: onArriveManually,
            onStartDelivery: onStartDelivery,
            onContinueDelivery: onContinueDelivery,
            onChecklistChanged: onChecklistChanged,
          )),
          SliverToBoxAdapter(
              child: _QuickActionsSection()),
          SliverToBoxAdapter(child: _KPISection(tripData: tripData)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TripData tripData;
  const _Header({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 18 ? 'Buenas tardes' : 'Buenas noches';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              tripData.driverName.isNotEmpty ? tripData.driverName[0] : '?',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(tripData.driverName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  final TripData tripData;
  const _NextStopCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = tripData.etaArrivalTime;
    final arrivalString = a != null
        ? '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppBadge(
                    label: 'PRÓXIMA PARADA',
                    icon: Icons.near_me,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(tripData.nextStopName,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text(tripData.nextStopAddress,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.business,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(tripData.customerName,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9))),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  StopStat(
                      icon: Icons.route,
                      value: tripData.distance != null
                          ? '${tripData.distance!.toStringAsFixed(1)} km'
                          : '—',
                      label: 'Distancia',
                      color: Colors.white),
                  VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  StopStat(
                      icon: Icons.schedule,
                      value: tripData.etaMinutes != null
                          ? '${tripData.etaMinutes} min'
                          : '—',
                      label: 'ETA',
                      color: Colors.white),
                  VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  StopStat(
                      icon: Icons.access_time,
                      value: arrivalString,
                      label: 'Llegada',
                      color: Colors.white),
                  VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  StopStat(
                      icon: Icons.inventory_2,
                      value: '${tripData.packages}',
                      label: 'Paquetes',
                      color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  final TripData tripData;
  const _TripSummaryCard({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tripData.tripCode.isNotEmpty
                        ? tripData.tripCode
                        : 'Viaje activo',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text('${tripData.stopsProgress}/${tripData.totalStops} paradas',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            TripLocationRow(
                color: Colors.green,
                label: 'ORIGEN',
                value: tripData.originName.isNotEmpty
                    ? tripData.originName
                    : 'Origen no informado'),
            const SizedBox(height: 12),
            TripLocationRow(
                color: Colors.red,
                label: 'DESTINO',
                value: tripData.destinationName.isNotEmpty
                    ? tripData.destinationName
                    : 'Destino no informado'),
            if (tripData.totalStops == 0) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Este viaje no tiene paradas configuradas.',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
          ActionDef(Icons.checklist, 'Checklist', Colors.purple, () {}),
          ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange, () {}),
        ];
      case TripState.inRoute:
      case TripState.geofenceEntry:
        return [
          ActionDef(Icons.qr_code_scanner, 'Escanear', Colors.blue, () {}),
          ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange, () {}),
        ];
      case TripState.delivering:
        return [
          ActionDef(Icons.qr_code_scanner, 'Escanear', Colors.blue, () {}),
          ActionDef(Icons.camera_alt, 'Foto', Colors.purple, () {}),
          ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange, () {}),
        ];
      case TripState.completed:
        return [ActionDef(Icons.summarize, 'Resumen', Colors.blue, () {})];
      case TripState.paused:
        return [
          ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange, () {}),
          ActionDef(Icons.restaurant, 'Descanso', Colors.blue, () {}),
        ];
    }
  }
}

class _KPISection extends StatelessWidget {
  final TripData tripData;
  const _KPISection({required this.tripData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen del día',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: [
              KPICard(value: '${tripData.deliveredCount}',
                  label: 'Entregados', color: Colors.green),
              KPICard(value: '${tripData.pendingCount}',
                  label: 'Pendientes', color: Colors.orange),
              KPICard(value: '${tripData.incidentCount}',
                  label: 'Incidencias', color: Colors.red),
              KPICard(
                  value: '${(tripData.efficiencyPercent * 100).toInt()}%',
                  label: 'Eficiencia',
                  color: theme.colorScheme.primary),
            ],
          ),
        ],
      ),
    );
  }
}
