import 'package:flutter/material.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';

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
  final String tripCode;
  final String originName;
  final String destinationName;
  final String nextStopName;
  final String nextStopAddress;
  final String customerName;
  final double? distance;
  final int? etaMinutes;
  final DateTime? etaArrivalTime;
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
    this.tripCode = '',
    this.originName = '',
    this.destinationName = '',
    this.nextStopName = '',
    this.nextStopAddress = '',
    this.customerName = '',
    this.distance,
    this.etaMinutes,
    this.etaArrivalTime,
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
    String? tripCode,
    String? originName,
    String? destinationName,
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
      tripCode: tripCode ?? this.tripCode,
      originName: originName ?? this.originName,
      destinationName: destinationName ?? this.destinationName,
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
