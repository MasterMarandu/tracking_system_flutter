import 'package:flutter/material.dart';

// --- MODELS (Separación de lógica y UI) ---
enum TripState { notStarted, inProgress, paused, completed }

class TripData {
  final String driverName;
  final String nextStopName;
  final String nextStopAddress;
  final double distance;
  final int etaMinutes;
  final int packages;
  final int stopsProgress;
  final int totalStops;
  final double progressPercent;

  TripData({
    required this.driverName,
    required this.nextStopName,
    required this.nextStopAddress,
    required this.distance,
    required this.etaMinutes,
    required this.packages,
    required this.stopsProgress,
    required this.totalStops,
    required this.progressPercent,
  });
}

// --- MAIN SCREEN ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TripState _tripState = TripState.inProgress;

  // Simulando datos que vendrían de un BLoC o Provider
  final TripData _currentTrip = TripData(
    driverName: 'Carlos Mendoza',
    nextStopName: 'Warehouse B - Zona Norte',
    nextStopAddress: 'Av. Principal 456, Distrito Industrial',
    distance: 4.2,
    etaMinutes: 12,
    packages: 5,
    stopsProgress: 3,
    totalStops: 8,
    progressPercent: 0.65,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // SafeArea evita que el contenido choque con el notch/isla dinámica
      body: SafeArea(
        child: Column(
          children: [
            // El Status Bar debería estar dentro de un widget que maneje colores dinámicos
            const _OperationStatusBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context)),
                    SliverToBoxAdapter(child: _buildNextStopCard(context)),
                    SliverToBoxAdapter(child: _buildTripProgress(context)),
                    SliverToBoxAdapter(child: _buildPrimaryAction(context)),
                    SliverToBoxAdapter(child: _buildQuickActions(context)),
                    SliverToBoxAdapter(child: _buildKPIs(context)),
                    SliverToBoxAdapter(child: _buildRecentActivity(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshData() async =>
      await Future.delayed(const Duration(seconds: 1));

  // ==================== COMPONENTS ====================

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              _currentTrip.driverName[0],
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buenos días',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _currentTrip.driverName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () {},
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined),
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

  Widget _buildNextStopCard(BuildContext context) {
    if (_tripState == TripState.completed ||
        _tripState == TripState.notStarted) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Badge(
                    label: 'PRÓXIMA PARADA',
                    icon: Icons.near_me,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _Badge(
                    label: 'EN RUTA',
                    icon: Icons.check_circle,
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    textCol: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _currentTrip.nextStopName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                _currentTrip.nextStopAddress,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _StopStat(
                    icon: Icons.route,
                    value: '${_currentTrip.distance} km',
                    label: 'Distancia',
                    color: Colors.white,
                  ),
                  _VerticalDivider(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.schedule,
                    value: '${_currentTrip.etaMinutes} min',
                    label: 'ETA',
                    color: Colors.white,
                  ),
                  _VerticalDivider(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.inventory_2,
                    value: '${_currentTrip.packages}',
                    label: 'Paquetes',
                    color: Colors.white,
                  ),
                  _VerticalDivider(color: Colors.white.withValues(alpha: 0.2)),
                  _StopStat(
                    icon: Icons.flag,
                    value:
                        '${_currentTrip.stopsProgress}/${_currentTrip.totalStops}',
                    label: 'Paradas',
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation),
                      SizedBox(width: 8),
                      Text(
                        'NAVEGAR',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripProgress(BuildContext context) {
    if (_tripState != TripState.inProgress) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TripInfo(label: 'Salida', value: '08:30', icon: Icons.login),
                _TripInfo(
                  label: 'Llegada',
                  value: '14:30',
                  icon: Icons.schedule,
                ),
                _TripInfo(
                  label: 'Recorrido',
                  value: '45.2 km',
                  icon: Icons.straighten,
                ),
                _TripInfo(
                  label: 'Restante',
                  value: '18.6 km',
                  icon: Icons.route,
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _currentTrip.progressPercent,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_currentTrip.progressPercent * 100).toInt()}% completado',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${_currentTrip.stopsProgress} de ${_currentTrip.totalStops} paradas',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: _PrimaryActionButton(
        state: _tripState,
        theme: theme,
        onTap: () {
          setState(() => _tripState = TripState.completed);
        },
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.qr_code_scanner,
              label: 'Escanear',
              color: Colors.blue,
              onTap: () {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickAction(
              icon: Icons.report_outlined,
              label: 'Incidencia',
              color: Colors.orange,
              onTap: () {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickAction(
              icon: Icons.phone,
              label: 'Soporte',
              color: Colors.green,
              onTap: () {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickAction(
              icon: Icons.checklist,
              label: 'Checklist',
              color: Colors.purple,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIs(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del día',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Uso de GridView para evitar overflow en pantallas pequeñas
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85, // Ajuste para que quepan los textos
            children: [
              _KPICard(
                value: '24',
                label: 'Paq.',
                color: theme.colorScheme.primary,
              ),
              _KPICard(value: '18', label: 'Entr.', color: Colors.green),
              _KPICard(value: '6', label: 'Pend.', color: Colors.orange),
              _KPICard(value: '1', label: 'Incid.', color: Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Actividad reciente',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
            icon: Icons.warning,
            iconColor: Colors.orange,
            title: 'Incidencia reportada',
            subtitle: 'TRK-2024-0890 - Cliente ausente',
            time: 'Hace 1h',
          ),
        ],
      ),
    );
  }
}

// --- SUB-WIDGETS (Reutilizables y Limpios) ---

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color textCol;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
    this.textCol = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textCol),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textCol,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StopStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final Color color;
  const _VerticalDivider({required this.color});
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: color);
}

class _TripInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _TripInfo({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _KPICard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final TripState state;
  final ThemeData theme;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.state,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case TripState.notStarted:
        return ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.play_arrow),
          label: const Text('INICIAR VIAJE'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      case TripState.inProgress:
        return ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.check_circle),
          label: const Text('LLEGUÉ AL DESTINO'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      case TripState.paused:
        return ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.play_arrow),
          label: const Text('REANUDAR VIAJE'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      case TripState.completed:
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'VIAJE COMPLETADO',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
    }
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// Placeholder para el status bar
class _OperationStatusBar extends StatelessWidget {
  const _OperationStatusBar();
  @override
  Widget build(BuildContext context) =>
      Container(height: 30, color: Colors.transparent);
}
