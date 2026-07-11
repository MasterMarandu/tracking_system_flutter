import 'package:flutter/material.dart';

enum StopStatus { completed, inProgress, pending }

class TripDetailScreen extends StatelessWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  static const _tripCode = 'TRP-2024-001';
  static const _origin = 'New York, NY';
  static const _destination = 'Boston, MA';
  static const _distance = '215 mi';
  static const _duration = '4h 30m';
  static const _packageCount = 12;

  static const _stops = <_StopData>[
    _StopData(name: 'NYC Distribution Center', address: '123 Main St, New York', status: StopStatus.completed),
    _StopData(name: 'Hartford Warehouse', address: '456 Oak Ave, Hartford, CT', status: StopStatus.completed),
    _StopData(name: 'Springfield Depot', address: '789 Elm St, Springfield, MA', status: StopStatus.inProgress),
    _StopData(name: 'Worcester Hub', address: '321 Pine Rd, Worcester, MA', status: StopStatus.pending),
    _StopData(name: 'Boston Terminal', address: '650 Atlantic Ave, Boston, MA', status: StopStatus.pending),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tripCode),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _RouteCard(origin: _origin, destination: _destination),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _StatsRow(
                    distance: _distance,
                    duration: _duration,
                    packageCount: _packageCount,
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Stops',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_stops.length, (i) {
                    return _StopTile(
                      stop: _stops[i],
                      index: i + 1,
                      isLast: i == _stops.length - 1,
                    );
                  }),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _ActionButtons(colorScheme: colorScheme),
    );
  }
}

class _StopData {
  final String name;
  final String address;
  final StopStatus status;

  const _StopData({
    required this.name,
    required this.address,
    required this.status,
  });
}

class _RouteCard extends StatelessWidget {
  final String origin;
  final String destination;

  const _RouteCard({required this.origin, required this.destination});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Column(
              children: [
                Icon(
                  Icons.circle,
                  size: 14,
                  color: Colors.green.shade600,
                ),
                Container(
                  width: 2,
                  height: 40,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const Icon(Icons.location_on, size: 18, color: Colors.red),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Origin',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    origin,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Destination',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    destination,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final String distance;
  final String duration;
  final int packageCount;

  const _StatsRow({
    required this.distance,
    required this.duration,
    required this.packageCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.route,
            label: 'Distance',
            value: distance,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.access_time_filled,
            label: 'Duration',
            value: duration,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.inventory_2,
            label: 'Packages',
            value: '$packageCount',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 24, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final _StopData stop;
  final int index;
  final bool isLast;

  const _StopTile({
    required this.stop,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (circleColor, icon) = switch (stop.status) {
      StopStatus.completed => (Colors.green, Icons.check as IconData),
      StopStatus.inProgress => (colorScheme.primary, Icons.radio_button_checked as IconData),
      StopStatus.pending => (colorScheme.outline, Icons.circle_outlined as IconData),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stop.status == StopStatus.completed
                        ? Colors.green
                        : stop.status == StopStatus.inProgress
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                    border: stop.status == StopStatus.pending
                        ? Border.all(color: colorScheme.outline)
                        : null,
                  ),
                  child: Center(
                    child: stop.status == StopStatus.completed
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : Text(
                            '$index',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: stop.status == StopStatus.inProgress
                                  ? Colors.white
                                  : colorScheme.onSurface,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: stop.status == StopStatus.completed
                          ? Colors.green.shade300
                          : colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              color: stop.status == StopStatus.inProgress
                  ? colorScheme.primaryContainer.withOpacity(0.4)
                  : colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stop.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _StopStatusBadge(status: stop.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stop.address,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopStatusBadge extends StatelessWidget {
  final StopStatus status;

  const _StopStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StopStatus.completed => ('Done', Colors.green),
      StopStatus.inProgress => ('Current', Theme.of(context).colorScheme.primary),
      StopStatus.pending => ('Pending', Theme.of(context).colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ActionButtons({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start Trip'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.navigation_rounded, size: 20),
                label: const Text('Navigate'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
