import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';

// ============================================================================
// LOCAL CACHE — Snapshot offline: bootstrap + paquetes + paradas + GPS
// ============================================================================

/// Parada/itinerario cacheable (independiente de la UI de trip_detail).
class CachedTripStop {
  final String id;
  final String checkpointId;
  final String? name;
  final String? address;
  final double? lat;
  final double? lng;
  final String status; // pendiente | llego | en_proceso | completado
  final int order;
  final int? etaMinutes;
  final int packages;

  const CachedTripStop({
    required this.id,
    required this.checkpointId,
    this.name,
    this.address,
    this.lat,
    this.lng,
    required this.status,
    required this.order,
    this.etaMinutes,
    this.packages = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'checkpointId': checkpointId,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'status': status,
        'order': order,
        'etaMinutes': etaMinutes,
        'packages': packages,
      };

  factory CachedTripStop.fromJson(Map<String, dynamic> json) {
    return CachedTripStop(
      id: json['id'] as String,
      checkpointId: (json['checkpointId'] as String?) ?? json['id'] as String,
      name: json['name'] as String?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      status: (json['status'] as String?) ?? 'pendiente',
      order: (json['order'] as num?)?.toInt() ?? 0,
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      packages: (json['packages'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Contexto para reanudar GPS/navegación sin red.
class CachedTripContext {
  final String tripId;
  final String empresaId;
  final String conductorId;
  final String vehiculoId;

  const CachedTripContext({
    required this.tripId,
    required this.empresaId,
    required this.conductorId,
    required this.vehiculoId,
  });

  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'empresaId': empresaId,
        'conductorId': conductorId,
        'vehiculoId': vehiculoId,
      };

  factory CachedTripContext.fromJson(Map<String, dynamic> json) {
    return CachedTripContext(
      tripId: json['tripId'] as String,
      empresaId: json['empresaId'] as String,
      conductorId: json['conductorId'] as String,
      vehiculoId: json['vehiculoId'] as String,
    );
  }
}

/// Punto GPS pendiente de envío.
class BufferedGpsPoint {
  final String id;
  final String empresaId;
  final String viajeId;
  final String vehiculoId;
  final String conductorId;
  final double lat;
  final double lng;
  final double? accuracy;
  final double? altitude;
  final double? speedMps;
  final double? heading;
  final DateTime recordedAt;

  const BufferedGpsPoint({
    required this.id,
    required this.empresaId,
    required this.viajeId,
    required this.vehiculoId,
    required this.conductorId,
    required this.lat,
    required this.lng,
    this.accuracy,
    this.altitude,
    this.speedMps,
    this.heading,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'empresaId': empresaId,
        'viajeId': viajeId,
        'vehiculoId': vehiculoId,
        'conductorId': conductorId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'altitude': altitude,
        'speedMps': speedMps,
        'heading': heading,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory BufferedGpsPoint.fromJson(Map<String, dynamic> json) {
    return BufferedGpsPoint(
      id: json['id'] as String,
      empresaId: json['empresaId'] as String,
      viajeId: json['viajeId'] as String,
      vehiculoId: json['vehiculoId'] as String,
      conductorId: json['conductorId'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toTrackingGpsInsert() {
    final ubicacionWkt = 'POINT($lng $lat)';
    return {
      'empresa_id': empresaId,
      'viaje_id': viajeId,
      'vehiculo_id': vehiculoId,
      'conductor_id': conductorId,
      'latitud': lat,
      'longitud': lng,
      'ubicacion': ubicacionWkt,
      'precision_m': accuracy,
      'altitud': altitude,
      'velocidad_kmh': (speedMps ?? 0) * 3.6,
      'rumbo': heading,
      'bateria': 100,
      'internet': false,
      'gps': true,
      'satelites': 0,
      'created_at': recordedAt.toUtc().toIso8601String(),
    };
  }
}

class LocalCache {
  static const _bootstrapFileName = 'bootstrap_cache.json';
  static const _packagesFileName = 'packages_cache.json';
  static const _stopsFileName = 'stops_cache.json';
  static const _gpsBufferFileName = 'gps_buffer.json';
  static const _tripContextFileName = 'trip_context.json';
  static const _gpsTrackingActiveFileName = 'gps_tracking_active.json';
  static const _appliedOpsFileName = 'applied_client_ops.json';
  static const _metadataFileName = 'cache_metadata.json';

  /// Con red: considerar fresco hasta N minutos.
  static const onlineStalenessMinutes = 30;

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
      tripId: bootstrap.trip?.id,
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

  /// Offline: siempre usable. Online: stale tras [onlineStalenessMinutes].
  Future<bool> isCacheStale({bool offline = false}) async {
    if (offline) return false;
    final metadata = await _loadMetadata();
    if (metadata == null || metadata.bootstrapCachedAt == null) return true;

    final age = DateTime.now().difference(metadata.bootstrapCachedAt!);
    return age.inMinutes > onlineStalenessMinutes;
  }

  Future<void> clearBootstrap() async {
    for (final name in [
      _bootstrapFileName,
      _packagesFileName,
      _stopsFileName,
      _tripContextFileName,
      _gpsTrackingActiveFileName,
      _gpsBufferFileName,
      _appliedOpsFileName,
    ]) {
      final f = File('${_cacheDir.path}/$name');
      if (await f.exists()) await f.delete();
    }
  }

  // ─── Packages snapshot ─────────────────────────────

  Future<void> savePackages(
    List<Package> packages, {
    String? tripId,
  }) async {
    final file = File('${_cacheDir.path}/$_packagesFileName');
    final payload = {
      'tripId': tripId,
      'cachedAt': DateTime.now().toIso8601String(),
      'items': packages.map((p) => p.toCacheJson()).toList(),
    };
    await file.writeAsString(jsonEncode(payload));
  }

  Future<List<Package>> loadPackages({String? tripId}) async {
    try {
      final file = File('${_cacheDir.path}/$_packagesFileName');
      if (!await file.exists()) return [];

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (tripId != null &&
          tripId.isNotEmpty &&
          json['tripId'] != null &&
          json['tripId'] != tripId) {
        // Snapshot de otro viaje
        return [];
      }
      final items = json['items'] as List? ?? const [];
      return items
          .map((e) => Package.fromCacheJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Marca paquetes como entregados en el snapshot local (optimista).
  Future<void> markPackagesDelivered(
    List<String> packageIds, {
    String? statusLabel,
  }) async {
    if (packageIds.isEmpty) return;
    final ids = packageIds.toSet();
    final current = await loadPackages();
    if (current.isEmpty) return;

    final updated = current.map((p) {
      if (!ids.contains(p.id)) return p;
      return p.copyWith(
        status: PackageStatus.delivered,
        actualDeliveryDate: DateTime.now(),
      );
    }).toList();

    final meta = await _loadMetadata();
    await savePackages(updated, tripId: meta?.tripId);

    // También actualizar bootstrap.packages si existe
    final boot = await loadBootstrap();
    if (boot != null && boot.packages.isNotEmpty) {
      final newPkgs = boot.packages.map((bp) {
        if (!ids.contains(bp.id)) return bp;
        return BootstrapPackage(
          id: bp.id,
          trackingNumber: bp.trackingNumber,
          status: statusLabel ?? 'ENTREGADO',
          recipientName: bp.recipientName,
          priority: bp.priority,
          weight: bp.weight,
        );
      }).toList();
      await saveBootstrap(DriverBootstrap(
        user: boot.user,
        driver: boot.driver,
        vehicle: boot.vehicle,
        trip: boot.trip,
        checklist: boot.checklist,
        currentStop: boot.currentStop,
        packages: newPkgs,
        deliverySession: boot.deliverySession,
        device: boot.device,
      ));
    }
  }

  // ─── Stops / itinerario ────────────────────────────

  Future<void> saveStops(
    List<CachedTripStop> stops, {
    String? tripId,
  }) async {
    final file = File('${_cacheDir.path}/$_stopsFileName');
    final payload = {
      'tripId': tripId,
      'cachedAt': DateTime.now().toIso8601String(),
      'items': stops.map((s) => s.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(payload));
  }

  Future<List<CachedTripStop>> loadStops({String? tripId}) async {
    try {
      final file = File('${_cacheDir.path}/$_stopsFileName');
      if (!await file.exists()) return [];
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (tripId != null &&
          tripId.isNotEmpty &&
          json['tripId'] != null &&
          json['tripId'] != tripId) {
        return [];
      }
      final items = json['items'] as List? ?? const [];
      final stops = items
          .map((e) =>
              CachedTripStop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return stops;
    } catch (_) {
      return [];
    }
  }

  Future<void> markStopStatus(String stopOrCheckpointId, String status) async {
    final meta = await _loadMetadata();
    final stops = await loadStops(tripId: meta?.tripId);
    if (stops.isEmpty) return;
    final updated = stops.map((s) {
      if (s.id == stopOrCheckpointId || s.checkpointId == stopOrCheckpointId) {
        return CachedTripStop(
          id: s.id,
          checkpointId: s.checkpointId,
          name: s.name,
          address: s.address,
          lat: s.lat,
          lng: s.lng,
          status: status,
          order: s.order,
          etaMinutes: s.etaMinutes,
          packages: s.packages,
        );
      }
      return s;
    }).toList();
    await saveStops(updated, tripId: meta?.tripId);
  }

  // ─── Trip context (navegación offline) ─────────────

  Future<void> saveTripContext(CachedTripContext ctx) async {
    final file = File('${_cacheDir.path}/$_tripContextFileName');
    await file.writeAsString(jsonEncode(ctx.toJson()));
  }

  Future<CachedTripContext?> loadTripContext({String? tripId}) async {
    try {
      final file = File('${_cacheDir.path}/$_tripContextFileName');
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ctx = CachedTripContext.fromJson(json);
      if (tripId != null && tripId.isNotEmpty && ctx.tripId != tripId) {
        return null;
      }
      return ctx;
    } catch (_) {
      return null;
    }
  }

  // ─── Flag: tracking GPS activo (leído por el isolate background) ──

  Future<void> setGpsTrackingActive(bool active) async {
    final file = File('${_cacheDir.path}/$_gpsTrackingActiveFileName');
    await file.writeAsString(
      jsonEncode({
        'active': active,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<bool> isGpsTrackingActive() async {
    try {
      final file = File('${_cacheDir.path}/$_gpsTrackingActiveFileName');
      if (!await file.exists()) return false;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json['active'] == true;
    } catch (_) {
      return false;
    }
  }

  // ─── GPS offline buffer ────────────────────────────

  Future<List<BufferedGpsPoint>> loadGpsBuffer() async {
    try {
      final file = File('${_cacheDir.path}/$_gpsBufferFileName');
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) =>
              BufferedGpsPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveGpsBuffer(List<BufferedGpsPoint> points) async {
    final file = File('${_cacheDir.path}/$_gpsBufferFileName');
    // Cap: descartar los más viejos
    var list = points;
    if (list.length > AppConstants.maxGpsTrailPoints) {
      list = list.sublist(list.length - AppConstants.maxGpsTrailPoints);
    }
    await file.writeAsString(
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> enqueueGpsPoint(BufferedGpsPoint point) async {
    final current = await loadGpsBuffer();
    current.add(point);
    await _saveGpsBuffer(current);
  }

  Future<int> gpsBufferCount() async {
    final list = await loadGpsBuffer();
    return list.length;
  }

  /// Reemplaza el buffer tras un flush parcial (solo deja los no enviados).
  Future<void> replaceGpsBuffer(List<BufferedGpsPoint> remaining) async {
    await _saveGpsBuffer(remaining);
  }

  Future<void> clearGpsBuffer() async {
    final file = File('${_cacheDir.path}/$_gpsBufferFileName');
    if (await file.exists()) await file.delete();
  }

  // ─── Client ops aplicadas (idempotencia local) ─────

  Future<Set<String>> loadAppliedClientOps() async {
    try {
      final file = File('${_cacheDir.path}/$_appliedOpsFileName');
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString()) as List;
      return json.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<bool> isClientOpApplied(String clientOpId) async {
    final set = await loadAppliedClientOps();
    return set.contains(clientOpId);
  }

  Future<void> markClientOpApplied(String clientOpId) async {
    final set = await loadAppliedClientOps();
    set.add(clientOpId);
    // Cap: no crecer sin límite
    var list = set.toList();
    if (list.length > 500) {
      list = list.sublist(list.length - 500);
    }
    final file = File('${_cacheDir.path}/$_appliedOpsFileName');
    await file.writeAsString(jsonEncode(list));
  }

  // ─── Metadata ──────────────────────────────────────

  Future<void> _saveMetadata(CacheMetadata metadata) async {
    final file = File('${_cacheDir.path}/$_metadataFileName');
    final current = await _loadMetadata();
    final merged = CacheMetadata(
      bootstrapCachedAt:
          metadata.bootstrapCachedAt ?? current?.bootstrapCachedAt,
      userId: metadata.userId ?? current?.userId,
      tripId: metadata.tripId ?? current?.tripId,
      lastSyncAttempt: metadata.lastSyncAttempt ?? current?.lastSyncAttempt,
      lastSyncSuccess: metadata.lastSyncSuccess ?? current?.lastSyncSuccess,
      // Preservar contador si el write parcial no lo tocó (0 por default)
      syncFailureCount: metadata.syncFailureCount != 0
          ? metadata.syncFailureCount
          : (current?.syncFailureCount ?? 0),
    );
    final json = jsonEncode({
      'bootstrapCachedAt': merged.bootstrapCachedAt?.toIso8601String(),
      'userId': merged.userId,
      'tripId': merged.tripId,
      'lastSyncAttempt': merged.lastSyncAttempt?.toIso8601String(),
      'lastSyncSuccess': merged.lastSyncSuccess?.toIso8601String(),
      'syncFailureCount': merged.syncFailureCount,
    });
    await file.writeAsString(json);
  }

  Future<CacheMetadata?> _loadMetadata() async {
    try {
      final file = File('${_cacheDir.path}/$_metadataFileName');
      if (!await file.exists()) return null;

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CacheMetadata(
        bootstrapCachedAt: json['bootstrapCachedAt'] != null
            ? DateTime.parse(json['bootstrapCachedAt'] as String)
            : null,
        userId: json['userId'] as String?,
        tripId: json['tripId'] as String?,
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
    await _saveMetadata(CacheMetadata(
      bootstrapCachedAt: current.bootstrapCachedAt,
      userId: current.userId,
      tripId: current.tripId,
      lastSyncAttempt: lastSyncAttempt ?? current.lastSyncAttempt,
      lastSyncSuccess: lastSyncSuccess ?? current.lastSyncSuccess,
      syncFailureCount: syncFailureCount ?? current.syncFailureCount,
    ));
  }

  Future<CacheMetadata?> getMetadata() => _loadMetadata();

  // ─── JSON Serialization ────────────────────────────

  Map<String, dynamic> _bootstrapToJson(DriverBootstrap b) {
    return {
      'user': {
        'id': b.user.id,
        'name': b.user.name,
        'email': b.user.email,
        'phone': b.user.phone,
        'role': b.user.role,
        'companyId': b.user.companyId,
        'active': b.user.active,
      },
      'driver': {
        'id': b.driver.id,
        'status': b.driver.status,
        'license': b.driver.license,
        'phone': b.driver.phone,
        'photoUrl': b.driver.photoUrl,
        'vehicleId': b.driver.vehicleId,
      },
      'vehicle': b.vehicle != null
          ? {
              'id': b.vehicle!.id,
              'plate': b.vehicle!.plate,
              'brand': b.vehicle!.brand,
              'model': b.vehicle!.model,
              'year': b.vehicle!.year,
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
              'origin': b.trip!.origin,
              'destination': b.trip!.destination,
              'routeName': b.trip!.routeName,
            }
          : null,
      'currentStop': b.currentStop != null
          ? {
              'id': b.currentStop!.id,
              'checkpointId': b.currentStop!.checkpointId,
              'name': b.currentStop!.name,
              'address': b.currentStop!.address,
              'customerName': b.currentStop!.customerName,
              'status': b.currentStop!.status,
              'lat': b.currentStop!.lat,
              'lng': b.currentStop!.lng,
              'etaMinutes': b.currentStop!.etaMinutes,
              'distanceKm': b.currentStop!.distanceKm,
              'packages': b.currentStop!.packages,
              'order': b.currentStop!.order,
            }
          : null,
      'checklist': b.checklist != null
          ? {
              'id': b.checklist!.id,
              'type': b.checklist!.type,
              'status': b.checklist!.status,
              'completed': b.checklist!.completed,
              'total': b.checklist!.total,
              'items': b.checklist!.items
                  .map((i) => {
                        'id': i.id,
                        'name': i.name,
                        'category': i.category,
                        'status': i.status,
                        'observation': i.observation,
                      })
                  .toList(),
            }
          : null,
      'packages': b.packages.map((p) => p.toJson()).toList(),
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
      user: BootstrapUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
      driver: BootstrapDriver.fromJson(
        Map<String, dynamic>.from(json['driver'] as Map),
      ),
      vehicle: json['vehicle'] != null
          ? BootstrapVehicle.fromJson(
              Map<String, dynamic>.from(json['vehicle'] as Map),
            )
          : null,
      trip: json['trip'] != null
          ? BootstrapTrip.fromJson(
              Map<String, dynamic>.from(json['trip'] as Map),
            )
          : null,
      currentStop: json['currentStop'] != null
          ? BootstrapCurrentStop.fromJson(
              Map<String, dynamic>.from(json['currentStop'] as Map),
            )
          : null,
      checklist: json['checklist'] != null
          ? BootstrapChecklist.fromJson(
              Map<String, dynamic>.from(json['checklist'] as Map),
            )
          : null,
      packages: json['packages'] != null
          ? (json['packages'] as List)
              .map((p) => BootstrapPackage.fromJson(
                    Map<String, dynamic>.from(p as Map),
                  ))
              .toList()
          : const [],
      deliverySession: json['deliverySession'] != null
          ? BootstrapDeliverySession.fromJson(
              Map<String, dynamic>.from(json['deliverySession'] as Map),
            )
          : null,
      device: json['device'] != null
          ? BootstrapDevice.fromJson(
              Map<String, dynamic>.from(json['device'] as Map),
            )
          : const BootstrapDevice(),
    );
  }
}

class CacheMetadata {
  final DateTime? bootstrapCachedAt;
  final String? userId;
  final String? tripId;
  final DateTime? lastSyncAttempt;
  final DateTime? lastSyncSuccess;
  final int syncFailureCount;

  const CacheMetadata({
    this.bootstrapCachedAt,
    this.userId,
    this.tripId,
    this.lastSyncAttempt,
    this.lastSyncSuccess,
    this.syncFailureCount = 0,
  });
}

final localCacheProvider = FutureProvider<LocalCache>((ref) async {
  return LocalCache.create();
});
