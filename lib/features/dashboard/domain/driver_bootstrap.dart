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
  final String role;
  final String companyId;
  final bool active;

  const BootstrapUser({
    required this.id,
    required this.name,
    required this.role,
    required this.companyId,
    required this.active,
  });

  factory BootstrapUser.fromJson(Map<String, dynamic> json) {
    return BootstrapUser(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      companyId: json['companyId'] as String,
      active: json['active'] as bool? ?? true,
    );
  }
}

class BootstrapDriver {
  final String id;
  final String status;
  final String license;
  final String? vehicleId;

  const BootstrapDriver({
    required this.id,
    required this.status,
    required this.license,
    this.vehicleId,
  });

  factory BootstrapDriver.fromJson(Map<String, dynamic> json) {
    return BootstrapDriver(
      id: json['id'] as String,
      status: json['status'] as String,
      license: json['license'] as String,
      vehicleId: json['vehicleId'] as String?,
    );
  }
}

class BootstrapVehicle {
  final String id;
  final String plate;
  final String brand;
  final String model;

  const BootstrapVehicle({
    required this.id,
    required this.plate,
    required this.brand,
    required this.model,
  });

  factory BootstrapVehicle.fromJson(Map<String, dynamic> json) {
    return BootstrapVehicle(
      id: json['id'] as String,
      plate: json['plate'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
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
      code: json['code'] as String,
      status: json['status'] as String,
      departureTime: json['departureTime'] as String?,
      estimatedArrival: json['estimatedArrival'] as String?,
      totalDistance: (json['totalDistance'] as num?)?.toDouble(),
      remainingDistance: (json['remainingDistance'] as num?)?.toDouble(),
      stopsProgress: json['stopsProgress'] as int?,
      totalStops: json['totalStops'] as int?,
      packagesRemaining: json['packagesRemaining'] as int?,
      progressPercent: (json['progressPercent'] as num?)?.toDouble(),
    );
  }
}

class BootstrapChecklist {
  final String id;
  final String status;
  final int completed;
  final int total;
  final List<BootstrapChecklistItem> items;

  const BootstrapChecklist({
    required this.id,
    required this.status,
    required this.completed,
    required this.total,
    this.items = const [],
  });

  factory BootstrapChecklist.fromJson(Map<String, dynamic> json) {
    return BootstrapChecklist(
      id: json['id'] as String,
      status: json['status'] as String,
      completed: json['completed'] as int,
      total: json['total'] as int,
      items: json['items'] != null
          ? (json['items'] as List)
              .map((i) => BootstrapChecklistItem.fromJson(
                  i as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

class BootstrapChecklistItem {
  final String id;
  final String name;
  final String category;
  final String status;

  const BootstrapChecklistItem({
    required this.id,
    required this.name,
    required this.category,
    required this.status,
  });

  factory BootstrapChecklistItem.fromJson(Map<String, dynamic> json) {
    return BootstrapChecklistItem(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      status: json['status'] as String,
    );
  }
}

class BootstrapCurrentStop {
  final String id;
  final String name;
  final String address;
  final String? customerName;
  final String status;
  final int? etaMinutes;
  final double? distanceKm;
  final int? packages;
  final int? order;

  const BootstrapCurrentStop({
    required this.id,
    required this.name,
    required this.address,
    this.customerName,
    required this.status,
    this.etaMinutes,
    this.distanceKm,
    this.packages,
    this.order,
  });

  factory BootstrapCurrentStop.fromJson(Map<String, dynamic> json) {
    return BootstrapCurrentStop(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      customerName: json['customerName'] as String?,
      status: json['status'] as String,
      etaMinutes: json['etaMinutes'] as int?,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      packages: json['packages'] as int?,
      order: json['order'] as int?,
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
