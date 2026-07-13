import 'package:flutter/material.dart';

class AppBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const AppBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
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
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class StopStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const StopStat({
    super.key,
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
                  color: color),
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 10, color: color.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class VDiv extends StatelessWidget {
  final Color color;
  const VDiv({super.key, required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: color);
}

class TripLocationRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const TripLocationRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TripInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const TripInfo({
    super.key,
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
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          label,
          style: TextStyle(
              fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class StatusDot extends StatelessWidget {
  final IconData icon;
  final bool active;

  const StatusDot({super.key, required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.green : Colors.red,
      ),
    );
  }
}

class KPICard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const KPICard({
    super.key,
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
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class ActionDef {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionDef(this.icon, this.label, this.color, this.onTap);
}

class QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.12)),
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
                    color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActivityItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String time;

  const ActivityItem({
    super.key,
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
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class ScrollableColumn extends StatelessWidget {
  final List<Widget> children;
  const ScrollableColumn({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
