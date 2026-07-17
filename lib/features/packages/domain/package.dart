import 'package:flutter/material.dart';

enum PackageStatus { pending, inTransit, delivered }

enum PackagePriority { urgent, high, normal, low }

class Package {
  final String id;
  final String trackingNumber;
  final String? recipientName;
  final String? address;
  final PackageStatus status;
  final PackagePriority priority;
  final String weight;
  final String? notes;
  final String? senderName;
  final bool requiresSignature;
  final bool requiresOtp;
  final double? declaredValue;
  final String? type;
  final bool isFragile;
  final DateTime? estimatedDeliveryDate;
  final DateTime? actualDeliveryDate;

  const Package({
    required this.id,
    required this.trackingNumber,
    this.recipientName,
    this.address,
    required this.status,
    required this.priority,
    required this.weight,
    this.notes,
    this.senderName,
    this.requiresSignature = false,
    this.requiresOtp = false,
    this.declaredValue,
    this.type,
    this.isFragile = false,
    this.estimatedDeliveryDate,
    this.actualDeliveryDate,
  });

  Package copyWith({
    PackageStatus? status,
    DateTime? actualDeliveryDate,
    String? recipientName,
    String? notes,
  }) {
    return Package(
      id: id,
      trackingNumber: trackingNumber,
      recipientName: recipientName ?? this.recipientName,
      address: address,
      status: status ?? this.status,
      priority: priority,
      weight: weight,
      notes: notes ?? this.notes,
      senderName: senderName,
      requiresSignature: requiresSignature,
      requiresOtp: requiresOtp,
      declaredValue: declaredValue,
      type: type,
      isFragile: isFragile,
      estimatedDeliveryDate: estimatedDeliveryDate,
      actualDeliveryDate: actualDeliveryDate ?? this.actualDeliveryDate,
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'trackingNumber': trackingNumber,
        'recipientName': recipientName,
        'address': address,
        'status': status.name,
        'priority': priority.name,
        'weight': weight,
        'notes': notes,
        'senderName': senderName,
        'requiresSignature': requiresSignature,
        'requiresOtp': requiresOtp,
        'declaredValue': declaredValue,
        'type': type,
        'isFragile': isFragile,
        'estimatedDeliveryDate': estimatedDeliveryDate?.toIso8601String(),
        'actualDeliveryDate': actualDeliveryDate?.toIso8601String(),
      };

  factory Package.fromCacheJson(Map<String, dynamic> json) {
    PackageStatus status;
    final s = (json['status'] as String?) ?? 'pending';
    status = PackageStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PackageStatus.pending,
    );
    PackagePriority priority;
    final p = (json['priority'] as String?) ?? 'normal';
    priority = PackagePriority.values.firstWhere(
      (e) => e.name == p,
      orElse: () => PackagePriority.normal,
    );
    return Package(
      id: json['id'] as String,
      trackingNumber: (json['trackingNumber'] as String?) ?? '',
      recipientName: json['recipientName'] as String?,
      address: json['address'] as String?,
      status: status,
      priority: priority,
      weight: (json['weight'] as String?) ?? '—',
      notes: json['notes'] as String?,
      senderName: json['senderName'] as String?,
      requiresSignature: json['requiresSignature'] as bool? ?? false,
      requiresOtp: json['requiresOtp'] as bool? ?? false,
      declaredValue: (json['declaredValue'] as num?)?.toDouble(),
      type: json['type'] as String?,
      isFragile: json['isFragile'] as bool? ?? false,
      estimatedDeliveryDate: json['estimatedDeliveryDate'] != null
          ? DateTime.tryParse(json['estimatedDeliveryDate'] as String)
          : null,
      actualDeliveryDate: json['actualDeliveryDate'] != null
          ? DateTime.tryParse(json['actualDeliveryDate'] as String)
          : null,
    );
  }
}

extension PackageStatusUI on PackageStatus {
  String get label {
    switch (this) {
      case PackageStatus.pending:
        return 'Pendiente';
      case PackageStatus.inTransit:
        return 'En tránsito';
      case PackageStatus.delivered:
        return 'Entregado';
    }
  }

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (this) {
      case PackageStatus.pending:
        return Colors.orange;
      case PackageStatus.inTransit:
        return scheme.primary;
      case PackageStatus.delivered:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case PackageStatus.pending:
        return Icons.schedule;
      case PackageStatus.inTransit:
        return Icons.local_shipping;
      case PackageStatus.delivered:
        return Icons.check_circle;
    }
  }
}

extension PackagePriorityUI on PackagePriority {
  String get label {
    switch (this) {
      case PackagePriority.urgent:
        return 'Urgente';
      case PackagePriority.high:
        return 'Alta';
      case PackagePriority.normal:
        return 'Normal';
      case PackagePriority.low:
        return 'Baja';
    }
  }

  Color get color {
    switch (this) {
      case PackagePriority.urgent:
        return Colors.red;
      case PackagePriority.high:
        return Colors.orange;
      case PackagePriority.normal:
        return Colors.blue;
      case PackagePriority.low:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case PackagePriority.urgent:
        return Icons.priority_high;
      case PackagePriority.high:
        return Icons.arrow_upward;
      case PackagePriority.normal:
        return Icons.remove;
      case PackagePriority.low:
        return Icons.arrow_downward;
    }
  }
}
