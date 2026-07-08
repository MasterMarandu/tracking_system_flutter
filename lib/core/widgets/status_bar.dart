import 'package:flutter/material.dart';

enum GpsStatus { active, weak, inactive, searching }
enum ConnectionStatus { online, offline, syncing }
enum BatteryStatus { full, medium, low, critical, charging }

class OperationStatusBar extends StatelessWidget {
  final GpsStatus gpsStatus;
  final ConnectionStatus connectionStatus;
  final BatteryStatus batteryStatus;
  final int batteryPercent;
  final int gpsAccuracy; // meters
  final int pendingSyncItems;
  final VoidCallback? onTapSync;

  const OperationStatusBar({
    super.key,
    this.gpsStatus = GpsStatus.active,
    this.connectionStatus = ConnectionStatus.online,
    this.batteryStatus = BatteryStatus.full,
    this.batteryPercent = 85,
    this.gpsAccuracy = 8,
    this.pendingSyncItems = 0,
    this.onTapSync,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _StatusIndicator(
              icon: _gpsIcon,
              label: _gpsLabel,
              color: _gpsColor,
            ),
            const SizedBox(width: 12),
            _StatusIndicator(
              icon: _connectionIcon,
              label: _connectionLabel,
              color: _connectionColor,
            ),
            const SizedBox(width: 12),
            _StatusIndicator(
              icon: _batteryIcon,
              label: '$batteryPercent%',
              color: _batteryColor,
            ),
            if (pendingSyncItems > 0) ...[
              const Spacer(),
              GestureDetector(
                onTap: onTapSync,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync_problem, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '$pendingSyncItems pending',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const Spacer(),
              _StatusIndicator(
                icon: Icons.check_circle,
                label: 'Synced',
                color: Colors.green,
                isSmall: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData get _gpsIcon {
    switch (gpsStatus) {
      case GpsStatus.active:
        return Icons.gps_fixed;
      case GpsStatus.weak:
        return Icons.gps_not_fixed;
      case GpsStatus.inactive:
        return Icons.gps_off;
      case GpsStatus.searching:
        return Icons.gps_fixed;
    }
  }

  String get _gpsLabel {
    switch (gpsStatus) {
      case GpsStatus.active:
        return '${gpsAccuracy}m';
      case GpsStatus.weak:
        return 'Weak';
      case GpsStatus.inactive:
        return 'Off';
      case GpsStatus.searching:
        return '...';
    }
  }

  Color get _gpsColor {
    switch (gpsStatus) {
      case GpsStatus.active:
        return gpsAccuracy <= 10 ? Colors.green : Colors.orange;
      case GpsStatus.weak:
        return Colors.orange;
      case GpsStatus.inactive:
        return Colors.red;
      case GpsStatus.searching:
        return Colors.grey;
    }
  }

  IconData get _connectionIcon {
    switch (connectionStatus) {
      case ConnectionStatus.online:
        return Icons.wifi;
      case ConnectionStatus.offline:
        return Icons.wifi_off;
      case ConnectionStatus.syncing:
        return Icons.sync;
    }
  }

  String get _connectionLabel {
    switch (connectionStatus) {
      case ConnectionStatus.online:
        return 'Online';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.syncing:
        return 'Syncing';
    }
  }

  Color get _connectionColor {
    switch (connectionStatus) {
      case ConnectionStatus.online:
        return Colors.green;
      case ConnectionStatus.offline:
        return Colors.red;
      case ConnectionStatus.syncing:
        return Colors.blue;
    }
  }

  IconData get _batteryIcon {
    if (batteryStatus == BatteryStatus.charging) return Icons.battery_charging_full;
    if (batteryPercent > 75) return Icons.battery_full;
    if (batteryPercent > 50) return Icons.battery_5_bar;
    if (batteryPercent > 25) return Icons.battery_3_bar;
    if (batteryPercent > 10) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color get _batteryColor {
    if (batteryStatus == BatteryStatus.charging) return Colors.green;
    if (batteryPercent > 50) return Colors.green;
    if (batteryPercent > 20) return Colors.orange;
    return Colors.red;
  }
}

class _StatusIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSmall;

  const _StatusIndicator({
    required this.icon,
    required this.label,
    required this.color,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isSmall ? 12 : 14, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: isSmall ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
