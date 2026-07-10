import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// ============================================================================
// SYNC QUEUE — Persistent queue for offline mutations
// ============================================================================

class SyncQueue {
  static const _queueFileName = 'sync_queue.json';

  final Directory _cacheDir;
  final _uuid = const Uuid();

  SyncQueue(this._cacheDir);

  static Future<SyncQueue> create() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/sync_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return SyncQueue(cacheDir);
  }

  // ─── Queue Operations ──────────────────────────────

  Future<List<SyncOperation>> getPendingOperations() async {
    try {
      final file = File('${_cacheDir.path}/$_queueFileName');
      if (!await file.exists()) return [];

      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => SyncOperation.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<SyncOperation> enqueue(SyncOperationType type, Map<String, dynamic> payload) async {
    final operation = SyncOperation(
      id: _uuid.v4(),
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
      retryCount: 0,
      status: SyncOperationStatus.pending,
    );

    final operations = await getPendingOperations();
    operations.add(operation);
    await _saveOperations(operations);

    return operation;
  }

  Future<void> markProcessing(String operationId) async {
    final operations = await getPendingOperations();
    final index = operations.indexWhere((o) => o.id == operationId);
    if (index == -1) return;

    operations[index] = operations[index].copyWith(
      status: SyncOperationStatus.processing,
    );
    await _saveOperations(operations);
  }

  Future<void> markCompleted(String operationId) async {
    final operations = await getPendingOperations();
    operations.removeWhere((o) => o.id == operationId);
    await _saveOperations(operations);
  }

  Future<void> markFailed(String operationId, String error) async {
    final operations = await getPendingOperations();
    final index = operations.indexWhere((o) => o.id == operationId);
    if (index == -1) return;

    final op = operations[index];
    final maxRetries = 3;

    if (op.retryCount >= maxRetries) {
      operations[index] = op.copyWith(
        status: SyncOperationStatus.failed,
        lastError: error,
      );
    } else {
      operations[index] = op.copyWith(
        status: SyncOperationStatus.pending,
        retryCount: op.retryCount + 1,
        lastError: error,
        nextRetryAt: _calculateRetryDelay(op.retryCount + 1),
      );
    }
    await _saveOperations(operations);
  }

  Future<void> retryOperation(String operationId) async {
    final operations = await getPendingOperations();
    final index = operations.indexWhere((o) => o.id == operationId);
    if (index == -1) return;

    operations[index] = operations[index].copyWith(
      status: SyncOperationStatus.pending,
      retryCount: 0,
      lastError: null,
      nextRetryAt: null,
    );
    await _saveOperations(operations);
  }

  Future<void> clearCompleted() async {
    final operations = await getPendingOperations();
    final pending = operations
        .where((o) => o.status != SyncOperationStatus.completed)
        .toList();
    await _saveOperations(pending);
  }

  Future<void> clearAll() async {
    await _saveOperations([]);
  }

  Future<int> get pendingCount async {
    final operations = await getPendingOperations();
    return operations.where((o) =>
        o.status == SyncOperationStatus.pending ||
        o.status == SyncOperationStatus.failed).length;
  }

  // ─── Private ───────────────────────────────────────

  Future<void> _saveOperations(List<SyncOperation> operations) async {
    final file = File('${_cacheDir.path}/$_queueFileName');
    final json = jsonEncode(operations.map((o) => o.toJson()).toList());
    await file.writeAsString(json);
  }

  DateTime _calculateRetryDelay(int retryCount) {
    // Exponential backoff: 5s, 15s, 45s
    final delaySeconds = [5, 15, 45];
    final index = (retryCount - 1).clamp(0, delaySeconds.length - 1);
    return DateTime.now().add(Duration(seconds: delaySeconds[index]));
  }
}

// ─── Models ──────────────────────────────────────────

enum SyncOperationType {
  completeDelivery,
  updateChecklist,
  verifyOtp,
  submitPhoto,
  submitSignature,
  reportIncident,
  updateTripStatus,
}

enum SyncOperationStatus {
  pending,
  processing,
  completed,
  failed,
}

class SyncOperation {
  final String id;
  final SyncOperationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final SyncOperationStatus status;
  final String? lastError;
  final DateTime? nextRetryAt;

  const SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.retryCount,
    required this.status,
    this.lastError,
    this.nextRetryAt,
  });

  bool get canRetry => status == SyncOperationStatus.failed && retryCount < 3;
  bool get isPending => status == SyncOperationStatus.pending;
  bool get isReady => isPending && (nextRetryAt == null || nextRetryAt!.isBefore(DateTime.now()));

  SyncOperation copyWith({
    SyncOperationStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? nextRetryAt,
  }) {
    return SyncOperation(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'status': status.name,
      'lastError': lastError,
      'nextRetryAt': nextRetryAt?.toIso8601String(),
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      type: SyncOperationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SyncOperationType.completeDelivery,
      ),
      payload: json['payload'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      status: SyncOperationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SyncOperationStatus.pending,
      ),
      lastError: json['lastError'] as String?,
      nextRetryAt: json['nextRetryAt'] != null
          ? DateTime.parse(json['nextRetryAt'] as String)
          : null,
    );
  }
}

// ─── Riverpod Provider ───────────────────────────────

final syncQueueProvider = FutureProvider<SyncQueue>((ref) async {
  return await SyncQueue.create();
});
