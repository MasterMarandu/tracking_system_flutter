import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap_service.dart';
import 'package:tracking_system_app/core/services/location_service.dart';
import 'package:tracking_system_app/features/packages/data/package_service.dart';
import 'package:tracking_system_app/features/sync/data/local_cache.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';
import 'package:tracking_system_app/features/trips/presentation/screens/trip_detail_screen.dart'
    show TripDetailRepository;

// ============================================================================
// SYNC ENGINE — Orchestrates offline-first data synchronization
// ============================================================================

enum SyncStatus { idle, syncing, error, offline }

class SyncState {
  final SyncStatus status;
  final int pendingOperations;
  final DateTime? lastSyncTime;
  final bool lastSyncSuccess;
  final String? error;

  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingOperations = 0,
    this.lastSyncTime,
    this.lastSyncSuccess = false,
    this.error,
  });

  bool get isOnline => status != SyncStatus.offline;
  bool get isSyncing => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingOperations,
    DateTime? lastSyncTime,
    bool? lastSyncSuccess,
    String? error,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSyncSuccess: lastSyncSuccess ?? this.lastSyncSuccess,
      error: error ?? this.error,
    );
  }
}

class SyncEngine extends Notifier<SyncState> {
  final _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  StreamSubscription? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  bool _isProcessing = false;

  LocalCache? _cache;
  SyncQueue? _queue;

  @override
  SyncState build() {
    _initialize();
    return const SyncState();
  }

  Future<void> _initialize() async {
    _cache = await LocalCache.create();
    _queue = await SyncQueue.create();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Check initial connectivity
    final results = await Connectivity().checkConnectivity();
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (!isOnline) {
      state = state.copyWith(status: SyncStatus.offline);
    }

    // Start periodic sync (every 5 minutes)
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => syncNow(),
    );

    // Initial sync attempt
    if (isOnline) {
      syncNow();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (isOnline && state.status == SyncStatus.offline) {
      _logger.i('Connectivity restored, triggering sync + GPS flush');
      state = state.copyWith(status: SyncStatus.idle);
      syncNow();
      // Vaciar buffer GPS offline
      LocationService.instance.flushGpsBuffer().then((n) {
        if (n > 0) _logger.i('GPS buffer flushed: $n points');
      });
    } else if (!isOnline) {
      _logger.w('Connectivity lost');
      state = state.copyWith(status: SyncStatus.offline);
    }
  }

  // ─── Public API ────────────────────────────────────

