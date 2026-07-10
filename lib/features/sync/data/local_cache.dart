import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';

// ============================================================================
// LOCAL CACHE — JSON file-based persistence for bootstrap data
// ============================================================================

class LocalCache {
  static const _bootstrapFileName = 'bootstrap_cache.json';
  static const _metadataFileName = 'cache_metadata.json';
  static const _stalenessMinutes = 5;

  final Directory _cacheDir;

  LocalCache(this._cacheDir);

  static Future<LocalCache> create() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/sync_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return LocalCache(cacheDir);
  }

  // ─── Bootstrap Cache ───────────────────────────────

  Future<void> saveBootstrap(DriverBootstrap bootstrap) async {
    final file = File('${_cacheDir.path}/$_bootstrapFileName');
    final json = jsonEncode(_bootstrapToJson(bootstrap));
    await file.writeAsString(json);

    await _saveMetadata(CacheMetadata(
      bootstrapCachedAt: DateTime.now(),
      userId: bootstrap.user.id,
    ));
  }

  Future<DriverBootstrap?> loadBootstrap() async {
    try {
      final file = File('${_cacheDir.path}/$_bootstrapFileName');
      if (!await file.exists()) return null;

      final json = jsonDecode(await file.readAsString());
      return _bootstrapFromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isCacheStale() async {
    final metadata = await _loadMetadata();
    if (metadata == null || metadata.bootstrapCachedAt == null) return true;

    final age = DateTime.now().difference(metadata.bootstrapCachedAt!);
    return age.inMinutes > _stalenessMinutes;
  }

  Future<void> clearBootstrap() async {
    final file = File('${_cacheDir.path}/$_bootstrapFileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ─── Metadata ──────────────────────────────────────

  Future<void> _saveMetadata(CacheMetadata metadata) async {
    final file = File('${_cacheDir.path}/$_metadataFileName');
    final json = jsonEncode({
      'bootstrapCachedAt': metadata.bootstrapCachedAt?.toIso8601String(),
      'userId': metadata.userId,
      'lastSyncAttempt': metadata.lastSyncAttempt?.toIso8601String(),
      'lastSyncSuccess': metadata.lastSyncSuccess?.toIso8601String(),
      'syncFailureCount': metadata.syncFailureCount,
    });
    await file.writeAsString(json);
  }

  Future<CacheMetadata?> _loadMetadata() async {
    try {
      final file = File('${_cacheDir.path}/$_metadataFileName');
      if (!await file.exists()) return null;

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CacheMetadata(
        bootstrapCachedAt: json['bootstrapCachedAt'] != null
            ? DateTime.parse(json['bootstrapCachedAt'] as String)
            : null,
        userId: json['userId'] as String?,
        lastSyncAttempt: json['lastSyncAttempt'] != null
            ? DateTime.parse(json['lastSyncAttempt'] as String)
            : null,
        lastSyncSuccess: json['lastSyncSuccess'] != null
            ? DateTime.parse(json['lastSyncSuccess'] as String)
            : null,
        syncFailureCount: json['syncFailureCount'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> updateSyncMetadata({
    DateTime? lastSyncAttempt,
    DateTime? lastSyncSuccess,
    int? syncFailureCount,
  }) async {
    final current = await _loadMetadata() ?? const CacheMetadata();
    final updated = CacheMetadata(
      bootstrapCachedAt: current.bootstrapCachedAt,
      userId: current.userId,
      lastSyncAttempt: lastSyncAttempt ?? current.lastSyncAttempt,
      lastSyncSuccess: lastSyncSuccess ?? current.lastSyncSuccess,
      syncFailureCount: syncFailureCount ?? current.syncFailureCount,
    );
    await _saveMetadata(updated);
  }

  Future<CacheMetadata?> getMetadata() => _loadMetadata();

  // ─── JSON Serialization ────────────────────────────

  Map<String, dynamic> _bootstrapToJson(DriverBootstrap b) {
    return {
      'user': {
        'id': b.user.id,
        'name': b.user.name,
        'role': b.user.role,
        'companyId': b.user.companyId,
        'active': b.user.active,
      },
      'driver': {
        'id': b.driver.id,
        'status': b.driver.status,
        'license': b.driver.license,
        'vehicleId': b.driver.vehicleId,
      },
      'vehicle': b.vehicle != null
          ? {
              'id': b.vehicle!.id,
              'plate': b.vehicle!.plate,
              'brand': b.vehicle!.brand,
              'model': b.vehicle!.model,
            }
          : null,
      'trip': b.trip != null
          ? {
              'id': b.trip!.id,
              'code': b.trip!.code,
              'status': b.trip!.status,
              'departureTime': b.trip!.departureTime,
              'estimatedArrival': b.trip!.estimatedArrival,
              'totalDistance': b.trip!.totalDistance,
              'remainingDistance': b.trip!.remainingDistance,
              'stopsProgress': b.trip!.stopsProgress,
              'totalStops': b.trip!.totalStops,
              'packagesRemaining': b.trip!.packagesRemaining,
              'progressPercent': b.trip!.progressPercent,
            }
          : null,
      'currentStop': b.currentStop != null
          ? {
              'id': b.currentStop!.id,
              'name': b.currentStop!.name,
              'address': b.currentStop!.address,
              'customerName': b.currentStop!.customerName,
              'status': b.currentStop!.status,
              'etaMinutes': b.currentStop!.etaMinutes,
              'distanceKm': b.currentStop!.distanceKm,
              'packages': b.currentStop!.packages,
              'order': b.currentStop!.order,
            }
          : null,
      'checklist': b.checklist != null
          ? {
              'id': b.checklist!.id,
              'status': b.checklist!.status,
              'completed': b.checklist!.completed,
              'total': b.checklist!.total,
              'items': b.checklist!.items
                  .map((i) => {
                        'id': i.id,
                        'name': i.name,
                        'category': i.category,
                        'status': i.status,
                      })
                  .toList(),
            }
          : null,
      'deliverySession': b.deliverySession != null
          ? {
              'id': b.deliverySession!.id,
              'currentStep': b.deliverySession!.currentStep,
              'scannedPackageIds': b.deliverySession!.scannedPackageIds,
              'photoCompleted': b.deliverySession!.photoCompleted,
              'signatureCompleted': b.deliverySession!.signatureCompleted,
              'otpVerified': b.deliverySession!.otpVerified,
              'status': b.deliverySession!.status,
            }
          : null,
      'device': {
        'gps': b.device.gps,
        'internet': b.device.internet,
        'synced': b.device.synced,
      },
    };
  }

  DriverBootstrap _bootstrapFromJson(Map<String, dynamic> json) {
    return DriverBootstrap(
      user: BootstrapUser.fromJson(json['user'] as Map<String, dynamic>),
      driver: BootstrapDriver.fromJson(json['driver'] as Map<String, dynamic>),
      vehicle: json['vehicle'] != null
          ? BootstrapVehicle.fromJson(json['vehicle'] as Map<String, dynamic>)
          : null,
      trip: json['trip'] != null
          ? BootstrapTrip.fromJson(json['trip'] as Map<String, dynamic>)
          : null,
      currentStop: json['currentStop'] != null
          ? BootstrapCurrentStop.fromJson(
              json['currentStop'] as Map<String, dynamic>)
          : null,
      checklist: json['checklist'] != null
          ? BootstrapChecklist.fromJson(
              json['checklist'] as Map<String, dynamic>)
          : null,
      deliverySession: json['deliverySession'] != null
          ? BootstrapDeliverySession.fromJson(
              json['deliverySession'] as Map<String, dynamic>)
          : null,
      device: json['device'] != null
          ? BootstrapDevice.fromJson(json['device'] as Map<String, dynamic>)
          : const BootstrapDevice(),
    );
  }
}

// ─── Metadata Model ──────────────────────────────────

class CacheMetadata {
  final DateTime? bootstrapCachedAt;
  final String? userId;
  final DateTime? lastSyncAttempt;
  final DateTime? lastSyncSuccess;
  final int syncFailureCount;

  const CacheMetadata({
    this.bootstrapCachedAt,
    this.userId,
    this.lastSyncAttempt,
    this.lastSyncSuccess,
    this.syncFailureCount = 0,
  });
}

// ─── Riverpod Provider ───────────────────────────────

final localCacheProvider = FutureProvider<LocalCache>((ref) async {
  return await LocalCache.create();
});
