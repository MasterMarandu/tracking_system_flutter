import 'package:flutter/material.dart';
import 'package:tracking_system_app/core/theme/app_colors.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';

/// Cabecera verde del dashboard del conductor:
/// - Fila de estado (GPS / Red / Sinc.), batería y badge del estado del viaje.
/// - Saludo + avatar + nombre del conductor + campana de notificaciones.
/// Los banners de alerta (sin señal / GPS off / pendientes) se muestran encima.
class OperationStatusBar extends StatelessWidget {
  final DeviceStatus status;
  final bool isDark;
  final TripState tripState;
  final int pendingSyncCount;

  /// Nombre del conductor para el saludo. Si viene vacío, se omite el bloque.
  final String driverName;

  /// Callback opcional para la campana de notificaciones.
  final VoidCallback? onNotifications;

  const OperationStatusBar({
    super.key,
    required this.status,
    required this.isDark,
    required this.tripState,
    this.pendingSyncCount = 0,
    this.driverName = '',
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 18
            ? 'Buenas tardes'
            : 'Buenas noches';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AlertBanner(
          internet: status.internet,
          gps: status.gps,
          pendingSyncCount: pendingSyncCount,
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primaryLight],
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 20),
          child: Column(
            children: [
              // ── Fila de estado del dispositivo ──
              Row(
                children: [
                  _StatusChip(label: 'GPS', active: status.gps),
                  const SizedBox(width: 14),
                  _StatusChip(label: 'Red', active: status.internet),
                  const SizedBox(width: 14),
                  _StatusChip(label: 'Sinc.', active: status.synced),
                  const Spacer(),
                  _BatteryIndicator(percent: status.batteryPercent),
                  const SizedBox(width: 12),
                  _TripStateBadge(tripState: tripState),
                ],
              ),
              const SizedBox(height: 16),
              // ── Saludo + avatar + nombre + campana ──
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.45),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      driverName.isNotEmpty
                          ? driverName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        Text(
                          driverName.isNotEmpty ? driverName : 'Conductor',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _NotificationBell(onTap: onNotifications),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Banner de alerta condicional (sin señal / GPS off / pendientes de sync).
class _AlertBanner extends StatelessWidget {
  final bool internet;
  final bool gps;
  final int pendingSyncCount;

  const _AlertBanner({
    required this.internet,
    required this.gps,
    required this.pendingSyncCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!internet) {
      return _bannerRow(
        color: AppColors.error,
        icon: Icons.cloud_off,
        text: pendingSyncCount > 0
            ? 'SIN SEÑAL · Viaje en dispositivo · $pendingSyncCount pendiente${pendingSyncCount == 1 ? '' : 's'}'
            : 'SIN SEÑAL · Usando viaje y paquetes en dispositivo',
        textColor: Colors.white,
      );
    }
    if (!gps) {
      return _bannerRow(
        color: AppColors.accent,
        icon: Icons.gps_off,
        text: 'GPS DESACTIVADO · Actívalo para el tracking en tiempo real',
        textColor: Colors.white,
      );
    }
    if (pendingSyncCount > 0) {
      return _bannerRow(
        color: AppColors.amber,
        icon: Icons.sync_problem,
        text: '$pendingSyncCount CAMBIOS PENDIENTES DE SINCRONIZAR',
        textColor: Colors.white,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _bannerRow({
    required Color color,
    required IconData icon,
    required String text,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      color: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 15),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto + etiqueta de estado (GPS/Red/Sinc.) sobre el header verde.
class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  const _StatusChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final dotColor = active ? const Color(0xFF7DECC0) : const Color(0xFFFF8A80);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(color: dotColor.withValues(alpha: 0.6), blurRadius: 5),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final int percent;
  const _BatteryIndicator({required this.percent});

  @override
  Widget build(BuildContext context) {
    final low = percent <= 20;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          low
              ? Icons.battery_alert
              : percent > 60
                  ? Icons.battery_full
                  : percent > 30
                      ? Icons.battery_5_bar
                      : Icons.battery_3_bar,
          size: 17,
          color: low ? const Color(0xFFFF8A80) : Colors.white,
        ),
        const SizedBox(width: 4),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: low ? const Color(0xFFFF8A80) : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _TripStateBadge extends StatelessWidget {
  final TripState tripState;
  const _TripStateBadge({required this.tripState});

  @override
  Widget build(BuildContext context) {
    String label;
    switch (tripState) {
      case TripState.noTrip:
        label = 'Disponible';
      case TripState.preTrip:
        label = 'Pre-viaje';
      case TripState.inRoute:
        label = 'En ruta';
      case TripState.geofenceEntry:
        label = 'En destino';
      case TripState.delivering:
        label = 'Entregando';
      case TripState.completed:
        label = 'Completado';
      case TripState.paused:
        label = 'Pausado';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final VoidCallback? onTap;
  const _NotificationBell({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.notifications_none, color: Colors.white),
          iconSize: 26,
          splashRadius: 22,
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryDark, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
