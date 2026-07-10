// ============================================================================
// DRIVER BOOTSTRAP — Maps to get_driver_bootstrap() RPC response
// ============================================================================

enum DriverSessionState {
  loading,
  unauthenticated,
  profileIncomplete,
  noTripAssigned,
  tripReady,
  tripInProgress,
  deliveryInProgress,
  paused,
  completed,
  error,
}

class DriverBootstrap {
  final BootstrapUser user;
  final BootstrapDriver driver;
  final BootstrapVehicle? vehicle;
  final BootstrapTrip? trip;
  final BootstrapChecklist? checklist;
  final BootstrapCurrentStop? currentStop;
  final List<BootstrapPackage> packages;
  final BootstrapDeliverySession? deliverySession;
  final BootstrapDevice device;

  const DriverBootstrap({
    required this.user,
    required this.driver,
    this.vehicle,
    this.trip,
    this.checklist,
    this.currentStop,
    this.packages = const [],
    this.deliverySession,
    required this.device,
  });

  factory DriverBootstrap.fromJson(Map<String, dynamic> json) {
    return DriverBootstrap(
      user: BootstrapUser.fromJson(json['user'] as Map<String, dynamic>),
      driver:
          BootstrapDriver.fromJson(json['driver'] as Map<String, dynamic>),
      vehicle: json['vehicle'] != null
          ? BootstrapVehicle.fromJson(json['vehicle'] as Map<String, dynamic>)
          : null,
      trip: json['trip'] != null
          ? BootstrapTrip.fromJson(json['trip'] as Map<String, dynamic>)
          : null,
      checklist: json['checklist'] != null
          ? BootstrapChecklist.fromJson(
              json['checklist'] as Map<String, dynamic>)
          : null,
      currentStop: json['currentStop'] != null
          ? BootstrapCurrentStop.fromJson(
              json['currentStop'] as Map<String, dynamic>)
          : null,
      packages: json['packages'] != null
          ? (json['packages'] as List)
              .map((p) =>
                  BootstrapPackage.fromJson(p as Map<String, dynamic>))
              .toList()
          : [],
      deliverySession: json['deliverySession'] != null
          ? BootstrapDeliverySession.fromJson(
              json['deliverySession'] as Map<String, dynamic>)
          : null,
      device: BootstrapDevice.fromJson(json['device'] as Map<String, dynamic>),
    );
  }

  DriverSessionState resolveState() {
    if (trip == null) return DriverSessionState.noTripAssigned;

    switch (trip!.status) {
      case 'programado':
        if (checklist?.status == 'completado') {
          return DriverSessionState.tripReady;
        }
        return DriverSessionState.tripReady;

      case 'pausado':
        return DriverSessionState.paused;

      case 'completado':
      case 'cancelado':
        return DriverSessionState.completed;

      case 'en_curso':
        if (deliverySession != null &&
            deliverySession!.status == 'en_proceso') {
          return DriverSessionState.deliveryInProgress;
        }
        if (currentStop?.status == 'llego') {
          return DriverSessionState.deliveryInProgress;
        }
        return DriverSessionState.tripInProgress;

      default:
        return DriverSessionState.noTripAssigned;
    }
  }
}

class BootstrapUser {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final String companyId;
  final bool active;

  const BootstrapUser({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.role,
    required this.companyId,
    required this.active,
  });

  factory BootstrapUser.fromJson(Map<String, dynamic> json) {
    return BootstrapUser(
      id: (json['id'] ?? json['auth_user_id']) as String,
      name: (json['name'] ?? '') as String,
      email: json['email'] as String?,
      phone: json['telefono'] as String?,
      role: json['rol'] as String? ?? 'Chofer',
      companyId: (json['companyId'] ?? json['empresa_id'] ?? '') as String,
      active: json['active'] as bool? ?? true,
    );
  }
}

class BootstrapDriver {
  final String id;
  final String status;
  final String license;
  final String? phone;
  final String? photoUrl;
  final String? vehicleId;

  const BootstrapDriver({
    required this.id,
    required this.status,
    required this.license,
    this.phone,
    this.photoUrl,
    this.vehicleId,
  });

