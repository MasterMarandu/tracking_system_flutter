import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';

// ============================================================================
// MODELS — Aligned with tracking.sql schema
// ============================================================================

enum TripState {
  preTrip,
  inRoute,
  geofenceEntry,
  delivering,
  completed,
  paused,
}

enum DeliveryStep {
  confirmArrival,
  scanPackages,
  takePhoto,
  captureSignature,
  enterOTP,
  finalizeDelivery,
}

enum ChecklistStatus { pending, inProgress, completed, withObservations }

enum DeliveryOutcome { complete, partial, withIncident }

class ChecklistItem {
  final String id;
  final String name;
  final String category;
  final ChecklistStatus status;
  final String observation;

  const ChecklistItem({
    required this.id,
    required this.name,
    required this.category,
    this.status = ChecklistStatus.pending,
    this.observation = '',
  });

  ChecklistItem copyWith({
    String? id,
    String? name,
    String? category,
    ChecklistStatus? status,
    String? observation,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      status: status ?? this.status,
      observation: observation ?? this.observation,
    );
  }

  Color get statusColor {
    switch (status) {
      case ChecklistStatus.completed:
        return Colors.green;
      case ChecklistStatus.withObservations:
        return Colors.orange;
      case ChecklistStatus.inProgress:
        return const Color(0xFF1565C0);
      case ChecklistStatus.pending:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case ChecklistStatus.completed:
        return Icons.check_circle;
      case ChecklistStatus.withObservations:
        return Icons.warning_amber_rounded;
      case ChecklistStatus.inProgress:
        return Icons.radio_button_checked;
      case ChecklistStatus.pending:
        return Icons.radio_button_unchecked;
    }
  }

  bool get isDone =>
      status == ChecklistStatus.completed ||
      status == ChecklistStatus.withObservations;
}

class DeviceStatus {
  final bool gps;
  final bool internet;
  final bool synced;
  final int batteryPercent;
  final String vehiclePlate;

  const DeviceStatus({
    this.gps = true,
    this.internet = true,
    this.synced = true,
    this.batteryPercent = 100,
    this.vehiclePlate = '',
  });
}

class TripData {
  final String driverName;
  final String nextStopName;
  final String nextStopAddress;
  final String customerName;
  final double distance;
  final int etaMinutes;
  final DateTime etaArrivalTime;
  final int packages;
  final int stopsProgress;
  final int totalStops;
  final int packagesRemaining;
  final double progressPercent;
  final String departureTime;
  final String estimatedArrival;
  final double totalDistance;
  final double remainingDistance;
  final int deliveredCount;
  final int pendingCount;
  final int incidentCount;
  final double efficiencyPercent;

  const TripData({
    this.driverName = '',
    this.nextStopName = '',
    this.nextStopAddress = '',
    this.customerName = '',
    this.distance = 0,
    this.etaMinutes = 0,
    required this.etaArrivalTime,
    this.packages = 0,
    this.stopsProgress = 0,
    this.totalStops = 0,
    this.packagesRemaining = 0,
    this.progressPercent = 0,
    this.departureTime = '',
    this.estimatedArrival = '',
    this.totalDistance = 0,
    this.remainingDistance = 0,
    this.deliveredCount = 0,
    this.pendingCount = 0,
    this.incidentCount = 0,
    this.efficiencyPercent = 0,
  });

  TripData copyWith({
    String? driverName,
    String? nextStopName,
    String? nextStopAddress,
    String? customerName,
    double? distance,
    int? etaMinutes,
    DateTime? etaArrivalTime,
    int? packages,
    int? stopsProgress,
    int? totalStops,
    int? packagesRemaining,
    double? progressPercent,
    String? departureTime,
    String? estimatedArrival,
    double? totalDistance,
    double? remainingDistance,
    int? deliveredCount,
    int? pendingCount,
    int? incidentCount,
    double? efficiencyPercent,
  }) {
    return TripData(
      driverName: driverName ?? this.driverName,
      nextStopName: nextStopName ?? this.nextStopName,
      nextStopAddress: nextStopAddress ?? this.nextStopAddress,
      customerName: customerName ?? this.customerName,
      distance: distance ?? this.distance,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      etaArrivalTime: etaArrivalTime ?? this.etaArrivalTime,
      packages: packages ?? this.packages,
      stopsProgress: stopsProgress ?? this.stopsProgress,
      totalStops: totalStops ?? this.totalStops,
      packagesRemaining: packagesRemaining ?? this.packagesRemaining,
      progressPercent: progressPercent ?? this.progressPercent,
      departureTime: departureTime ?? this.departureTime,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      totalDistance: totalDistance ?? this.totalDistance,
      remainingDistance: remainingDistance ?? this.remainingDistance,
      deliveredCount: deliveredCount ?? this.deliveredCount,
      pendingCount: pendingCount ?? this.pendingCount,
      incidentCount: incidentCount ?? this.incidentCount,
      efficiencyPercent: efficiencyPercent ?? this.efficiencyPercent,
    );
  }
}

