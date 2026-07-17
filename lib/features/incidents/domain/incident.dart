import 'package:flutter/material.dart';

/// Tipos alineados al CHECK de `delivery_incidencias.tipo` (trackingV2).
enum IncidentType {
  retraso('retraso', 'Retraso', Icons.access_time),
  danoPaquete('dano_paquete', 'Daño de paquete', Icons.broken_image_outlined),
  paqueteExtraviado('paquete_extraviado', 'Paquete extraviado', Icons.warning_amber),
  direccionIncorrecta(
    'direccion_incorrecta',
    'Dirección incorrecta',
    Icons.location_off_outlined,
  ),
  destinatarioAusente(
    'destinatario_ausente',
    'Destinatario ausente',
    Icons.person_off_outlined,
  ),
  rechazado('rechazado', 'Rechazado', Icons.block),
  accesoRestringido(
    'acceso_restringido',
    'Acceso restringido',
    Icons.lock_outline,
  ),
  climaAdverso('clima_adverso', 'Clima adverso', Icons.cloud_queue),
  averiaVehiculo('averia_vehiculo', 'Avería vehículo', Icons.car_crash_outlined),
  otra('otra', 'Otra', Icons.more_horiz);

  final String dbCode;
  final String label;
  final IconData icon;
  const IncidentType(this.dbCode, this.label, this.icon);

  static IncidentType fromDb(String? code) {
    final c = (code ?? '').toLowerCase();
    return IncidentType.values.firstWhere(
      (e) => e.dbCode == c,
      orElse: () => IncidentType.otra,
    );
  }
}

enum IncidentStatus {
  abierta('abierta', 'Abierta', Color(0xFFD97706)),
  enProceso('en_proceso', 'En proceso', Color(0xFF1E5F8F)),
  resuelta('resuelta', 'Resuelta', Color(0xFF176351)),
  cerrada('cerrada', 'Cerrada', Color(0xFF6E7B77));

  final String dbCode;
  final String label;
  final Color color;
  const IncidentStatus(this.dbCode, this.label, this.color);

  static IncidentStatus fromDb(String? code) {
    final c = (code ?? 'abierta').toLowerCase();
    return IncidentStatus.values.firstWhere(
      (e) => e.dbCode == c,
      orElse: () => IncidentStatus.abierta,
    );
  }
}

class Incident {
  final String id;
  final IncidentType type;
  final String description;
  final DateTime date;
  final IncidentStatus status;
  final String? packageId;
  final String? packageTracking;
  final String? tripId;
  final String? tripCode;
  final String? fotoUrl;
  final double? lat;
  final double? lng;
  final String? solucion;

  const Incident({
    required this.id,
    required this.type,
    required this.description,
    required this.date,
    required this.status,
    this.packageId,
    this.packageTracking,
    this.tripId,
    this.tripCode,
    this.fotoUrl,
    this.lat,
    this.lng,
    this.solucion,
  });
}