  factory BootstrapDriver.fromJson(Map<String, dynamic> json) {
    return BootstrapDriver(
      id: json['id'] as String,
      status: (json['status'] ?? json['estado'] ?? 'desconocido') as String,
      license: (json['license'] ?? json['licencia'] ?? '') as String,
      phone: (json['telefono']) as String?,
      photoUrl: json['foto'] as String?,
      vehicleId: json['vehicleId'] as String?,
    );
  }
}

class BootstrapVehicle {
  final String id;
  final String plate;
  final String brand;
  final String model;
  final int? year;

  const BootstrapVehicle({
    required this.id,
    required this.plate,
    required this.brand,
    required this.model,
    this.year,
  });

  factory BootstrapVehicle.fromJson(Map<String, dynamic> json) {
    return BootstrapVehicle(
      id: json['id'] as String,
      plate: (json['plate'] ?? json['matricula'] ?? '') as String,
      brand: (json['brand'] ?? json['marca'] ?? '') as String,
      model: (json['model'] ?? json['modelo'] ?? '') as String,
      year: json['anio'] as int?,
    );
  }
}

class BootstrapTrip {
  final String id;
  final String code;
  final String status;
  final String? departureTime;
  final String? estimatedArrival;
  final double? totalDistance;
  final double? remainingDistance;
  final int? stopsProgress;
  final int? totalStops;
  final int? packagesRemaining;
  final double? progressPercent;

  const BootstrapTrip({
    required this.id,
    required this.code,
    required this.status,
    this.departureTime,
    this.estimatedArrival,
    this.totalDistance,
    this.remainingDistance,
    this.stopsProgress,
    this.totalStops,
    this.packagesRemaining,
    this.progressPercent,
  });

  factory BootstrapTrip.fromJson(Map<String, dynamic> json) {
    return BootstrapTrip(
      id: json['id'] as String,
      code: (json['code'] ?? json['codigo'] ?? '') as String,
      status: (json['status'] ?? json['estado'] ?? 'desconocido') as String,
      departureTime: (json['departureTime'] ?? json['departure_time'])
          as String?,
      estimatedArrival: (json['estimatedArrival'] ?? json['estimated_arrival'])
          as String?,
      totalDistance: (json['totalDistance'] ?? json['total_distance'] as num?)
          ?.toDouble(),
      remainingDistance:
          (json['remainingDistance'] ?? json['remaining_distance'] as num?)
              ?.toDouble(),
      stopsProgress: (json['stopsProgress'] ?? json['stops_progress']) as int?,
      totalStops: (json['totalStops'] ?? json['total_stops']) as int?,
      packagesRemaining:
          (json['packagesRemaining'] ?? json['packages_remaining']) as int?,
      progressPercent:
          (json['progressPercent'] ?? json['progress_percent'] as num?)
              ?.toDouble(),
    );
  }
}

class BootstrapChecklist {
  final String id;
  final String type;
  final String status;
  final int completed;
  final int total;
  final List<BootstrapChecklistItem> items;

  const BootstrapChecklist({
    required this.id,
    required this.type,
    required this.status,
    required this.completed,
    required this.total,
    this.items = const [],
  });

  factory BootstrapChecklist.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List? ?? const [];
    final completedCount = itemsJson.where((i) {
      final m = i as Map<String, dynamic>;
      return (m['status'] ?? m['estado']) == 'ok';
    }).length;

