import 'package:flutter/material.dart';

enum NotificationType {
  delivery('Entrega', Icons.local_shipping_outlined, Color(0xFF176351)),
  incident('Incidencia', Icons.warning_amber, Color(0xFFD97706)),
  system('Sistema', Icons.settings_outlined, Color(0xFF206B5C)),
  trip('Viaje', Icons.route_outlined, Color(0xFF1E5F8F)),
  alert('Alerta', Icons.error_outline, Color(0xFFC74C4C));

  final String label;
  final IconData icon;
  final Color color;
  const NotificationType(this.label, this.icon, this.color);
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime time;
  final String source; // 'evento' | 'notificacion' | 'outbox'
  final String? rawTipo;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    this.source = 'evento',
    this.rawTipo,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      time: time,
      source: source,
      rawTipo: rawTipo,
      isRead: isRead ?? this.isRead,
    );
  }
}
