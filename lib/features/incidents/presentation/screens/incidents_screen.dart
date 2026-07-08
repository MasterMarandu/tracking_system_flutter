import 'package:flutter/material.dart';

enum IncidentType {
  delay('Delay', Icons.access_time),
  damage('Damage', Icons.broken_image_outlined),
  theft('Theft', Icons.warning_amber),
  wrongAddress('Wrong Address', Icons.location_off_outlined),
  weather('Weather', Icons.cloud_queue),
  vehicleBreakdown('Vehicle Breakdown', Icons.car_crash_outlined),
  other('Other', Icons.more_horiz);

  final String label;
  final IconData icon;
  const IncidentType(this.label, this.icon);
}

enum IncidentStatus { open, inProgress, resolved }

class Incident {
  final String id;
  final IncidentType type;
  final String description;
  final DateTime date;
  final IncidentStatus status;
  final String? packageId;

  const Incident({
    required this.id,
    required this.type,
    required this.description,
    required this.date,
    required this.status,
    this.packageId,
  });
}

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  final List<Incident> _incidents = [
    Incident(
      id: 'INC-001',
      type: IncidentType.delay,
      description: 'Package delayed due to traffic congestion on highway.',
      date: DateTime.now().subtract(const Duration(hours: 2)),
      status: IncidentStatus.open,
      packageId: 'PKG-12345',
    ),
    Incident(
      id: 'INC-002',
      type: IncidentType.damage,
      description: 'Box found with visible water damage upon pickup.',
      date: DateTime.now().subtract(const Duration(days: 1)),
      status: IncidentStatus.inProgress,
      packageId: 'PKG-67890',
    ),
    Incident(
      id: 'INC-003',
      type: IncidentType.wrongAddress,
      description: 'Recipient address does not exist. Street name incorrect.',
      date: DateTime.now().subtract(const Duration(days: 2)),
      status: IncidentStatus.resolved,
      packageId: 'PKG-11111',
    ),
    Incident(
      id: 'INC-004',
      type: IncidentType.vehicleBreakdown,
      description: 'Flat tire on delivery vehicle. Assistance requested.',
      date: DateTime.now().subtract(const Duration(days: 3)),
      status: IncidentStatus.resolved,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidents'),
        centerTitle: true,
      ),
      body: _incidents.isEmpty
          ? _buildEmptyState(theme)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _incidents.length,
              itemBuilder: (context, index) {
                return _buildIncidentCard(theme, _incidents[index]);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReportIncidentSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Report'),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('No incidents reported',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('All deliveries are running smoothly',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(ThemeData theme, Incident incident) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primaryContainer,
                  child: Icon(
                    incident.type.icon,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.type.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        incident.id,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(theme, incident.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              incident.description,
              style: theme.textTheme.bodyMedium,
            ),
            if (incident.packageId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    incident.packageId!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _formatDate(incident.date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, IncidentStatus status) {
    final (label, color) = switch (status) {
      IncidentStatus.open => ('Open', Colors.orange),
      IncidentStatus.inProgress => ('In Progress', Colors.blue),
      IncidentStatus.resolved => ('Resolved', Colors.green),
    };

    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _showReportIncidentSheet(BuildContext context) {
    final theme = Theme.of(context);
    IncidentType? selectedType;
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Report Incident',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<IncidentType>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Incident Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: IncidentType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            Icon(type.icon, size: 20),
                            const SizedBox(width: 8),
                            Text(type.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setSheetState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Photo captured')),
                      );
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Add Photo'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                      suffixIcon: Icon(Icons.my_location),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      if (selectedType != null &&
                          descriptionController.text.isNotEmpty) {
                        setState(() {
                          _incidents.insert(
                            0,
                            Incident(
                              id: 'INC-${(_incidents.length + 1).toString().padLeft(3, '0')}',
                              type: selectedType!,
                              description: descriptionController.text,
                              date: DateTime.now(),
                              status: IncidentStatus.open,
                            ),
                          );
                        });
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Incident reported successfully'),
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Submit Report'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