    return BootstrapChecklist(
      id: json['id'] as String,
      type: (json['type'] ?? json['tipo'] ?? '') as String,
      status: (json['status'] ?? json['estado'] ?? 'pendiente') as String,
      completed: json['completed'] as int? ?? completedCount,
      total: json['total'] as int? ?? itemsJson.length,
      items: itemsJson
          .map((i) =>
              BootstrapChecklistItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BootstrapChecklistItem {
  final String id;
  final String name;
  final String category;
  final String status;
  final String? observation;

  const BootstrapChecklistItem({
    required this.id,
    required this.name,
    required this.category,
    required this.status,
    this.observation,
  });

  factory BootstrapChecklistItem.fromJson(Map<String, dynamic> json) {
    return BootstrapChecklistItem(
      id: json['id'] as String,
      name: (json['name'] ?? json['nombre'] ?? '') as String,
      category: (json['category'] ?? json['categoria'] ?? '') as String,
      status: (json['status'] ?? json['estado'] ?? 'pendiente') as String,
      observation: (json['observation'] ?? json['observacion']) as String?,
    );
  }
}

class BootstrapCurrentStop {
  final String id;
  final String? checkpointId;
  final String name;
  final String address;
  final String? customerName;
  final String? status;
  final double? lat;
  final double? lng;
  final int? etaMinutes;
  final double? distanceKm;
  final int? packages;
  final int? order;

  const BootstrapCurrentStop({
    required this.id,
    this.checkpointId,
    required this.name,
    required this.address,
    this.customerName,
    this.status,
    this.lat,
    this.lng,
    this.etaMinutes,
    this.distanceKm,
    this.packages,
    this.order,
  });

  factory BootstrapCurrentStop.fromJson(Map<String, dynamic> json) {
    return BootstrapCurrentStop(
      id: json['id'] as String,
      checkpointId: (json['checkpoint_id'] ?? json['checkpointId']) as String?,
      name: (json['name'] ?? json['nombre'] ?? '') as String,
      address: (json['address'] ?? json['direccion'] ?? '') as String,
      customerName: (json['customer_name'] ?? json['customerName']) as String?,
      status: (json['status'] ?? json['estado']) as String?,
      lat: (json['latitud'] ?? json['lat'] as num?)?.toDouble(),
      lng: (json['longitud'] ?? json['lng'] as num?)?.toDouble(),
      etaMinutes: (json['eta_minutes'] ?? json['etaMinutes']) as int?,
      distanceKm:
          (json['distance_km'] ?? json['distanceKm'] as num?)?.toDouble(),
      packages: (json['packages'] as num?)?.toInt(),
      order: (json['orden'] ?? json['order'] as num?)?.toInt(),
    );
  }
}

class BootstrapPackage {
  final String id;
  final String trackingNumber;
  final String status;

  const BootstrapPackage({
    required this.id,
    required this.trackingNumber,
    required this.status,
  });

  factory BootstrapPackage.fromJson(Map<String, dynamic> json) {
    return BootstrapPackage(
      id: json['id'] as String,
      trackingNumber: json['trackingNumber'] as String,
      status: json['status'] as String,
    );
  }
}

class BootstrapDeliverySession {
  final String id;
  final String currentStep;
  final List<String> scannedPackageIds;
  final bool photoCompleted;
  final bool signatureCompleted;
  final bool otpVerified;
  final String status;

  const BootstrapDeliverySession({
    required this.id,
    required this.currentStep,
    this.scannedPackageIds = const [],
    this.photoCompleted = false,
    this.signatureCompleted = false,
    this.otpVerified = false,
    required this.status,
  });

  factory BootstrapDeliverySession.fromJson(Map<String, dynamic> json) {
    return BootstrapDeliverySession(
      id: json['id'] as String,
      currentStep: json['currentStep'] as String,
      scannedPackageIds: json['scannedPackageIds'] != null
          ? List<String>.from(json['scannedPackageIds'] as List)
          : [],
      photoCompleted: json['photoCompleted'] as bool? ?? false,
      signatureCompleted: json['signatureCompleted'] as bool? ?? false,
      otpVerified: json['otpVerified'] as bool? ?? false,
      status: json['status'] as String,
    );
  }
}

class BootstrapDevice {
  final bool gps;
  final bool internet;
  final bool synced;

  const BootstrapDevice({
    this.gps = true,
    this.internet = true,
    this.synced = true,
  });

  factory BootstrapDevice.fromJson(Map<String, dynamic> json) {
    return BootstrapDevice(
      gps: json['gps'] as bool? ?? true,
      internet: json['internet'] as bool? ?? true,
      synced: json['synced'] as bool? ?? true,
    );
  }
}
