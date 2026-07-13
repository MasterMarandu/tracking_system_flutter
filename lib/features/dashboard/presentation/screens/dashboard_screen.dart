import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/core/services/navigation_service.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/dashboard/providers/trip_state_provider.dart';
import 'package:tracking_system_app/features/dashboard/providers/delivery_flow_provider.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/operation_status_bar.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/dashboard_body.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/delivery_flow_sheet.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  TripData _tripData = const TripData();
  DeviceStatus _deviceStatus = const DeviceStatus();
  List<ChecklistItem> _checklistItems = _defaultChecklistItems();
  String? _lastAppliedTripId;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<DriverBootstrap?>>(
      bootstrapProvider,
      (previous, next) {
        if (!mounted) return;
        final bootstrap = next.valueOrNull;
        if (bootstrap == null) return;
        _onBootstrapChanged(bootstrap);
      },
      fireImmediately: true,
    );
  }

  void _onBootstrapChanged(DriverBootstrap next) {
    setState(() => _applyBootstrap(next));
  }

  void _applyBootstrap(DriverBootstrap? bootstrap) {
    if (!mounted) return;
    final b = bootstrap;

    if (b == null || !b.user.active) {
      _lastAppliedTripId = null;
      _tripData = const TripData();
      _deviceStatus = const DeviceStatus(gps: false, internet: false, synced: false);
      _checklistItems = const [];
      ref.read(tripStateProvider.notifier).forceState(TripState.noTrip);
      return;
    }

    _deviceStatus = DeviceStatus(
      gps: b.device.gps,
      internet: b.device.internet,
      synced: b.device.synced,
      vehiclePlate: b.vehicle?.plate ?? '',
    );

    _checklistItems = b.checklist?.items
            .map(_mapChecklistStatus)
            .toList() ??
        _defaultChecklistItems();

    if (b.trip == null) {
      _lastAppliedTripId = null;
      _tripData = const TripData().copyWith(driverName: b.user.name);
      ref.read(tripStateProvider.notifier).forceState(TripState.noTrip);
      return;
    }

    final t = b.trip!;

    _tripData = TripData(
      driverName: b.user.name,
      tripCode: t.code,
      originName: t.origin ?? '',
      destinationName: t.destination ?? '',
      nextStopName: b.currentStop?.name ?? '',
      nextStopAddress: b.currentStop?.address ?? '',
      customerName: b.currentStop?.customerName ?? '',
      distance: b.currentStop?.distanceKm,
      etaMinutes: b.currentStop?.etaMinutes,
      etaArrivalTime: b.currentStop?.etaMinutes != null
          ? DateTime.now().add(Duration(minutes: b.currentStop!.etaMinutes!))
          : null,
      packages: b.currentStop?.packages ?? 0,
      stopsProgress: t.stopsProgress ?? 0,
      totalStops: t.totalStops ?? 0,
      packagesRemaining: t.packagesRemaining ?? 0,
      progressPercent: t.progressPercent ?? 0,
      departureTime: t.departureTime ?? '',
      estimatedArrival: t.estimatedArrival ?? '',
      totalDistance: t.totalDistance ?? 0,
      remainingDistance: t.remainingDistance ?? 0,
      deliveredCount: t.stopsProgress ?? 0,
      pendingCount: (t.totalStops ?? 0) - (t.stopsProgress ?? 0),
      incidentCount: 0,
      efficiencyPercent: t.totalStops != null && t.totalStops! > 0
          ? (t.stopsProgress ?? 0) / t.totalStops!
          : 0,
    );

    final newTripId = b.trip?.id;
    if (newTripId != _lastAppliedTripId) {
      _lastAppliedTripId = newTripId;
      ref.read(deliveryFlowProvider.notifier).reset();
    }

    final sessionState = b.resolveState();
    switch (sessionState) {
      case DriverSessionState.tripReady:
        ref.read(tripStateProvider.notifier).forceState(TripState.preTrip);
      case DriverSessionState.tripInProgress:
        ref.read(tripStateProvider.notifier).forceState(TripState.inRoute);
      case DriverSessionState.deliveryInProgress:
        ref.read(tripStateProvider.notifier).forceState(TripState.delivering);
        if (b.deliverySession != null) {
          ref
              .read(deliveryFlowProvider.notifier)
              .restoreFromSession(b.deliverySession!);
        }
      case DriverSessionState.paused:
        ref.read(tripStateProvider.notifier).forceState(TripState.paused);
      case DriverSessionState.completed:
        ref.read(tripStateProvider.notifier).forceState(TripState.completed);
      case DriverSessionState.noTripAssigned:
        ref.read(tripStateProvider.notifier).forceState(TripState.noTrip);
      default:
        ref.read(tripStateProvider.notifier).forceState(TripState.preTrip);
    }
  }

  ChecklistItem _mapChecklistStatus(BootstrapChecklistItem item) {
    ChecklistStatus status;
    switch (item.status) {
      case 'ok':
        status = ChecklistStatus.completed;
      case 'observacion':
        status = ChecklistStatus.withObservations;
      case 'fallo':
        status = ChecklistStatus.inProgress;
      default:
        status = ChecklistStatus.pending;
    }
    return ChecklistItem(
      id: item.id,
      name: item.name,
      category: item.category,
      status: status,
    );
  }

  static List<ChecklistItem> _defaultChecklistItems() {
    return const [
      ChecklistItem(id: '1', name: 'Combustible', category: 'Vehículo'),
      ChecklistItem(id: '2', name: 'Neumáticos', category: 'Vehículo'),
      ChecklistItem(id: '3', name: 'Luces', category: 'Vehículo'),
      ChecklistItem(id: '4', name: 'Frenos', category: 'Vehículo'),
      ChecklistItem(id: '5', name: 'Espejos', category: 'Vehículo'),
      ChecklistItem(id: '6', name: 'Documentación', category: 'Documentos'),
      ChecklistItem(id: '7', name: 'Licencia de conducir', category: 'Documentos'),
      ChecklistItem(id: '8', name: 'Seguro del vehículo', category: 'Documentos'),
      ChecklistItem(id: '9', name: 'Fotos del vehículo', category: 'Evidencia'),
      ChecklistItem(id: '10', name: 'Carga asegurada', category: 'Carga'),
      ChecklistItem(id: '11', name: 'Sellos verificados', category: 'Carga'),
      ChecklistItem(id: '12', name: 'Temperatura de carga', category: 'Carga'),
    ];
  }

  bool get _isChecklistComplete =>
      _checklistItems.isNotEmpty && _checklistItems.every((i) => i.isDone);

  @override
  Widget build(BuildContext context) {
    final bootstrapAsync = ref.watch(bootstrapProvider);
    final syncState = ref.watch(syncEngineProvider);
    final tripState = ref.watch(tripStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveDeviceStatus = DeviceStatus(
      gps: _deviceStatus.gps,
      internet: syncState.isOnline,
      synced: syncState.status == SyncStatus.idle &&
          syncState.pendingOperations == 0,
      batteryPercent: _deviceStatus.batteryPercent,
      vehiclePlate: _deviceStatus.vehiclePlate,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OperationStatusBar(
              status: effectiveDeviceStatus,
              isDark: isDark,
              tripState: tripState,
              pendingSyncCount: syncState.pendingOperations,
            ),
            Expanded(
              child: bootstrapAsync.when(
                loading: () => _buildLoadingScreen(),
                error: (error, _) => _buildErrorScreen(error),
                data: (bootstrap) {
                  if (bootstrap == null || !bootstrap.user.active || bootstrap.trip == null) {
                    return _buildNoTripScreen(bootstrap);
                  }
                  return _buildActiveTrip(bootstrap);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Cargando tu jornada...'),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No se pudo cargar tu jornada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'No pudimos cargar la información. '
              'Verifica tu conexión e inténtalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(bootstrapProvider.notifier).loadBootstrap(),
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoTripScreen(DriverBootstrap? bootstrap) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inbox_outlined,
                    size: 48, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(
                'Hola ${bootstrap?.user.name ?? ''}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'No tienes viajes asignados actualmente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(bootstrapProvider.notifier).loadBootstrap(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('ACTUALIZAR'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onChecklistChanged(List<ChecklistItem> updated) {
    setState(() => _checklistItems = updated);
  }

  Widget _buildActiveTrip(DriverBootstrap bootstrap) {
    return DashboardActiveBody(
      tripData: _tripData,
      checklistItems: _checklistItems,
      deliveryStep: ref.read(deliveryFlowProvider).currentStep,
      isChecklistComplete: _isChecklistComplete,
      bootstrap: bootstrap,
      onNavigate: _onNavigate,
      onArriveManually: _confirmManualArrival,
      onStartDelivery: _onStartDelivery,
      onContinueDelivery: _onContinueDelivery,
      onRefresh: _refreshData,
      onChecklistChanged: _onChecklistChanged,
    );
  }

  Future<void> _refreshData() async {
    try {
      await ref.read(bootstrapProvider.notifier).loadBootstrap();
    } catch (_) {}
  }

  Future<void> _onNavigate() async {
    final bootstrap = ref.read(bootstrapProvider).valueOrNull;
    final trip = bootstrap?.trip;

    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay un viaje activo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await NavigationService.instance.openNavigation(
      tripId: trip.id,
      activateTrip: false,
    );

    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ?? 'No se pudo abrir la navegación.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (trip.status == 'pausado' || trip.status == 'programado') {
      await ref.read(syncEngineProvider.notifier).enqueueOperation(
            SyncOperationType.updateTripStatus,
            {
              'tripId': trip.id,
              'status': 'en_curso',
            },
          );
    }

    if (!mounted) return;

    final tripState = ref.read(tripStateProvider);
    if (tripState == TripState.paused || tripState == TripState.preTrip) {
      ref.read(tripStateProvider.notifier).setState(TripState.inRoute);
    }

    if (mounted) context.go('/tracking');
  }

  Future<void> _confirmManualArrival() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar llegada manualmente'),
        content: const Text(
          'Solo usa esta opción si el GPS no detectó automáticamente '
          'tu llegada al destino. Esta acción será registrada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(tripStateProvider.notifier).setState(TripState.geofenceEntry);
    }
  }

  void _onStartDelivery() {
    ref.read(deliveryFlowProvider.notifier).reset();
    ref.read(tripStateProvider.notifier).setState(TripState.delivering);
    _showDeliverySheet();
  }

  void _onContinueDelivery() {
    _showDeliverySheet();
  }

  void _showDeliverySheet() {
    final bootstrap = ref.read(bootstrapProvider).valueOrNull;
    final trip = bootstrap?.trip;
    final stop = bootstrap?.currentStop;

    showDeliverySheet(
      context,
      tripData: _tripData,
      tripId: trip?.id ?? '',
      stopId: stop?.id,
      checkpointId: stop?.checkpointId,
      onDeliveryCompleted: _onDeliveryCompleted,
    );
  }

  void _onDeliveryCompleted() {
    final completedStops = _tripData.stopsProgress + 1;
    final tripCompleted = completedStops >= _tripData.totalStops;
    final newProgress = _tripData.totalStops == 0
        ? 0.0
        : completedStops / _tripData.totalStops;

    setState(() {
      _tripData = _tripData.copyWith(
        stopsProgress: completedStops,
        packagesRemaining:
            (_tripData.packagesRemaining - _tripData.packages).clamp(0, 999999).toInt(),
        deliveredCount: _tripData.deliveredCount + 1,
        pendingCount: (_tripData.pendingCount - 1).clamp(0, 999999).toInt(),
        progressPercent: newProgress,
      );

      if (tripCompleted) {
        ref.read(tripStateProvider.notifier).setState(TripState.completed);
      } else {
        ref.read(tripStateProvider.notifier).setState(TripState.inRoute);
      }
    });
  }
}
