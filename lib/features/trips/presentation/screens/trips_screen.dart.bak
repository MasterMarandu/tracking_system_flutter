import 'package:flutter/material.dart';

// ==================== MODELS ====================
enum TripStatus { inProgress, completed, scheduled, paused }

class TripData {
  final String code;
  final String origin;
  final String destination;
  final String? destinationDetail;
  final int packages;
  final double? progress;
  final String distance;
  final String eta;
  final String vehicle;
  final String driver;
  final int stops;
  final int completedStops;
  final TripStatus status;

  TripData({
    required this.code,
    required this.origin,
    required this.destination,
    this.destinationDetail,
    required this.packages,
    this.progress,
    required this.distance,
    required this.eta,
    required this.vehicle,
    required this.driver,
    required this.stops,
    required this.completedStops,
    required this.status,
  });
}

// ==================== MAIN SCREEN ====================
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ✅ SIMULACIÓN DE DATA (Debería venir de un Provider/Bloc)
  final List<TripData> activeTrips = [
    TripData(
      code: 'TRP-2024-001',
      origin: 'Warehouse A',
      destination: 'Warehouse B',
      destinationDetail: 'Zona Norte - 3 clientes',
      packages: 12,
      progress: 0.65,
      distance: '18.6 km',
      eta: '2h 30m',
      vehicle: 'ABC-1234 - Ford Transit',
      driver: 'Carlos Mendoza',
      stops: 8,
      completedStops: 3,
      status: TripStatus.inProgress,
    ),
  ];

  final List<TripData> completedTrips = [
    TripData(
      code: 'TRP-2024-002',
      origin: 'Warehouse A',
      destination: 'Centro Logístico Sur',
      packages: 8,
      distance: '25.4 km',
      eta: 'Completado',
      vehicle: 'ABC-1234',
      driver: 'Carlos Mendoza',
      stops: 5,
      completedStops: 5,
      status: TripStatus.completed,
    ),
  ];

  final List<TripData> scheduledTrips = [
    TripData(
      code: 'TRP-2024-004',
      origin: 'Warehouse A',
      destination: 'Zona Residencial Este',
      packages: 10,
      distance: '15.2 km',
      eta: 'Mañana 08:00',
      vehicle: 'ABC-1234',
      driver: 'Carlos Mendoza',
      stops: 6,
      completedStops: 0,
      status: TripStatus.scheduled,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Viajes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: 'Activo'),
            Tab(text: 'Completados'),
            Tab(text: 'Programados'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTripList(activeTrips),
          _buildTripList(completedTrips),
          _buildTripList(scheduledTrips),
        ],
      ),
    );
  }

  Widget _buildTripList(List<TripData> trips) {
    if (trips.isEmpty) {
      return const Center(child: Text('No hay viajes en esta categoría'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return _TripCard(
          trip: trips[index],
          onTap: () {
            // Navegar al detalle del viaje
          },
        );
      },
    );
  }
}

// ==================== COMPONENTS ====================

class _TripCard extends StatelessWidget {
  final TripData trip;
  final VoidCallback? onTap;

  const _TripCard({required this.trip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Generar color base del estado
    final Color statusColor = _getStatusColor(trip.status, theme);

    return Card(
      elevation: 0,
      clipBehavior:
          Clip.antiAlias, // Necesario para que el InkWell respete el borde
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: trip.status == TripStatus.inProgress
            ? BorderSide(color: statusColor.withOpacity(0.5), width: 1.5)
            : BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        // ✅ MEJORA: Feedback táctil (Ripple)
        onTap: onTap,
        child: Column(
          children: [
            // --- HEADER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.code,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(
                    status: trip.status,
                    color: statusColor,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            // --- TIMELINE / DESTINATION ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: IntrinsicHeight(
                // ✅ MEJORA: Altura dinámica para la línea
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Columna de los círculos y la línea
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green, width: 2),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 2,
                            color: theme.colorScheme.outlineVariant,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.red, width: 2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    // Textos descriptivos
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.origin,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            trip.destination,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          if (trip.destinationDetail != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              trip.destinationDetail!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- PROGRESS BAR ---
            if (trip.progress != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: trip.progress,
                        minHeight: 8,
                        backgroundColor: theme.colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(trip.progress! * 100).toInt()}% completado',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${trip.completedStops} de ${trip.stops} paradas',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // --- STATS ROW ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _TripStat(
                    icon: Icons.inventory_2,
                    value: '${trip.packages}',
                    label: 'Paquetes',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _TripStat(
                    icon: Icons.route,
                    value: trip.distance,
                    label: 'Distancia',
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  _TripStat(
                    icon: Icons.schedule,
                    value: trip.eta,
                    label: trip.status == TripStatus.completed
                        ? 'Duración'
                        : 'ETA',
                  ),
                ],
              ),
            ),

            // --- VEHICLE & DRIVER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceVariant.withOpacity(0.3)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trip.vehicle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.person,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trip.driver,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- ACTIONS (BUTTON) ---
            if (trip.status == TripStatus.inProgress ||
                trip.status == TripStatus.scheduled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: onTap,
                  icon: Icon(
                    trip.status == TripStatus.inProgress
                        ? Icons.navigation
                        : Icons.play_arrow,
                    size: 20,
                  ),
                  label: Text(
                    trip.status == TripStatus.inProgress
                        ? 'CONTINUAR VIAJE'
                        : 'INICIAR VIAJE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: trip.status == TripStatus.inProgress
                        ? theme.colorScheme.primary
                        : null,
                    foregroundColor: trip.status == TripStatus.inProgress
                        ? theme.colorScheme.onPrimary
                        : null,
                    minimumSize: const Size.fromHeight(
                      50,
                    ), // ✅ BUG RESUELTO: Evita que el texto se corte
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: trip.status == TripStatus.inProgress ? 2 : 0,
                  ),
                ),
              )
            else
              const SizedBox(height: 16), // Espaciado final si no hay botón
          ],
        ),
      ),
    );
  }

  // Helper para asignar colores según el estado
  Color _getStatusColor(TripStatus status, ThemeData theme) {
    switch (status) {
      case TripStatus.inProgress:
        return theme
            .colorScheme
            .primary; // Usa primary en lugar de Colors.blue fijo
      case TripStatus.completed:
        return Colors.green;
      case TripStatus.scheduled:
        return Colors.orange;
      case TripStatus.paused:
        return Colors.grey;
    }
  }
}

// ==================== SUB-WIDGETS ====================

class _StatusChip extends StatelessWidget {
  final TripStatus status;
  final Color color;
  final bool isDark;

  const _StatusChip({
    required this.status,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    switch (status) {
      case TripStatus.inProgress:
        label = 'En Curso';
        break;
      case TripStatus.completed:
        label = 'Completado';
        break;
      case TripStatus.scheduled:
        label = 'Programado';
        break;
      case TripStatus.paused:
        label = 'Pausado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _TripStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 4),
          FittedBox(
            // ✅ Evita overflow si los textos son muy largos
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
