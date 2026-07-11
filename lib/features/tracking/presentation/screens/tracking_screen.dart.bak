import 'package:flutter/material.dart';
import 'package:tracking_system_app/core/widgets/status_bar.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  bool _showTraffic = false;
  double _sheetSize = 0.35;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ==================== FULL SCREEN MAP ====================
          _buildMap(context),

          // ==================== STATUS BAR OVERLAY ====================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white.withValues(alpha: 0.9),
              child: const OperationStatusBar(
                gpsStatus: GpsStatus.active,
                connectionStatus: ConnectionStatus.online,
                batteryStatus: BatteryStatus.full,
                batteryPercent: 85,
                gpsAccuracy: 8,
              ),
            ),
          ),

          // ==================== SEARCH BAR ====================
          Positioned(
            top: MediaQuery.of(context).padding.top + 40,
            left: 16,
            right: 16,
            child: _buildSearchBar(context),
          ),

          // ==================== MAP CONTROLS ====================
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 100,
            child: Column(
              children: [
                _MapButton(icon: Icons.my_location, onTap: () {}),
                const SizedBox(height: 12),
                _MapButton(
                  icon: Icons.traffic,
                  isActive: _showTraffic,
                  onTap: () => setState(() => _showTraffic = !_showTraffic),
                ),
                const SizedBox(height: 12),
                _MapButton(icon: Icons.layers, onTap: () {}),
                const SizedBox(height: 12),
                _MapButton(icon: Icons.zoom_in, onTap: () {}),
                const SizedBox(height: 12),
                _MapButton(icon: Icons.zoom_out, onTap: () {}),
              ],
            ),
          ),

          // ==================== ROUTE INFO OVERLAY ====================
          Positioned(
            top: MediaQuery.of(context).padding.top + 100,
            left: 16,
            child: _buildRouteSummary(context),
          ),

          // ==================== BOTTOM SHEET ====================
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(0),
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),

                    // Next Stop Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on, size: 14, color: Colors.orange),
                                SizedBox(width: 4),
                                Text('PROXIMA PARADA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text('Parada 3 de 8', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),

                    // Stop Details
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Warehouse B - Zona Norte',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Av. Principal 456, Distrito Industrial',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),

                    // Stats Grid
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          Expanded(child: _StatTile(icon: Icons.speed, value: '45', unit: 'km/h', label: 'Velocidad', color: Colors.blue)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatTile(icon: Icons.schedule, value: '12', unit: 'min', label: 'ETA', color: Colors.green)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatTile(icon: Icons.route, value: '4.2', unit: 'km', label: 'Distancia', color: Colors.orange)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatTile(icon: Icons.timer_off, value: '8', unit: 'min', label: 'Detenido', color: Colors.grey)),
                        ],
                      ),
                    ),

                    // Packages Info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.inventory_2, color: Colors.blue.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('5 paquetes para esta parada', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                  Text('TRK-2024-0893, TRK-2024-0894...', style: TextStyle(fontSize: 12, color: Colors.blue.shade500)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.blue.shade400),
                          ],
                        ),
                      ),
                    ),

                    // Customer Info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              child: const Text('WH', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Warehouse B', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  Text('Contacto: Pedro Martinez - 999-888-777', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.phone, color: Colors.green),
                              style: IconButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.1)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // GPS Quality
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          _MiniIndicator(icon: Icons.gps_fixed, label: 'GPS', value: 'Excelente', color: Colors.green),
                          const SizedBox(width: 16),
                          _MiniIndicator(icon: Icons.wifi, label: 'Internet', value: 'Online', color: Colors.green),
                          const SizedBox(width: 16),
                          _MiniIndicator(icon: Icons.battery_full, label: 'Bateria', value: '85%', color: Colors.green),
                          const SizedBox(width: 16),
                          _MiniIndicator(icon: Icons.signal_cellular_alt, label: 'Precision', value: '8m', color: Colors.green),
                        ],
                      ),
                    ),

                    // Action Buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Escanear'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.call),
                              label: const Text('Llamar'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Confirmar llegada'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFE8EAED),
      child: CustomPaint(
        painter: _MapPainter(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Map View', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
              Text('Integrate Google Maps or Mapbox', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar tracking, cliente o direccion...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          suffixIcon: IconButton(
            icon: Icon(Icons.mic, color: Colors.grey.shade400),
            onPressed: () {},
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildRouteSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('Origen', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 4),
              const Text('Warehouse A', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(width: 2, height: 12, color: Colors.grey.shade300),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('Destino', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 4),
              const Text('Warehouse B', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RouteMetric(icon: Icons.route, value: '18.6 km'),
              const SizedBox(width: 12),
              _RouteMetric(icon: Icons.schedule, value: '24 min'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.3);
    path.cubicTo(
      size.width * 0.4, size.height * 0.2,
      size.width * 0.6, size.height * 0.5,
      size.width * 0.8, size.height * 0.4,
    );
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..style = PaintingStyle.fill;
    dotPaint.color = Colors.green;
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.3), 8, dotPaint);
    dotPaint.color = Colors.red;
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.4), 8, dotPaint);
    dotPaint.color = Colors.blue;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), 10, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _MapButton({required this.icon, this.isActive = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: isActive ? Colors.white : Colors.grey.shade700, size: 22),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _StatTile({required this.icon, required this.value, required this.unit, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                TextSpan(text: ' $unit', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _MiniIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniIndicator({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
              Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _RouteMetric({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
