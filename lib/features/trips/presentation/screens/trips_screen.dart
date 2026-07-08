import 'package:flutter/material.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
        title: const Text('Mis Viajes'),
        bottom: TabBar(
          controller: _tabController,
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
          _buildActiveTrips(),
          _buildCompletedTrips(),
          _buildScheduledTrips(),
        ],
      ),
    );
  }

  Widget _buildActiveTrips() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TripCard(
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
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildCompletedTrips() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TripCard(
          code: 'TRP-2024-002',
          origin: 'Warehouse A',
          destination: 'Centro Logistico Sur',
          packages: 8,
          distance: '25.4 km',
          eta: 'Completado',
          vehicle: 'ABC-1234',
          driver: 'Carlos Mendoza',
          stops: 5,
          completedStops: 5,
          status: TripStatus.completed,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        _TripCard(
          code: 'TRP-2024-003',
          origin: 'Warehouse B',
          destination: 'Zona Industrial',
          packages: 15,
          distance: '32.1 km',
          eta: 'Completado',
          vehicle: 'XYZ-5678',
          driver: 'Carlos Mendoza',
          stops: 10,
          completedStops: 10,
          status: TripStatus.completed,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildScheduledTrips() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TripCard(
          code: 'TRP-2024-004',
          origin: 'Warehouse A',
          destination: 'Zona Residencial Este',
          packages: 10,
          distance: '15.2 km',
          eta: 'Manana 08:00',
          vehicle: 'ABC-1234',
          driver: 'Carlos Mendoza',
          stops: 6,
          completedStops: 0,
          status: TripStatus.scheduled,
          onTap: () {},
        ),
      ],
    );
  }
}

enum TripStatus { inProgress, completed, scheduled, paused }

class _TripCard extends StatelessWidget {
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
  final VoidCallback? onTap;

  const _TripCard({
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
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: status == TripStatus.inProgress
              ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor)),
                  ),
                  const Spacer(),
                  _StatusChip(status: status),
                ],
              ),
            ),

            // Destination (MAIN FOCUS)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.green, width: 2))),
                      Container(width: 2, height: 24, color: Colors.grey.shade300),
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.red, width: 2))),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(origin, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                        const SizedBox(height: 16),
                        Text(destination, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (destinationDetail != null) ...[
                          const SizedBox(height: 2),
                          Text(destinationDetail!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Progress Bar (if active)
            if (progress != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(progress! * 100).toInt()}% completado', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        Text('$completedStops de $stops paradas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor)),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Stats Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _TripStat(icon: Icons.inventory_2, value: '$packages', label: 'Paquetes'),
                  Container(width: 1, height: 28, color: Colors.grey.shade200),
                  _TripStat(icon: Icons.route, value: distance, label: 'Distancia'),
                  Container(width: 1, height: 28, color: Colors.grey.shade200),
                  _TripStat(icon: Icons.schedule, value: eta, label: status == TripStatus.completed ? 'Duracion' : 'ETA'),
                ],
              ),
            ),

            // Vehicle & Driver
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping, size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text(vehicle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const Spacer(),
                    Icon(Icons.person, size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text(driver, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),

            // Action Button
            if (status == TripStatus.inProgress)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('CONTINUAR VIAJE', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),

            if (status == TripStatus.scheduled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('INICIAR VIAJE', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),

            if (status == TripStatus.completed)
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (status) {
      case TripStatus.inProgress:
        return Colors.blue;
      case TripStatus.completed:
        return Colors.green;
      case TripStatus.scheduled:
        return Colors.orange;
      case TripStatus.paused:
        return Colors.grey;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final TripStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(_label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _color)),
        ],
      ),
    );
  }

  Color get _color {
    switch (status) {
      case TripStatus.inProgress:
        return Colors.blue;
      case TripStatus.completed:
        return Colors.green;
      case TripStatus.scheduled:
        return Colors.orange;
      case TripStatus.paused:
        return Colors.grey;
    }
  }

  String get _label {
    switch (status) {
      case TripStatus.inProgress:
        return 'En Curso';
      case TripStatus.completed:
        return 'Completado';
      case TripStatus.scheduled:
        return 'Programado';
      case TripStatus.paused:
        return 'Pausado';
    }
  }
}

class _TripStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _TripStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
