import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap_service.dart';
import 'package:tracking_system_app/features/sync/data/local_cache.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';

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
      _logger.i('Connectivity restored, triggering sync');
      state = state.copyWith(status: SyncStatus.idle);
      syncNow();
    } else if (!isOnline) {
      _logger.w('Connectivity lost');
      state = state.copyWith(status: SyncStatus.offline);
    }
  }

  // ─── Public API ────────────────────────────────────

  /// Load bootstrap: try network first, fall back to cache
  Future<DriverBootstrap?> loadBootstrap({bool forceRefresh = false}) async {
    final isOnline = await _checkOnline();

    if (!isOnline) {
      _logger.i('Offline: loading from cache');
      state = state.copyWith(status: SyncStatus.offline);
      return await _cache?.loadBootstrap();
    }

    if (!forceRefresh && _cache != null && !await _cache!.isCacheStale()) {
      _logger.i('Cache fresh: loading from cache');
      return await _cache?.loadBootstrap();
    }

    // Try network
    try {
      state = state.copyWith(status: SyncStatus.syncing);
      final bootstrap = await DriverBootstrapService.instance.fetchBootstrap();

      // Cache the result
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

      // Fall back to cache
      final cached = await _cache?.loadBootstrap();

      state = state.copyWith(
        status: cached != null ? SyncStatus.idle : SyncStatus.error,
        lastSyncSuccess: false,
        error: e.toString(),
      );

      return cached;
    }
  }

  /// Enqueue a mutation for offline sync
  Future<void> enqueueOperation(
    SyncOperationType type,
    Map<String, dynamic> payload,
  ) async {
    if (_queue == null) return;

    await _queue!.enqueue(type, payload);
    await _updatePendingCount();

    _logger.i('Enqueued operation: ${type.name}');

    // Try to sync immediately if online
    if (await _checkOnline()) {
      syncNow();
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

      await _queue!.markCompleted(operation.id);
      _logger.i('Completed operation: ${operation.type.name}');
    } catch (e) {
      _logger.e('Failed operation ${operation.type.name}: $e');
      await _queue!.markFailed(operation.id, e.toString());
    }
  }

  // ─── Sync Implementations ──────────────────────────

  Future<void> _syncCompleteDelivery(Map<String, dynamic> payload) async {
    final scanned = payload['scannedPackages'];
    final packageIds = scanned is List
        ? scanned.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    // outcome de la app: complete | incident
    final outcome = (payload['outcome'] as String?) ?? 'complete';

    await SupabaseConfig.client.rpc(
      'complete_delivery',
      params: {
        'p_checkpoint_id': payload['checkpointId'],
        'p_trip_id': payload['tripId'],
        'p_stop_id': payload['stopId'],
        'p_outcome': outcome,
        'p_incident_reason': payload['incidentReason'],
        'p_packages_delivered': payload['packagesDelivered'] ?? packageIds.length,
        if (packageIds.isNotEmpty) 'p_package_ids': packageIds,
      },
    );

    // Entrega con incidencia → también fila en delivery_incidencias
    // (el RPC solo escribe eventos; la pantalla Incidencias lee esta tabla).
    if (outcome == 'incident') {
      try {
        await _syncReportIncident({
          'tripId': payload['tripId'],
          'checkpointId': payload['checkpointId'],
          'type': 'otra',
          'description': (payload['incidentReason'] as String?)?.trim().isNotEmpty == true
              ? payload['incidentReason']
              : 'Entrega con incidencia',
          'packageId': packageIds.isNotEmpty ? packageIds.first : null,
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
    // Tabla canónica trackingV2: delivery_incidencias
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
            'source': 'sync_engine',
          },
          if (usuarioId != null) 'usuario_id': usuarioId,
        });
      } catch (e) {
        _logger.w('_syncReportIncident evento: $e');
      }
    }
  }

  Future<void> _syncUpdateTripStatus(Map<String, dynamic> payload) async {
    await SupabaseConfig.client
        .from('operations_viajes')
        .update({'estado': payload['status']})
        .eq('id', payload['tripId']);
  }

  Future<bool> _checkOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _updatePendingCount() async {
    if (_queue == null) return;
    final count = await _queue!.pendingCount;
    state = state.copyWith(pendingOperations: count);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    //super.dispose();
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