class RecentActivity {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String time;

  const RecentActivity({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

// ============================================================================
// MAIN SCREEN
// ============================================================================

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  TripState _tripState = TripState.preTrip;
  DeliveryStep _deliveryStep = DeliveryStep.confirmArrival;
  late AnimationController _progressAnimation;
  late Animation<double> _progressAnim;

  final _otpController = TextEditingController();
  final Set<String> _scannedPackageIds = {};
  List<List<Offset>> _signatureStrokes = [];
  bool _otpFormatValid = false;
  bool _otpVerifying = false;
  bool _otpVerified = false;
  bool _photoTaken = false;
  int _otpAttempts = 0;
  DeliveryOutcome _currentOutcome = DeliveryOutcome.complete;
  String? _incidentReason;

  bool get _isChecklistComplete => _checklistItems.every((i) => i.isDone);

  late TripData _tripData = _emptyTripData();
  late DeviceStatus _deviceStatus = const DeviceStatus();
  late List<ChecklistItem> _checklistItems = _defaultChecklistItems();

  static const _activities = <RecentActivity>[
    RecentActivity(
      icon: Icons.check_circle,
      iconColor: Colors.green,
      title: 'Entrega completada',
      subtitle: 'TRK-2024-0892 - Maria Garcia',
      time: 'Hace 15 min',
    ),
    RecentActivity(
      icon: Icons.warning,
      iconColor: Colors.orange,
      title: 'Incidencia reportada',
      subtitle: 'TRK-2024-0890 - Cliente ausente',
      time: 'Hace 1h',
    ),
    RecentActivity(
      icon: Icons.local_shipping,
      iconColor: Color(0xFF1565C0),
      title: 'Carga completada',
      subtitle: '24 paquetes cargados en TRK-4521',
      time: 'Hace 2h',
    ),
  ];

  List<String> get _packageIds =>
      List.generate(_tripData.packages, (i) => 'TRK-2026-${7000 + i}');

  String? _lastAppliedTripId;
  ProviderSubscription<AsyncValue<DriverBootstrap?>>? _bootstrapSubscription;

  @override
  void initState() {
    super.initState();
    _progressAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final initialAsync = ref.read(bootstrapProvider);
    final initial = initialAsync.valueOrNull;
    if (initial != null) {
      _applyBootstrap(initial);
      _progressAnimation.forward();
    }

    _bootstrapSubscription = ref.listenManual<AsyncValue<DriverBootstrap?>>(
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

  @override
  void dispose() {
    _bootstrapSubscription?.close();
    _progressAnimation.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _onBootstrapChanged(DriverBootstrap next) {
    setState(() => _applyBootstrap(next));
    _progressAnimation
      ..reset()
      ..forward();
  }

  void _applyBootstrap(DriverBootstrap? bootstrap) {
    if (!mounted) return;
    final b = bootstrap;

    if (b == null || !b.user.active) {
      _tripData = _emptyTripData();
      _deviceStatus = const DeviceStatus(gps: false, internet: false, synced: false);
      _checklistItems = const [];
      _tripState = TripState.preTrip;
      _progressAnim = _createProgressAnim(0);
      return;
    }

    _deviceStatus = DeviceStatus(
      gps: b.device.gps,
      internet: b.device.internet,
      synced: b.device.synced,
      batteryPercent: 78,
      vehiclePlate: b.vehicle?.plate ?? '',
    );

    _checklistItems = b.checklist?.items
            .map((i) => _mapChecklistStatus(i))
            .toList() ??
        _defaultChecklistItems();

    if (b.trip == null) {
      _tripData = _emptyTripData();
      _tripState = TripState.preTrip;
      _progressAnim = _createProgressAnim(0);
      return;
    }

    final t = b.trip!;

    _tripData = TripData(
      driverName: b.user.name,
      nextStopName: b.currentStop?.name ?? '',
      nextStopAddress: b.currentStop?.address ?? '',
      customerName: b.currentStop?.customerName ?? '',
      distance: b.currentStop?.distanceKm ?? 0,
      etaMinutes: b.currentStop?.etaMinutes ?? 0,
      etaArrivalTime: DateTime.now().add(
          Duration(minutes: b.currentStop?.etaMinutes ?? 0)),
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

    // Reset delivery state FIRST when trip changes
    final newTripId = b.trip?.id;
    if (newTripId != _lastAppliedTripId) {
      _lastAppliedTripId = newTripId;
      _resetDeliveryState();
    }

    // THEN restore delivery session (if applicable)
    final sessionState = b.resolveState();
    switch (sessionState) {
      case DriverSessionState.tripReady:
        _tripState = TripState.preTrip;
      case DriverSessionState.tripInProgress:
        _tripState = TripState.inRoute;
      case DriverSessionState.deliveryInProgress:
        _tripState = TripState.delivering;
        if (b.deliverySession != null) {
          _restoreDeliverySession(b.deliverySession!);
        }
      case DriverSessionState.paused:
        _tripState = TripState.paused;
      case DriverSessionState.completed:
        _tripState = TripState.completed;
      default:
        _tripState = TripState.preTrip;
    }

    _progressAnim = _createProgressAnim(_tripData.progressPercent);
  }

  void _completeCurrentDelivery() {
    final completedStops = _tripData.stopsProgress + 1;
    final tripCompleted = completedStops >= _tripData.totalStops;
    final newProgress = _tripData.totalStops == 0
        ? 0.0
        : completedStops / _tripData.totalStops;
    final previousProgress = _tripData.progressPercent;

    final incidentDelta = _currentOutcome != DeliveryOutcome.complete ? 1 : 0;

    setState(() {
      _tripData = _tripData.copyWith(
        stopsProgress: completedStops,
        packagesRemaining:
            (_tripData.packagesRemaining - _tripData.packages).clamp(0, 999999),
        deliveredCount: _tripData.deliveredCount + 1,
        pendingCount: (_tripData.pendingCount - 1).clamp(0, 999999),
        progressPercent: newProgress,
        incidentCount: _tripData.incidentCount + incidentDelta,
      );
      _tripState = tripCompleted ? TripState.completed : TripState.inRoute;
    });

    _progressAnim = _createProgressAnim(newProgress, begin: previousProgress);
    _progressAnimation
      ..reset()
      ..forward();

    _resetDeliveryState();
  }

  void _resetDeliveryState() {
    _deliveryStep = DeliveryStep.confirmArrival;
    _scannedPackageIds.clear();
    _signatureStrokes = [];
    _otpController.clear();
    _otpFormatValid = false;
    _otpVerifying = false;
    _otpVerified = false;
    _photoTaken = false;
    _otpAttempts = 0;
    _currentOutcome = DeliveryOutcome.complete;
    _incidentReason = null;
  }

  void _advanceDeliveryStep(StateSetter setModalState) {
    final steps = DeliveryStep.values;
    final currentIndex = steps.indexOf(_deliveryStep);
    if (currentIndex >= steps.length - 1) return;

    final nextStep = steps[currentIndex + 1];

    setState(() {
      _deliveryStep = nextStep;
    });

    setModalState(() {});
  }

  void _setTripState(TripState newState) {
    setState(() {
      _tripState = newState;
    });
  }

  Animation<double> _createProgressAnim(double end, {double begin = 0}) {
    return Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _progressAnimation, curve: Curves.easeInOut),
    );
  }

  void _restoreDeliverySession(BootstrapDeliverySession session) {
    _deliveryStep = DeliveryStep.values.firstWhere(
      (s) => s.name == session.currentStep,
      orElse: () => DeliveryStep.confirmArrival,
    );
    _scannedPackageIds.addAll(session.scannedPackageIds);
    _photoTaken = session.photoCompleted;
    _otpVerified = session.otpVerified;
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

  List<ChecklistItem> _defaultChecklistItems() {
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

  TripData _emptyTripData() {
    return TripData(etaArrivalTime: DateTime.now());
  }

  Future<void> _verifyOtp(StateSetter setModalState) async {
    setModalState(() => _otpVerifying = true);

    try {
      await Future.delayed(const Duration(milliseconds: 800));
      final success = _otpController.text == '123456'; // demo: backend validation

      if (!mounted) return;
      setModalState(() {
        _otpVerifying = false;
        _otpAttempts++;
        _otpVerified = success;
      });

      if (!success && _otpAttempts >= 3 && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Código bloqueado'),
            content: const Text(
                'Has excedido el límite de intentos. Contacta a soporte.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setModalState(() => _otpVerifying = false);
    }
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
      _setTripState(TripState.geofenceEntry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapAsync = ref.watch(bootstrapProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _OperationStatusBar(
              status: _deviceStatus,
              isDark: isDark,
              tripState: _tripState,
            ),
            Expanded(
              child: bootstrapAsync.when(
                loading: () => _buildLoadingScreen(),
                error: (error, _) => _buildErrorScreen(error),
                data: (bootstrap) {
                  if (bootstrap == null) {
                    return _buildNoTripScreen(context, null);
                  }
                  if (!bootstrap.user.active) {
                    return _buildNoTripScreen(context, null);
                  }
                  if (bootstrap.trip == null) {
                    return _buildNoTripScreen(context, bootstrap);
                  }
                  return _buildActiveTrip(context);
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
            const Text(
              'No se pudo cargar tu jornada',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(bootstrapProvider.notifier).loadBootstrap();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTrip(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          SliverToBoxAdapter(child: _buildNextStopCard(context)),
          if (_tripState == TripState.preTrip)
            SliverToBoxAdapter(child: _buildChecklistPrompt(context)),
          SliverToBoxAdapter(child: _buildTripProgress(context)),
          SliverToBoxAdapter(child: _buildPrimaryAction(context)),
          SliverToBoxAdapter(child: _buildQuickActions(context)),
          SliverToBoxAdapter(child: _buildKPIs(context)),
          SliverToBoxAdapter(child: _buildRecentActivity(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildNoTripScreen(
      BuildContext context, DriverBootstrap? bootstrap) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHeader(context),
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
              const SizedBox(height: 4),
              const Text(
                'Próxima actualización: Hoy, 14:00',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _refreshData();
                    if (mounted) {
                      ref.read(bootstrapProvider.notifier).loadBootstrap();
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('ACTUALIZAR'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.phone),
                label: const Text('Contactar soporte'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _KPICard(value: '--', label: 'Entregados', color: Colors.green),
            _KPICard(value: '--', label: 'Pendientes', color: Colors.orange),
            _KPICard(value: '--', label: 'Incidencias', color: Colors.red),
            _KPICard(
                value: '--',
                label: 'Eficiencia',
                color: theme.colorScheme.primary),
          ],
        ),
      ],
    );
  }

  Future<void> _refreshData() async {
    try {
      await ref.read(bootstrapProvider.notifier).loadBootstrap();
    } catch (_) {
      // Error handled by provider
    }
  }

  // ==================== HEADER ====================

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 18
            ? 'Buenas tardes'
            : 'Buenas noches';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              _tripData.driverName.isNotEmpty ? _tripData.driverName[0] : '?',
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
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _tripData.driverName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _deviceStatus.vehiclePlate,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () {},
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== NEXT STOP CARD ====================

  Widget _buildNextStopCard(BuildContext context) {
    if (_tripState == TripState.completed || _tripState == TripState.preTrip) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final a = _tripData.etaArrivalTime;
    final arrivalString =
        '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';

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
                  _Badge(
                    label: 'PRÓXIMA PARADA',
                    icon: Icons.near_me,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _Badge(
                    label: _tripState == TripState.geofenceEntry
                        ? 'EN DESTINO'
                        : 'EN RUTA',
                    icon: _tripState == TripState.geofenceEntry
                        ? Icons.location_on
                        : Icons.check_circle,
                    color: _tripState == TripState.geofenceEntry
                        ? Colors.orangeAccent.withValues(alpha: 0.25)
                        : Colors.greenAccent.withValues(alpha: 0.2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _tripData.nextStopName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                _tripData.nextStopAddress,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.business,
                      size: 14, color: Colors.white.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    _tripData.customerName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _StopStat(
                    icon: Icons.route,
                    value: '${_tripData.distance} km',
                    label: 'Distancia',
                    color: Colors.white,
                  ),
                  _VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.schedule,
                    value: '${_tripData.etaMinutes} min',
                    label: 'ETA',
                    color: Colors.white,
                  ),
                  _VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.access_time,
                    value: arrivalString,
                    label: 'Llegada',
                    color: Colors.white,
                  ),
                  _VDiv(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.inventory_2,
                    value: '${_tripData.packages}',
                    label: 'Paquetes',
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== CHECKLIST PROMPT ====================

  Widget _buildChecklistPrompt(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_late,
                  color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Checklist ${_isChecklistComplete ? 'completado' : 'pendiente'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _isChecklistComplete ? Colors.green : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isChecklistComplete
                        ? 'Todo listo para iniciar el viaje'
                        : 'Completa la inspección para iniciar el viaje',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _showChecklistSheet(context),
              child: Text(_isChecklistComplete ? 'REVISAR' : 'INICIAR'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TRIP PROGRESS ====================

  Widget _buildTripProgress(BuildContext context) {
    if (_tripState == TripState.preTrip || _tripState == TripState.completed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TripInfo(
                    label: 'Salida',
                    value: _tripData.departureTime,
                    icon: Icons.login),
                _TripInfo(
                    label: 'Llegada',
                    value: _tripData.estimatedArrival,
                    icon: Icons.schedule),
                _TripInfo(
                    label: 'Recorrido',
                    value: '${_tripData.totalDistance} km',
                    icon: Icons.straighten),
                _TripInfo(
                    label: 'Restante',
                    value: '${_tripData.remainingDistance} km',
                    icon: Icons.route),
              ],
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _progressAnim,
              builder: (context, child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _progressAnim.value,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_tripData.progressPercent * 100).toInt()}% completado',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${_tripData.stopsProgress}/${_tripData.totalStops} paradas',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_tripData.packagesRemaining} paquetes restantes',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PRIMARY ACTION BUTTON ====================

  Widget _buildPrimaryAction(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: _PrimaryActionButton(
        tripState: _tripState,
        deliveryStep: _deliveryStep,
        theme: theme,
        canStartTrip: _isChecklistComplete,
        onPreTripChecklist: () => _showChecklistSheet(context),
        onStartTrip: () {
          if (_isChecklistComplete) {
            _setTripState(TripState.inRoute);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Completa el checklist antes de iniciar'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onNavigate: () {},
        onArriveManually: _confirmManualArrival,
        onStartDelivery: () {
          _resetDeliveryState();
          _setTripState(TripState.delivering);
          _showDeliverySheet(context);
        },
        onContinueDelivery: () => _showDeliverySheet(context),
        onPause: () => _setTripState(TripState.paused),
        onResume: () => _setTripState(TripState.inRoute),
      ),
    );
  }

  // ==================== DELIVERY FLOW SHEET ====================

  Future<void> _showDeliverySheet(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: _buildDeliveryStepContent(theme, setModalState),
            ),
          );
        });
      },
    );
    // No auto-complete. Only explicit button press completes delivery.
  }

  Widget _buildDeliveryStepContent(
      ThemeData theme, StateSetter setModalState) {
    Widget content;
    switch (_deliveryStep) {
      case DeliveryStep.confirmArrival:
        content = _buildConfirmArrivalStep(theme, setModalState);
      case DeliveryStep.scanPackages:
        content = _buildScanStep(theme, setModalState);
      case DeliveryStep.takePhoto:
        content = _buildPhotoStep(theme, setModalState);
      case DeliveryStep.captureSignature:
        content = _buildSignatureStep(theme, setModalState);
      case DeliveryStep.enterOTP:
        content = _buildOTPStep(theme, setModalState);
      case DeliveryStep.finalizeDelivery:
        content = _buildFinalizeStep(theme, setModalState);
    }
    return _ScrollableColumn(children: [content]);
  }

  Widget _buildConfirmArrivalStep(
      ThemeData theme, StateSetter setModalState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_on,
                  color: Colors.green, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirmar llegada',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Has llegado al destino',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.business, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tripData.nextStopName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(_tripData.nextStopAddress,
                        style: const TextStyle(fontSize: 12)),
                    Text(_tripData.customerName,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1565C0))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => _advanceDeliveryStep(setModalState),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('INICIAR ENTREGA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildScanStep(ThemeData theme, StateSetter setModalState) {
    final allScanned = _scannedPackageIds.length >= _packageIds.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(1, theme),
        const SizedBox(height: 20),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner,
                    size: 64, color: Colors.white70),
                const SizedBox(height: 8),
                const Text('Escanea el código de barras',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    setModalState(() {
                      _scannedPackageIds.addAll(_packageIds);
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('SIMULAR ESCANEO MASIVO'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._packageIds.map(
          (id) => CheckboxListTile(
            value: _scannedPackageIds.contains(id),
            onChanged: (selected) {
              setModalState(() {
                if (selected == true) {
                  _scannedPackageIds.add(id);
                } else {
                  _scannedPackageIds.remove(id);
                }
              });
            },
            title: Text(id),
            subtitle: const Text('Paquete estándar'),
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.green,
            dense: true,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: allScanned
              ? () => _advanceDeliveryStep(setModalState)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            'CONTINUAR (${_scannedPackageIds.length}/${_packageIds.length})',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            if (_scannedPackageIds.length < _packageIds.length) {
              _currentOutcome = DeliveryOutcome.partial;
              _incidentReason = 'Paquetes no escaneados reportados como faltantes';
            }
            _advanceDeliveryStep(setModalState);
          },
          child: const Text('Reportar paquete faltante'),
        ),
      ],
    );
  }

  Widget _buildPhotoStep(ThemeData theme, StateSetter setModalState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(2, theme),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => setModalState(() => _photoTaken = true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: _photoTaken
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _photoTaken ? Colors.green : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: _photoTaken
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 40, color: Colors.green),
                      ),
                      const SizedBox(height: 8),
                      const Text('Foto capturada',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text('Toma una foto del paquete',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Toma una foto del paquete entregado como evidencia',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _photoTaken
              ? () => _advanceDeliveryStep(setModalState)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('CONTINUAR'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            _currentOutcome = DeliveryOutcome.withIncident;
            _incidentReason = 'Foto de evidencia omitida por el conductor';
            _advanceDeliveryStep(setModalState);
          },
          child: const Text('Saltar'),
        ),
      ],
    );
  }

  Widget _buildSignatureStep(ThemeData theme, StateSetter setModalState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(3, theme),
        const SizedBox(height: 16),
        const Text('Firma del receptor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Listener(
            onPointerDown: (event) {
              setModalState(() {
                _signatureStrokes.add([event.localPosition]);
              });
            },
            onPointerMove: (event) {
              setModalState(() {
                if (_signatureStrokes.isNotEmpty) {
                  _signatureStrokes.last = [
                    ..._signatureStrokes.last,
                    event.localPosition,
                  ];
                }
              });
            },
            child: CustomPaint(
              painter: _SignaturePainter(_signatureStrokes),
              size: const Size(double.infinity, 160),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => setModalState(() => _signatureStrokes = []),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Limpiar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _signatureStrokes
                  .expand((s) => s)
                  .isNotEmpty
              ? () => _advanceDeliveryStep(setModalState)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('CONFIRMAR FIRMA'),
        ),
      ],
    );
  }

  Widget _buildOTPStep(ThemeData theme, StateSetter setModalState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(4, theme),
        const SizedBox(height: 20),
        const Icon(Icons.pin, size: 48, color: Color(0xFF1565C0)),
        const SizedBox(height: 12),
        const Text('Código de verificación',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Solicita el código OTP al receptor',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 20),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) {
            setModalState(() {
              _otpFormatValid = v.length == 6;
              _otpVerified = false;
            });
          },
        ),
        if (_otpFormatValid && !_otpVerified) ...[
          const SizedBox(height: 12),
          Text(
            _otpAttempts > 0
                ? 'Código incorrecto. ${3 - _otpAttempts} intentos restantes'
                : '',
            style: TextStyle(
                fontSize: 12, color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
        ],
        if (_otpVerified) ...[
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 6),
              Text('Código verificado',
                  style: TextStyle(color: Colors.green)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _otpFormatValid && !_otpVerifying
              ? () => _verifyOtp(setModalState)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _otpVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('VERIFICAR'),
        ),
        const SizedBox(height: 8),
        if (_otpVerified)
          ElevatedButton.icon(
            onPressed: () => _advanceDeliveryStep(setModalState),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('CONTINUAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => _advanceDeliveryStep(setModalState),
          child: const Text('El receptor no tiene código'),
        ),
      ],
    );
  }

  Widget _buildFinalizeStep(ThemeData theme, StateSetter setModalState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(5, theme),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    size: 48, color: Colors.green),
              ),
              const SizedBox(height: 16),
              const Text('Entrega completada',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${_tripData.packages} paquetes entregados a ${_tripData.customerName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              if (_currentOutcome != DeliveryOutcome.complete &&
                  _incidentReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _incidentReason!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Finalizar entrega'),
                content: const Text(
                  '¿Confirmas que la entrega fue completada correctamente? '
                  'Esta acción no se puede deshacer.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Revisar'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Finalizar'),
                  ),
                ],
              ),
            );

            if (confirmed == true) {
              if (!mounted) return;
              Navigator.pop(context);
              _completeCurrentDelivery();
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('FINALIZAR ENTREGA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryProgress(int currentStep, ThemeData theme) {
    const steps = ['Llegada', 'Escaneo', 'Foto', 'Firma', 'OTP'];
    return Row(
      children: List.generate(steps.length, (i) {
        final isCompleted = i < currentStep;
        final isCurrent = i == currentStep;
        return Expanded(
          child: Row(
            children: [
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color:
                        isCompleted ? Colors.green : Colors.grey.shade200,
                  ),
                ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? Colors.green
                      : isCurrent
                          ? theme.colorScheme.primary
                          : Colors.grey.shade200,
                ),
                child: Icon(
                  isCompleted ? Icons.check : Icons.circle,
                  size: 14,
                  color:
                      isCompleted || isCurrent ? Colors.white : Colors.grey,
                ),
              ),
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color:
                        isCompleted ? Colors.green : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ==================== QUICK ACTIONS ====================

  Widget _buildQuickActions(BuildContext context) {
    final actions = _getContextualActions();
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
                      child: _QuickAction(
                        icon: a.icon,
                        label: a.label,
                        color: a.color,
                        onTap: a.onTap,
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  List<_ActionDef> _getContextualActions() {
    switch (_tripState) {
      case TripState.preTrip:
        return [
          _ActionDef(Icons.checklist, 'Checklist', Colors.purple,
              () => _showChecklistSheet(context)),
          _ActionDef(Icons.phone, 'Soporte', Colors.green, () {}),
          _ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange,
              () {}),
          _ActionDef(Icons.map, 'Mapa', Colors.blue, () {}),
        ];
      case TripState.inRoute:
      case TripState.geofenceEntry:
        return [
          _ActionDef(Icons.qr_code_scanner, 'Escanear', Colors.blue, () {}),
          _ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange,
              () {}),
          _ActionDef(Icons.map, 'Mapa', Colors.teal, () {}),
          _ActionDef(Icons.phone, 'Cliente', Colors.green, () {}),
        ];
      case TripState.delivering:
        return [
          _ActionDef(Icons.qr_code_scanner, 'Escanear', Colors.blue, () {}),
          _ActionDef(Icons.camera_alt, 'Foto', Colors.purple, () {}),
          _ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange,
              () {}),
          _ActionDef(Icons.phone, 'Soporte', Colors.green, () {}),
        ];
      case TripState.completed:
        return [
          _ActionDef(Icons.summarize, 'Resumen', Colors.blue, () {}),
          _ActionDef(
              Icons.report_outlined, 'Incidencia', Colors.orange, () {}),
          _ActionDef(
              Icons.local_gas_station, 'Combust.', Colors.teal, () {}),
          _ActionDef(Icons.logout, 'Cerrar turno', Colors.red, () {}),
        ];
      case TripState.paused:
        return [
          _ActionDef(Icons.report_outlined, 'Incidencia', Colors.orange,
              () {}),
          _ActionDef(Icons.phone, 'Soporte', Colors.green, () {}),
          _ActionDef(Icons.restaurant, 'Descanso', Colors.blue, () {}),
          _ActionDef(
              Icons.local_gas_station, 'Combust.', Colors.teal, () {}),
        ];
    }
  }

  // ==================== KPIs ====================

  Widget _buildKPIs(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del día',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: [
              _KPICard(
                value: '${_tripData.deliveredCount}',
                label: 'Entregados',
                color: Colors.green,
              ),
              _KPICard(
                value: '${_tripData.pendingCount}',
                label: 'Pendientes',
                color: Colors.orange,
              ),
              _KPICard(
                value: '${_tripData.incidentCount}',
                label: 'Incidencias',
                color: Colors.red,
              ),
              _KPICard(
                value:
                    '${(_tripData.efficiencyPercent * 100).toInt()}%',
                label: 'Eficiencia',
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== RECENT ACTIVITY ====================

  Widget _buildRecentActivity(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Actividad reciente',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(onPressed: () {}, child: const Text('Ver todo')),
            ],
          ),
          ..._activities.map(
            (a) => _ActivityItem(
              icon: a.icon,
              iconColor: a.iconColor,
              title: a.title,
              subtitle: a.subtitle,
              time: a.time,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CHECKLIST SHEET ====================

  void _showChecklistSheet(BuildContext context) {
    final theme = Theme.of(context);
    final itemsNotifier =
        ValueNotifier(List<ChecklistItem>.from(_checklistItems));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<List<ChecklistItem>>(
          valueListenable: itemsNotifier,
          builder: (context, items, _) {
            final allDone = items.every((i) => i.isDone);
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Checklist Pre-Viaje',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${items.where((i) => i.status == ChecklistStatus.completed).length}/${items.length}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: _groupByCategory(items)
                              .entries
                              .expand((entry) => [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 12, bottom: 4),
                                      child: Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    ...entry.value.map(
                                      (item) => _ChecklistTile(
                                        item: item,
                                        onToggle: () {
                                          final updatedItems =
                                              itemsNotifier.value.map((i) {
                                            if (i.id != item.id) return i;
                                            return i.copyWith(
                                              status:
                                                  i.status ==
                                                          ChecklistStatus
                                                              .completed
                                                      ? ChecklistStatus
                                                          .pending
                                                      : ChecklistStatus
                                                          .completed,
                                            );
                                          }).toList();

                                          itemsNotifier.value = updatedItems;

                                          setState(() {
                                            _checklistItems = updatedItems;
                                          });
                                        },
                                      ),
                                    ),
                                  ])
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: allDone
                            ? () => Navigator.pop(ctx)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('CHECKLIST COMPLETADO'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, List<ChecklistItem>> _groupByCategory(
      List<ChecklistItem> items) {
    final map = <String, List<ChecklistItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }
}

// ============================================================================
// OPERATION STATUS BAR
// ============================================================================

class _OperationStatusBar extends StatelessWidget {
  final DeviceStatus status;
  final bool isDark;
  final TripState tripState;

  const _OperationStatusBar({
    required this.status,
    required this.isDark,
    required this.tripState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!status.internet || !status.gps || !status.synced)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.red.withValues(alpha: 0.85),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('MODO OFFLINE - Los datos se sincronizarán al reconectar',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(
                color: theme.dividerTheme.color ?? Colors.grey.shade200,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              _StatusDot(
                icon: Icons.gps_fixed,
                active: status.gps,
              ),
              const SizedBox(width: 6),
              Text('GPS',
                  style: TextStyle(
                      fontSize: 11,
                      color: status.gps ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              _StatusDot(
                icon: Icons.wifi,
                active: status.internet,
              ),
              const SizedBox(width: 6),
              Text('Red',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          status.internet ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              _StatusDot(
                icon: Icons.sync,
                active: status.synced,
              ),
              const SizedBox(width: 6),
              Text('Sync',
                  style: TextStyle(
                      fontSize: 11,
                      color: status.synced ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (status.batteryPercent <= 20) ...[
                const Icon(Icons.battery_alert,
                    color: Colors.red, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Batería baja',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ] else ...[
                Icon(
                  status.batteryPercent > 60
                      ? Icons.battery_full
                      : status.batteryPercent > 30
                          ? Icons.battery_5_bar
                          : Icons.battery_3_bar,
                  size: 18,
                  color: status.batteryPercent > 60
                      ? Colors.green
                      : status.batteryPercent > 30
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '${status.batteryPercent}%',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(width: 16),
              _tripStateBadge(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tripStateBadge() {
    String label;
    Color color;
    switch (tripState) {
      case TripState.preTrip:
        label = 'PRE-VIAJE';
        color = Colors.grey;
      case TripState.inRoute:
        label = 'EN RUTA';
        color = const Color(0xFF1565C0);
      case TripState.geofenceEntry:
        label = 'EN DESTINO';
        color = Colors.orange;
      case TripState.delivering:
        label = 'ENTREGANDO';
        color = Colors.purple;
      case TripState.completed:
        label = 'COMPLETADO';
        color = Colors.green;
      case TripState.paused:
        label = 'PAUSADO';
        color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final IconData icon;
  final bool active;

  const _StatusDot({required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.green : Colors.red,
      ),
    );
  }
}

// ============================================================================
// CHECKLIST TILE
// ============================================================================

class _ChecklistTile extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;

  const _ChecklistTile({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: item.status == ChecklistStatus.completed
                ? Colors.green.withValues(alpha: 0.05)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.status == ChecklistStatus.completed
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(item.statusIcon, size: 20, color: item.statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    decoration: item.status == ChecklistStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                    color: item.status == ChecklistStatus.completed
                        ? Colors.grey
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PRIMARY ACTION BUTTON
// ============================================================================

class _PrimaryActionButton extends StatelessWidget {
  final TripState tripState;
  final DeliveryStep deliveryStep;
  final ThemeData theme;
  final bool canStartTrip;
  final VoidCallback onPreTripChecklist;
  final VoidCallback onStartTrip;
  final VoidCallback onNavigate;
  final VoidCallback onArriveManually;
  final VoidCallback onStartDelivery;
  final VoidCallback onContinueDelivery;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const _PrimaryActionButton({
    required this.tripState,
    required this.deliveryStep,
    required this.theme,
    required this.canStartTrip,
    required this.onPreTripChecklist,
    required this.onStartTrip,
    required this.onNavigate,
    required this.onArriveManually,
    required this.onStartDelivery,
    required this.onContinueDelivery,
    required this.onPause,
    required this.onResume,
  });

  static String _deliveryStepLabel(DeliveryStep step) {
    switch (step) {
      case DeliveryStep.confirmArrival:
        return 'CONTINUAR: CONFIRMAR LLEGADA';
      case DeliveryStep.scanPackages:
        return 'CONTINUAR: ESCANEAR PAQUETES';
      case DeliveryStep.takePhoto:
        return 'CONTINUAR: TOMAR FOTO';
      case DeliveryStep.captureSignature:
        return 'CONTINUAR: OBTENER FIRMA';
      case DeliveryStep.enterOTP:
        return 'CONTINUAR: VERIFICAR OTP';
      case DeliveryStep.finalizeDelivery:
        return 'CONTINUAR: FINALIZAR ENTREGA';
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (tripState) {
      case TripState.preTrip:
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: onPreTripChecklist,
              icon: const Icon(Icons.assignment),
              label: const Text('INICIAR CHECKLIST'),
              style: _buttonStyle(Colors.orange),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: canStartTrip ? onStartTrip : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('INICIAR VIAJE'),
              style: _buttonStyle(Colors.green),
            ),
            if (!canStartTrip)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Completa el checklist para habilitar',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        );
      case TripState.inRoute:
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation),
              label: const Text('NAVEGAR'),
              style: _buttonStyle(theme.colorScheme.primary),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onArriveManually,
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Confirmar llegada manualmente'),
            ),
          ],
        );
      case TripState.geofenceEntry:
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: onStartDelivery,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('INICIAR ENTREGA'),
              style: _buttonStyle(Colors.purple),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onNavigate,
                child: const Text('Abrir navegación')),
          ],
        );
      case TripState.delivering:
        return ElevatedButton.icon(
          onPressed: onContinueDelivery,
          icon: const Icon(Icons.pending_actions),
          label: Text(_deliveryStepLabel(deliveryStep)),
          style: _buttonStyle(Colors.purple),
        );
      case TripState.paused:
        return ElevatedButton.icon(
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow),
          label: const Text('REANUDAR VIAJE'),
          style: _buttonStyle(Colors.orange),
        );
      case TripState.completed:
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('VIAJE COMPLETADO',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        );
    }
  }

  ButtonStyle _buttonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    );
  }
}

// ============================================================================
// REUSABLE WIDGETS
// ============================================================================

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StopStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 10, color: color.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _VDiv extends StatelessWidget {
  final Color color;
  const _VDiv({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: color);
}

class _TripInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _TripInfo({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          label,
          style: TextStyle(
              fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ActionDef {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionDef(this.icon, this.label, this.color, this.onTap);
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _KPICard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
                fontSize: 11,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _ScrollableColumn extends StatelessWidget {
  final List<Widget> children;
  const _ScrollableColumn({required this.children});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ============================================================================
// SIGNATURE PAINTER (multi-stroke)
// ============================================================================

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1565C0)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint);
        continue;
      }
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final p0 = stroke[i];
        final p1 = stroke[i + 1];
        path.quadraticBezierTo(
            p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
