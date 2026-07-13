import 'package:flutter/material.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';

class PackageDetailScreen extends StatelessWidget {
  final Package package;

  const PackageDetailScreen({super.key, required this.package});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(package.trackingNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => debugPrint('Scan pressed'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPackageInfoSection(context),
            const Divider(height: 1),
            _buildSenderRecipientSection(context),
            const Divider(height: 1),
            _buildStatusTimeline(context),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomSheet: _buildBottomActions(context),
    );
  }

  Widget _buildPackageInfoSection(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información del paquete',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Peso',
                  value: package.weight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Tipo',
                  value: package.type ?? 'Estándar',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.flag,
                  label: 'Prioridad',
                  value: package.priority.label,
                  valueColor: package.priority.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  icon: Icons.attach_money,
                  label: 'Valor declarado',
                  value: package.declaredValue != null
                      ? 'S/ ${package.declaredValue!.toStringAsFixed(2)}'
                      : 'N/A',
                ),
              ),
            ],
          ),
          if (package.isFragile) ...[
            const SizedBox(height: 12),
            Chip(
              avatar: const Icon(Icons.warning_amber, size: 16),
              label: const Text('Frágil'),
              backgroundColor: Colors.red.withOpacity(0.1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSenderRecipientSection(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remitente y Destinatario',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _ContactCard(
            icon: Icons.person_outline,
            label: 'Remitente',
            name: package.senderName ?? 'Sin información',
            address: '--',
            phone: '--',
          ),
          const SizedBox(height: 12),
          _ContactCard(
            icon: Icons.person,
            label: 'Destinatario',
            name: package.recipientName ?? 'Sin información',
            address: package.address ?? '--',
            phone: '--',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(BuildContext context) {
    final theme = Theme.of(context);

    // Build timeline from package status
    final isDelivered = package.status == PackageStatus.delivered;
    final isInTransit = package.status == PackageStatus.inTransit;

    final List<_TimelineEntry> timeline = [
      _TimelineEntry(
        status: 'Paquete creado',
        description: 'Tracking: ${package.trackingNumber}',
        isCompleted: true,
      ),
      _TimelineEntry(
        status: 'Asignado a viaje',
        description: 'Listo para entrega',
        isCompleted: true,
      ),
      _TimelineEntry(
        status: 'En ruta',
        description: package.address ?? 'Dirección de destino',
        isCompleted: isInTransit || isDelivered,
      ),
      _TimelineEntry(
        status: 'Entregado',
        description: isDelivered
            ? (package.actualDeliveryDate?.toString() ?? 'Completado')
            : 'Pendiente',
        isCompleted: isDelivered,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado del paquete',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...List.generate(timeline.length, (index) {
            final item = timeline[index];
            final isLast = index == timeline.length - 1;
            return _TimelineItem(
              status: item.status,
              time: item.description,
              isCompleted: item.isCompleted,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    if (package.status == PackageStatus.delivered) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => debugPrint('Report Issue pressed'),
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Reportar incidencia'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => debugPrint('Mark as Delivered pressed'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Marcar entregado'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry {
  final String status;
  final String description;
  final bool isCompleted;

  const _TimelineEntry({
    required this.status,
    required this.description,
    required this.isCompleted,
  });
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.6),
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String name;
  final String address;
  final String phone;

  const _ContactCard({
    required this.icon,
    required this.label,
    required this.name,
    required this.address,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withOpacity(0.6),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (phone != '--') ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone,
                          size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        phone,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                            ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final String status;
  final String time;
  final bool isCompleted;
  final bool isLast;

  const _TimelineItem({
    required this.status,
    required this.time,
    required this.isCompleted,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final mutedColor =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.4);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted ? primaryColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCompleted ? primaryColor : mutedColor,
                    width: 2,
                  ),
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted ? primaryColor : mutedColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? null : mutedColor,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCompleted
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6)
                              : mutedColor,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
