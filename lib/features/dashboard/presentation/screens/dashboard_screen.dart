import 'package:flutter/material.dart';
import 'package:tracking_system_app/core/widgets/status_bar.dart';

enum TripState { notStarted, inProgress, paused, completed }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TripState _tripState = TripState.inProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OperationStatusBar(
            gpsStatus: GpsStatus.active,
            connectionStatus: ConnectionStatus.online,
            batteryStatus: BatteryStatus.full,
            batteryPercent: 85,
            gpsAccuracy: 8,
            pendingSyncItems: 3,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  SliverToBoxAdapter(child: _buildNextStopCard(context)),
                  SliverToBoxAdapter(child: _buildTripProgress(context)),
                  SliverToBoxAdapter(child: _buildPrimaryAction(context)),
                  SliverToBoxAdapter(child: _buildQuickActions(context)),
                  SliverToBoxAdapter(child: _buildKPIs(context)),
                  SliverToBoxAdapter(child: _buildRecentActivity(context)),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(seconds: 1));
  }

  // ==================== HEADER ====================
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('C', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const Text(
                  'Carlos Mendoza',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined, size: 26),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos dias';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  // ==================== NEXT STOP (UBER STYLE) ====================
  Widget _buildNextStopCard(BuildContext context) {
    if (_tripState == TripState.completed || _tripState == TripState.notStarted) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.near_me, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('TU PROXIMA PARADA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('EN RUTA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Warehouse B - Zona Norte',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Av. Principal 456, Distrito Industrial',
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _StopStat(icon: Icons.route, value: '4.2 km', label: 'Distancia'),
                  Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.3)),
                  _StopStat(icon: Icons.schedule, value: '12 min', label: 'ETA'),
                  Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.3)),
                  _StopStat(icon: Icons.inventory_2, value: '5', label: 'Paquetes'),
                  Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.3)),
                  _StopStat(icon: Icons.flag, value: '3/8', label: 'Paradas'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.navigation, color: Color(0xFF1565C0)),
                  label: const Text('NAVEGAR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TRIP PROGRESS ====================
  Widget _buildTripProgress(BuildContext context) {
    if (_tripState != TripState.inProgress) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TripInfo(label: 'Salida', value: '08:30', icon: Icons.login),
                _TripInfo(label: 'Llegada ETA', value: '14:30', icon: Icons.schedule),
                _TripInfo(label: 'Recorrido', value: '45.2 km', icon: Icons.straighten),
                _TripInfo(label: 'Restante', value: '18.6 km', icon: Icons.route),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: 0.65,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('65% completado', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text('3 de 8 paradas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PRIMARY ACTION ====================
  Widget _buildPrimaryAction(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: switch (_tripState) {
        TripState.notStarted => SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _tripState = TripState.inProgress),
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('INICIAR VIAJE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: Colors.green.withValues(alpha: 0.4),
              ),
            ),
          ),
        TripState.inProgress => SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.check_circle, size: 28),
              label: const Text('LLEGUE AL DESTINO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
        TripState.paused => SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _tripState = TripState.inProgress),
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('REANUDAR VIAJE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        TripState.completed => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('VIAJE COMPLETADO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ),
      },
    );
  }

  // ==================== QUICK ACTIONS ====================
  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(child: _QuickAction(icon: Icons.qr_code_scanner, label: 'Escanear', color: Colors.blue, onTap: () {})),
          const SizedBox(width: 10),
          Expanded(child: _QuickAction(icon: Icons.report_outlined, label: 'Incidencia', color: Colors.orange, onTap: () {})),
          const SizedBox(width: 10),
          Expanded(child: _QuickAction(icon: Icons.phone, label: 'Supervisor', color: Colors.green, onTap: () {})),
          const SizedBox(width: 10),
          Expanded(child: _QuickAction(icon: Icons.checklist, label: 'Checklist', color: Colors.purple, onTap: () {})),
        ],
      ),
    );
  }

  // ==================== KPIs ====================
  Widget _buildKPIs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen del dia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _KPICard(value: '24', label: 'Paquetes', trend: '+3', trendUp: true, color: Colors.blue)),
              const SizedBox(width: 10),
              Expanded(child: _KPICard(value: '18', label: 'Entregados', percent: 75, color: Colors.green)),
              const SizedBox(width: 10),
              Expanded(child: _KPICard(value: '6', label: 'Pendientes', color: Colors.orange)),
              const SizedBox(width: 10),
              Expanded(child: _KPICard(value: '1', label: 'Incidencia', color: Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _KPICard(value: '63.8', label: 'Km recorridos', color: Colors.teal)),
              const SizedBox(width: 10),
              Expanded(child: _KPICard(value: '5h 20m', label: 'Tiempo activo', color: Colors.indigo)),
              const SizedBox(width: 10),
              Expanded(child: _KPICard(value: '42m', label: 'Detenido', color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== RECENT ACTIVITY ====================
  Widget _buildRecentActivity(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Actividad reciente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () {}, child: const Text('Ver todo')),
            ],
          ),
          _ActivityItem(
            icon: Icons.check_circle,
            iconColor: Colors.green,
            title: 'Entrega completada',
            subtitle: 'TRK-2024-0892 - Maria Garcia',
            time: 'Hace 15 min',
          ),
          _ActivityItem(
            icon: Icons.check_circle,
            iconColor: Colors.green,
            title: 'Entrega completada',
            subtitle: 'TRK-2024-0891 - Juan Perez',
            time: 'Hace 32 min',
          ),
          _ActivityItem(
            icon: Icons.warning,
            iconColor: Colors.orange,
            title: 'Incidencia reportada',
            subtitle: 'TRK-2024-0890 - Cliente ausente',
            time: 'Hace 1h',
          ),
          _ActivityItem(
            icon: Icons.check_circle,
            iconColor: Colors.green,
            title: 'Entrega completada',
            subtitle: 'TRK-2024-0889 - Ana Lopez',
            time: 'Hace 1h 15m',
          ),
        ],
      ),
    );
  }
}

// ==================== HELPER WIDGETS ====================

class _StopStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StopStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TripInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _TripInfo({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String value;
  final String label;
  final String? trend;
  final bool? trendUp;
  final int? percent;
  final Color color;

  const _KPICard({
    required this.value,
    required this.label,
    this.trend,
    this.trendUp,
    this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (trendUp == true ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendUp == true ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 10,
                        color: trendUp == true ? Colors.green : Colors.red,
                      ),
                      Text(
                        trend!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: trendUp == true ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              if (percent != null)
                Text(
                  '$percent%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