  /// Load bootstrap: network when possible, always fall back to local snapshot.
  Future<DriverBootstrap?> loadBootstrap({bool forceRefresh = false}) async {
    // Ensure cache/queue ready (init is async)
    _cache ??= await LocalCache.create();
    _queue ??= await SyncQueue.create();

    final isOnline = await _checkOnline();

    if (!isOnline) {
      _logger.i('Offline: loading bootstrap from cache');
      state = state.copyWith(status: SyncStatus.offline);
      final cached = await _cache?.loadBootstrap();
      if (cached != null) {
        // Marcar device offline en el snapshot devuelto
        return DriverBootstrap(
          user: cached.user,
          driver: cached.driver,
          vehicle: cached.vehicle,
          trip: cached.trip,
          checklist: cached.checklist,
          currentStop: cached.currentStop,
          packages: cached.packages,
          deliverySession: cached.deliverySession,
          device: BootstrapDevice(
            gps: cached.device.gps,
            internet: false,
            synced: state.pendingOperations == 0,
          ),
        );
      }
      return null;
    }

    if (!forceRefresh &&
        _cache != null &&
        !await _cache!.isCacheStale(offline: false)) {
      _logger.i('Cache fresh: loading bootstrap from cache');
      final cached = await _cache?.loadBootstrap();
      if (cached != null) return cached;
    }

    // Try network
    try {
      state = state.copyWith(status: SyncStatus.syncing);
      DriverBootstrap bootstrap;
      try {
        bootstrap = await DriverBootstrapService.instance.fetchBootstrap();
      } catch (e) {
        _logger.w('RPC bootstrap failed, using fallback: $e');
        bootstrap =
            await DriverBootstrapService.instance.fetchBootstrapFallback();
      }

      // Enriquecer con paquetes + paradas y guardar snapshot
      bootstrap = await _attachAndCachePackages(bootstrap);
      await _cacheStopsForTrip(bootstrap.trip?.id);

      await _cache?.saveBootstrap(bootstrap);
      await _cache?.updateSyncMetadata(
        lastSyncAttempt: DateTime.now(),
        lastSyncSuccess: DateTime.now(),
        syncFailureCount: 0,
      );

      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now(),
        lastSyncSuccess: true,
        error: null,
      );

      return bootstrap;
    } catch (e) {
      _logger.e('Network fetch failed: $e');

      await _cache?.updateSyncMetadata(
        lastSyncAttempt: DateTime.now(),
        syncFailureCount: (state.pendingOperations) + 1,
      );

      final cached = await _cache?.loadBootstrap();

      state = state.copyWith(
        status: cached != null ? SyncStatus.idle : SyncStatus.error,
        lastSyncSuccess: false,
        error: e.toString(),
      );

      return cached;
    }
  }

  /// Baja paquetes del viaje y los guarda en cache local.
  Future<DriverBootstrap> _attachAndCachePackages(
    DriverBootstrap bootstrap,
  ) async {
    final tripId = bootstrap.trip?.id;
    if (tripId == null || tripId.isEmpty) return bootstrap;

    try {
      // Import lazy via dynamic package service to avoid circular deps —
      // use PackageService directly
      final page =
          await PackageService.instance.fetchPackagesForTripPageOnline(
        tripId,
        page: 0,
        pageSize: AppConstants.maxPageSize,
      );

      if (page.items.isEmpty) return bootstrap;

      await _cache?.savePackages(page.items, tripId: tripId);

      final bootPkgs = page.items
          .map(
            (p) => BootstrapPackage(
              id: p.id,
              trackingNumber: p.trackingNumber,
              status: p.status.name,
              recipientName: p.recipientName,
              priority: p.priority.name,
              weight: p.weight,
            ),
          )
          .toList();

      return DriverBootstrap(
        user: bootstrap.user,
        driver: bootstrap.driver,
        vehicle: bootstrap.vehicle,
        trip: bootstrap.trip,
        checklist: bootstrap.checklist,
        currentStop: bootstrap.currentStop,
        packages: bootPkgs,
        deliverySession: bootstrap.deliverySession,
        device: bootstrap.device,
      );
    } catch (e) {
      _logger.w('attach packages: $e');
      return bootstrap;
    }
  }

  Future<void> _cacheStopsForTrip(String? tripId) async {
    if (tripId == null || tripId.isEmpty) return;
    try {
      // fetchTripDetail ya persiste stops en LocalCache
      await TripDetailRepository(SupabaseConfig.client).fetchTripDetail(tripId);
    } catch (e) {
      _logger.w('cache stops: $e');
    }
  }

  /// Enqueue a mutation for offline sync (+ updates optimistas locales).
  Future<void> enqueueOperation(
    SyncOperationType type,
    Map<String, dynamic> payload,
  ) async {
    _queue ??= await SyncQueue.create();
    _cache ??= await LocalCache.create();

    // Optimista: marcar paquetes / parada en snapshot local
    if (type == SyncOperationType.completeDelivery) {
      final scanned = payload['scannedPackages'];
      final packageIds = scanned is List
          ? scanned.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      if (packageIds.isNotEmpty) {
        await _cache?.markPackagesDelivered(packageIds);
      }
      final stopId = payload['stopId'] as String?;
      final checkpointId = payload['checkpointId'] as String?;
      final target = stopId ?? checkpointId;
      if (target != null && target.isNotEmpty) {
        await _cache?.markStopStatus(target, 'completado');
      }
    }

    await _queue!.enqueue(type, payload);
    await _updatePendingCount();

    _logger.i('Enqueued operation: ${type.name}');

    if (await _checkOnline()) {
      syncNow();
    } else {
      state = state.copyWith(status: SyncStatus.offline);
    }
  }

  /// Process pending operations in the queue
  Future<void> syncNow() async {
    if (_isProcessing || _queue == null) return;
    _isProcessing = true;

    try {
      state = state.copyWith(status: SyncStatus.syncing);

      final operations = await _queue!.getPendingOperations();
      final readyOperations = operations.where((o) => o.isReady).toList();

      // Flush GPS buffer en cada sync exitoso de red
      try {
        await LocationService.instance.flushGpsBuffer();
      } catch (e) {
        _logger.w('GPS flush during syncNow: $e');
      }

      if (readyOperations.isEmpty) {
        state = state.copyWith(status: SyncStatus.idle);
        return;
      }

      _logger.i('Processing ${readyOperations.length} pending operations');

      for (final operation in readyOperations) {
        await _processOperation(operation);
      }

      await _cache?.updateSyncMetadata(
        lastSyncAttempt: DateTime.now(),
        lastSyncSuccess: DateTime.now(),
      );

      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now(),
        lastSyncSuccess: true,
        error: null,
      );
    } catch (e) {
      _logger.e('Sync failed: $e');
      state = state.copyWith(status: SyncStatus.error, error: e.toString());
    } finally {
      _isProcessing = false;
      await _updatePendingCount();
    }
  }

  /// Force refresh bootstrap from network
  Future<DriverBootstrap?> forceRefresh() async {
    return loadBootstrap(forceRefresh: true);
  }

  /// Get sync status for UI
  Future<SyncState> getSyncStatus() async {
    await _updatePendingCount();
    return state;
  }

  /// Clear all local data (logout)
  Future<void> clearAll() async {
    await _cache?.clearBootstrap();
    await _queue?.clearAll();
    state = const SyncState();
  }

  // ─── Private ───────────────────────────────────────

  Future<void> _processOperation(SyncOperation operation) async {
    if (_queue == null) return;

    await _queue!.markProcessing(operation.id);

    try {
      // Idempotencia local: ya aplicada con éxito antes
      final clientOpId = operation.payload['clientOpId'] as String?;
      if (clientOpId != null &&
          await _cache?.isClientOpApplied(clientOpId) == true) {
        _logger.i('Skip already-applied clientOpId=$clientOpId');
        await _queue!.markCompleted(operation.id);
        return;
      }

      // Preflight de conflictos
      final conflict = await _detectConflict(operation);
      if (conflict != null) {
        await _queue!.markConflict(operation.id, conflict);
        _logger.w('Conflict ${operation.type.name}: $conflict');
        return;
      }

      switch (operation.type) {
        case SyncOperationType.completeDelivery:
          await _syncCompleteDelivery(operation.payload);
        case SyncOperationType.updateChecklist:
          await _syncUpdateChecklist(operation.payload);
        case SyncOperationType.verifyOtp:
          await _syncVerifyOtp(operation.payload);
        case SyncOperationType.submitPhoto:
          await _syncSubmitPhoto(operation.payload);
        case SyncOperationType.submitSignature:
          await _syncSubmitSignature(operation.payload);
        case SyncOperationType.reportIncident:
          await _syncReportIncident(operation.payload);
        case SyncOperationType.updateTripStatus:
          await _syncUpdateTripStatus(operation.payload);
      }

      if (clientOpId != null) {
        await _cache?.markClientOpApplied(clientOpId);
      }
      await _queue!.markCompleted(operation.id);
      _logger.i('Completed operation: ${operation.type.name}');
    } catch (e) {
      _logger.e('Failed operation ${operation.type.name}: $e');
      final msg = e.toString();
      // Errores que no conviene reintentar
      if (_isHardConflictError(msg)) {
        await _queue!.markConflict(operation.id, _humanizeConflict(msg));
      } else {
        await _queue!.markFailed(operation.id, msg);
      }
    }
  }

  /// Conflictos irrecuperables según estado del servidor.
  Future<String?> _detectConflict(SyncOperation operation) async {
    final tripId = operation.payload['tripId'] as String?;
    if (tripId == null || tripId.isEmpty) return null;

    try {
      final trip = await SupabaseConfig.client
          .from('operations_viajes')
          .select('id, estado, deleted_at')
          .eq('id', tripId)
          .maybeSingle();

      if (trip == null || trip['deleted_at'] != null) {
        // Entregas: el hecho del conductor sigue valiendo si hay paquetes
        if (operation.type == SyncOperationType.completeDelivery) {
          return null; // intentar igual (RPC validará)
        }
        return 'El viaje ya no existe en el servidor';
      }

      final estado = (trip['estado'] as String?)?.toLowerCase() ?? '';

      if (operation.type == SyncOperationType.updateTripStatus) {
        final desired = (operation.payload['status'] as String?)?.toLowerCase();
        // No reactivar un viaje cancelado
        if (estado == 'cancelado' &&
            (desired == 'en_curso' || desired == 'programado')) {
          return 'El viaje fue cancelado en oficina; no se puede reactivar desde la app';
        }
        // Ya completado en servidor: no bajar a en_curso
        if (estado == 'completado' && desired == 'en_curso') {
          return 'El viaje ya está completado en el servidor';
        }
      }

      // Entrega: si checkpoint no existe → conflicto
      if (operation.type == SyncOperationType.completeDelivery) {
        final cpId = operation.payload['checkpointId'] as String?;
        if (cpId != null) {
          final cp = await SupabaseConfig.client
              .from('operations_checkpoints')
              .select('id, estado, deleted_at')
              .eq('id', cpId)
              .maybeSingle();
          if (cp == null || cp['deleted_at'] != null) {
            return 'La parada/checkpoint ya no existe en el servidor';
          }
          // Ya completado: no es conflicto — se trata como idempotente en sync
        }
      }
    } catch (e) {
      // Sin red o error de lectura: no marcar conflicto, reintentar
      _logger.w('detectConflict: $e');
    }
    return null;
  }

  bool _isHardConflictError(String msg) {
    final m = msg.toLowerCase();
    return m.contains('access denied') ||
        m.contains('trip not found') ||
        m.contains('checkpoint not found') ||
        m.contains('violates foreign key') ||
        m.contains('permission denied');
  }

  String _humanizeConflict(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('access denied')) {
      return 'Sin permiso para esta operación en el servidor';
    }
    if (m.contains('trip not found')) {
      return 'Viaje no encontrado en el servidor';
    }
    if (m.contains('checkpoint not found')) {
      return 'Parada no encontrada en el servidor';
    }
    return msg.length > 180 ? '${msg.substring(0, 180)}…' : msg;
  }

  // ─── Sync Implementations ──────────────────────────

  Future<void> _syncCompleteDelivery(Map<String, dynamic> payload) async {
    final scanned = payload['scannedPackages'];
    final packageIds = scanned is List
        ? scanned.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final outcome = (payload['outcome'] as String?) ?? 'complete';
    final clientOpId = payload['clientOpId'] as String?;

    // Si el checkpoint ya está completado, no fallar (idempotencia por estado)
    final checkpointId = payload['checkpointId'] as String?;
    if (checkpointId != null) {
      try {
        final cp = await SupabaseConfig.client
            .from('operations_checkpoints')
            .select('estado')
            .eq('id', checkpointId)
            .maybeSingle();
        if (cp != null &&
            (cp['estado'] as String?)?.toLowerCase() == 'completado' &&
            packageIds.isEmpty) {
          _logger.i('Checkpoint ya completado — skip re-entrega');
          return;
        }
      } catch (_) {}
    }

    final baseParams = <String, dynamic>{
      'p_checkpoint_id': payload['checkpointId'],
      'p_trip_id': payload['tripId'],
      'p_stop_id': payload['stopId'],
      'p_outcome': outcome,
      'p_incident_reason': payload['incidentReason'],
      'p_packages_delivered':
          payload['packagesDelivered'] ?? packageIds.length,
      if (packageIds.isNotEmpty) 'p_package_ids': packageIds,
    };

    try {
      // Preferir RPC con idempotencia (008)
      await SupabaseConfig.client.rpc(
        'complete_delivery',
        params: {
          ...baseParams,
          if (clientOpId != null) 'p_client_op_id': clientOpId,
        },
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // Firma vieja sin p_client_op_id
      if (msg.contains('p_client_op_id') ||
          msg.contains('could not find') ||
          msg.contains('function public.complete_delivery')) {
        _logger.w('complete_delivery sin p_client_op_id, reintentando…');
        await SupabaseConfig.client.rpc(
          'complete_delivery',
          params: baseParams,
        );
      } else {
        rethrow;
      }
    }

    if (outcome == 'incident') {
      try {
        await _syncReportIncident({
          'tripId': payload['tripId'],
          'checkpointId': payload['checkpointId'],
          'type': 'otra',
          'description':
              (payload['incidentReason'] as String?)?.trim().isNotEmpty == true
                  ? payload['incidentReason']
                  : 'Entrega con incidencia',
          'packageId': packageIds.isNotEmpty ? packageIds.first : null,
          'clientOpId': clientOpId != null ? '$clientOpId-inc' : null,
        });
      } catch (e) {
        _logger.w('completeDelivery → delivery_incidencias: $e');
      }
    }
  }

  Future<void> _syncUpdateChecklist(Map<String, dynamic> payload) async {
    final items = payload['items'] as List<Map<String, dynamic>>;
    for (final item in items) {
      await SupabaseConfig.client
          .from('fleet_checklists_items')
          .update({'estado': item['status']})
          .eq('id', item['id']);
    }
  }

  Future<void> _syncVerifyOtp(Map<String, dynamic> payload) async {
    await SupabaseConfig.client.rpc(
      'verify_delivery_otp',
      params: {
        'p_checkpoint_id': payload['checkpointId'],
        'p_otp_code': payload['otpCode'],
      },
    );
  }

  Future<void> _syncSubmitPhoto(Map<String, dynamic> payload) async {
    // Upload photo to storage, then update checkpoint
    final filePath = payload['filePath'] as String;
    final checkpointId = payload['checkpointId'] as String;

    final bytes = await File(filePath).readAsBytes();
    final fileName =
        'delivery_${checkpointId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await SupabaseConfig.client.storage
        .from('delivery-photos')
        .uploadBinary(fileName, bytes);

    await SupabaseConfig.client
        .from('operations_checkpoints')
        .update({'foto_evidencia_url': fileName})
        .eq('id', checkpointId);
  }

  Future<void> _syncSubmitSignature(Map<String, dynamic> payload) async {
    final signatureData = payload['signatureData'] as String;
    final checkpointId = payload['checkpointId'] as String;

    await SupabaseConfig.client
        .from('operations_checkpoints')
        .update({'firma_receptor': signatureData})
        .eq('id', checkpointId);
  }

  Future<void> _syncReportIncident(Map<String, dynamic> payload) async {
    final clientOpId = payload['clientOpId'] as String?;
    if (clientOpId != null &&
        await _cache?.isClientOpApplied(clientOpId) == true) {
      return;
    }

    final user = SupabaseConfig.client.auth.currentUser;
    String? empresaId;
    String? usuarioId;
    if (user != null) {
      final core = await SupabaseConfig.client
          .from('core_usuarios')
          .select('id, empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      empresaId = core?['empresa_id'] as String?;
      usuarioId = core?['id'] as String?;
    }
    if (empresaId == null) {
      throw Exception('Sin empresa para reportar incidencia');
    }

    final tipo = (payload['type'] as String?) ?? 'otra';
    final row = await SupabaseConfig.client
        .from(SupabaseConfig.tableIncidencias)
        .insert({
          'empresa_id': empresaId,
          if (payload['tripId'] != null) 'viaje_id': payload['tripId'],
          if (payload['packageId'] != null) 'paquete_id': payload['packageId'],
          'tipo': tipo,
          'descripcion': payload['description'] ?? '',
          'estado': 'abierta',
          if (usuarioId != null) 'created_by': usuarioId,
        })
        .select('id')
        .single();

    final tripId = payload['tripId'] as String?;
    if (tripId != null) {
      try {
        await SupabaseConfig.client.from('operations_viajes_eventos').insert({
          'viaje_id': tripId,
          'tipo': 'incidente',
          'descripcion': payload['description'] ?? tipo,
          'metadata': {
            'incidencia_id': row['id'],
            'tipo': tipo,
            'client_op_id': clientOpId,
            'source': 'sync_engine',
          },
          if (usuarioId != null) 'usuario_id': usuarioId,
        });
      } catch (e) {
        _logger.w('_syncReportIncident evento: $e');
      }

      // Outbox con clave de idempotencia
      if (clientOpId != null) {
        try {
          await SupabaseConfig.client.from('integration_outbox').insert({
            'empresa_id': empresaId,
            'aggregate_type': 'delivery_incidencias',
            'aggregate_id': row['id'],
            'event_type': 'incidencia_reportada',
            'payload': {
              'incidencia_id': row['id'],
              'viaje_id': tripId,
              'tipo': tipo,
              'client_op_id': clientOpId,
              'source': 'tracking_system_flutter',
            },
            'destino': 'web',
            'status': 'pendiente',
            'idempotency_key': 'incidencia:$clientOpId',
          });
        } catch (e) {
          // UNIQUE violation = ya enviada
          _logger.w('_syncReportIncident outbox: $e');
        }
      }
    }
  }

  Future<void> _syncUpdateTripStatus(Map<String, dynamic> payload) async {
    final tripId = payload['tripId'] as String?;
    final status = payload['status'] as String?;
    if (tripId == null || status == null) return;

    // Leer estado actual para no sobrescribir con transición inválida
    final current = await SupabaseConfig.client
        .from('operations_viajes')
        .select('estado')
        .eq('id', tripId)
        .maybeSingle();
    final server = (current?['estado'] as String?)?.toLowerCase();
    final desired = status.toLowerCase();

    if (server == 'cancelado' && desired != 'cancelado') {
      throw Exception(
        'Access denied: viaje cancelado no se puede cambiar a $desired',
      );
    }
    if (server == 'completado' &&
        (desired == 'en_curso' || desired == 'programado')) {
      throw Exception(
        'Access denied: viaje completado no se puede reabrir a $desired',
      );
    }

    await SupabaseConfig.client
        .from('operations_viajes')
        .update({'estado': status})
        .eq('id', tripId);
  }

  Future<void> dismissConflict(String operationId) async {
    _queue ??= await SyncQueue.create();
    await _queue!.dismissOperation(operationId);
    await _updatePendingCount();
  }

  Future<void> retryFailed(String operationId) async {
    _queue ??= await SyncQueue.create();
    await _queue!.retryOperation(operationId);
    await _updatePendingCount();
    await syncNow();
  }

  Future<bool> _checkOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _updatePendingCount() async {
    if (_queue == null) return;
    final ops = await _queue!.pendingCount;
    var gps = 0;
    try {
      gps = await LocationService.instance.pendingGpsCount();
    } catch (_) {}
    state = state.copyWith(pendingOperations: ops + gps);
  }

  void disposeEngine() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
  }
}

// ─── Riverpod Provider ───────────────────────────────

final syncEngineProvider = NotifierProvider<SyncEngine, SyncState>(
  SyncEngine.new,
);

/// Convenience provider for just the sync status
final syncStatusProvider = Provider<SyncStatus>((ref) {
  return ref.watch(syncEngineProvider).status;
});

/// Convenience provider for pending operations count
final pendingSyncCountProvider = Provider<int>((ref) {
  return ref.watch(syncEngineProvider).pendingOperations;
});
