import 'package:flutter/material.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/common_widgets.dart';

class OperationStatusBar extends StatelessWidget {
  final DeviceStatus status;
  final bool isDark;
  final TripState tripState;
  final int pendingSyncCount;

  const OperationStatusBar({
    super.key,
    required this.status,
    required this.isDark,
    required this.tripState,
    this.pendingSyncCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!status.internet)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.red.withValues(alpha: 0.85),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                    'MODO OFFLINE - Los datos se sincronizarán al reconectar',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else if (!status.gps)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.orange.withValues(alpha: 0.85),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gps_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                    'GPS DESACTIVADO - Activa el GPS para tracking en tiempo real',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else if (pendingSyncCount > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.amber.withValues(alpha: 0.85),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_problem, color: Colors.black87, size: 16),
                const SizedBox(width: 8),
                Text(
                  '$pendingSyncCount CAMBIOS PENDIENTES DE SINCRONIZAR',
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(
                color: theme.dividerTheme.color ?? Colors.grey.shade200,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              StatusDot(
                icon: Icons.gps_fixed,
                active: status.gps,
              ),
              const SizedBox(width: 6),
              Text('GPS',
                  style: TextStyle(
                      fontSize: 11,
                      color: status.gps ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              StatusDot(
                icon: Icons.wifi,
                active: status.internet,
              ),
              const SizedBox(width: 6),
              Text('Red',
                  style: TextStyle(
                      fontSize: 11,
                      color: status.internet ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              StatusDot(
                icon: Icons.sync,
                active: status.synced,
              ),
              const SizedBox(width: 6),
              Text('Sync',
                  style: TextStyle(
                      fontSize: 11,
                      color: status.synced ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (status.batteryPercent <= 20) ...[
                const Icon(Icons.battery_alert,
                    color: Colors.red, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Batería baja',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ] else ...[
                Icon(
                  status.batteryPercent > 60
                      ? Icons.battery_full
                      : status.batteryPercent > 30
                          ? Icons.battery_5_bar
                          : Icons.battery_3_bar,
                  size: 18,
                  color: status.batteryPercent > 60
                      ? Colors.green
                      : status.batteryPercent > 30
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '${status.batteryPercent}%',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(width: 16),
              _tripStateBadge(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tripStateBadge() {
    String label;
    Color color;
    switch (tripState) {
      case TripState.noTrip:
        label = 'Disponible';
        color = Colors.teal;
      case TripState.preTrip:
        label = 'Pre-viaje';
        color = Colors.grey;
      case TripState.inRoute:
        label = 'En ruta';
        color = const Color(0xFF206B5C);
      case TripState.geofenceEntry:
        label = 'En destino';
        color = Colors.orange;
      case TripState.delivering:
        label = 'Entregando';
        color = Colors.purple;
      case TripState.completed:
        label = 'Completado';
        color = Colors.green;
      case TripState.paused:
        label = 'Pausado';
        color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
