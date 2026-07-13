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
