import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap_service.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

// ============================================================================
// SYNC REPOSITORY — High-level API for offline-first operations
// ============================================================================

class SyncRepository {
  final SyncEngine _engine;

  SyncRepository(this._engine);

  // ─── Bootstrap ─────────────────────────────────────

  /// Load bootstrap directly from service, bypassing SyncEngine cache
  /// for the critical startup path.
  Future<DriverBootstrap?> loadBootstrap({bool forceRefresh = false}) async {
    try {
      final bootstrap = await DriverBootstrapService.instance.fetchBootstrap();
      return bootstrap;
    } catch (_) {
      // Try fallback
      try {
        final bootstrap =
            await DriverBootstrapService.instance.fetchBootstrapFallback();
        return bootstrap;
      } catch (_) {
        return null;
      }
    }
  }

  Future<DriverBootstrap?> forceRefresh() => loadBootstrap(forceRefresh: true);

  // ─── Delivery Operations ───────────────────────────

  Future<void> completeDelivery({
    required String checkpointId,
    required String tripId,
    required String stopId,
    required String outcome,
    String? incidentReason,
    required int packagesDelivered,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.completeDelivery,
      {
        'checkpointId': checkpointId,
        'tripId': tripId,
        'stopId': stopId,
        'outcome': outcome,
        'incidentReason': incidentReason,
        'packagesDelivered': packagesDelivered,
      },
    );
  }

  Future<void> updateChecklist({
    required String checklistId,
    required List<Map<String, dynamic>> items,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.updateChecklist,
      {
        'checklistId': checklistId,
        'items': items,
      },
    );
  }

  Future<void> verifyOtp({
    required String checkpointId,
    required String otpCode,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.verifyOtp,
      {
        'checkpointId': checkpointId,
        'otpCode': otpCode,
      },
    );
  }

  Future<void> submitPhoto({
    required String checkpointId,
    required String filePath,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.submitPhoto,
      {
        'checkpointId': checkpointId,
        'filePath': filePath,
      },
    );
  }

  Future<void> submitSignature({
    required String checkpointId,
    required String signatureData,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.submitSignature,
      {
        'checkpointId': checkpointId,
        'signatureData': signatureData,
      },
    );
  }

  Future<void> reportIncident({
    required String tripId,
    String? checkpointId,
    required String type,
    required String description,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.reportIncident,
      {
        'tripId': tripId,
        'checkpointId': checkpointId,
        'type': type,
        'description': description,
      },
    );
  }

  Future<void> updateTripStatus({
    required String tripId,
    required String status,
  }) async {
    await _engine.enqueueOperation(
      SyncOperationType.updateTripStatus,
      {
        'tripId': tripId,
        'status': status,
      },
    );
  }

  // ─── Sync Control ──────────────────────────────────

  Future<void> syncNow() => _engine.syncNow();

  Future<void> clearAll() => _engine.clearAll();
}

// ─── Riverpod Provider ───────────────────────────────

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final engine = ref.watch(syncEngineProvider.notifier);
  return SyncRepository(engine);
});
