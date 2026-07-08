import 'package:flutter/material.dart';

enum NotificationType {
  delivery('Delivery', Icons.local_shipping_outlined, Colors.green),
  incident('Incident', Icons.warning_amber, Colors.orange),
  system('System', Icons.settings_outlined, Colors.blue),
  promotion('Promotion', Icons.local_offer_outlined, Colors.purple),
  alert('Alert', Icons.error_outline, Colors.red);

  final String label;
  final IconData icon;
  final Color color;
  const NotificationType(this.label, this.icon, this.color);
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime time;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    this.isRead = false,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _notifications = [
    AppNotification(
      id: '1',
      type: NotificationType.delivery,
      title: 'Package Delivered',
      message: 'Your package PKG-12345 has been delivered successfully to the front door.',
      time: DateTime.now().subtract(const Duration(minutes: 15)),
      isRead: false,
    ),
    AppNotification(
      id: '2',
      type: NotificationType.incident,
      title: 'Delivery Delayed',
      message: 'Package PKG-67890 is experiencing a delay due to weather conditions.',
      time: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: false,
    ),
    AppNotification(
      id: '3',
      type: NotificationType.alert,
      title: 'Action Required',
      message: 'Package PKG-11111 requires a new delivery address. Please update.',
      time: DateTime.now().subtract(const Duration(hours: 3)),
      isRead: false,
    ),
    AppNotification(
      id: '4',
      type: NotificationType.system,
      title: 'App Update Available',
      message: 'Version 2.5.0 is now available with improved tracking features.',
      time: DateTime.now().subtract(const Duration(hours: 6)),
      isRead: true,
    ),
    AppNotification(
      id: '5',
      type: NotificationType.delivery,
      title: 'Out for Delivery',
      message: 'Package PKG-99999 is out for delivery. Expected by 5:00 PM.',
      time: DateTime.now().subtract(const Duration(hours: 8)),
      isRead: true,
    ),
    AppNotification(
      id: '6',
      type: NotificationType.promotion,
      title: 'Free Delivery Weekend',
      message: 'Enjoy free delivery on all orders this weekend! Use code FREEWEEKEND.',
      time: DateTime.now().subtract(const Duration(days: 1)),
      isRead: true,
    ),
    AppNotification(
      id: '7',
      type: NotificationType.incident,
      title: 'Incident Resolved',
      message: 'Incident INC-003 regarding wrong address has been resolved.',
      time: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
      isRead: true,
    ),
    AppNotification(
      id: '8',
      type: NotificationType.system,
      title: 'Profile Incomplete',
      message: 'Please complete your driver profile to continue accepting deliveries.',
      time: DateTime.now().subtract(const Duration(days: 2)),
      isRead: true,
    ),
  ];

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? _buildEmptyState(theme)
          : Column(
              children: [
                if (_unreadCount > 0) _buildUnreadBanner(theme),
                Expanded(
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      return _buildNotificationTile(
                        theme,
                        _notifications[index],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUnreadBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer,
      child: Text(
        '$_unreadCount unread notification${_unreadCount > 1 ? 's' : ''}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_outlined,
              size: 64, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('No notifications', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(ThemeData theme, AppNotification notification) {
    return InkWell(
      onTap: () {
        setState(() => notification.isRead = true);
        _showNotificationDetail(theme, notification);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: notification.isRead
            ? null
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: notification.type.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                notification.type.icon,
                color: notification.type.color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(notification.time),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: notification.type.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          notification.type.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: notification.type.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.month}/${time.day}/${time.year}';
  }

  void _markAllAsRead() {
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notifications marked as read')),
    );
  }

  void _showNotificationDetail(ThemeData theme, AppNotification notification) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: notification.type.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      notification.type.icon,
                      color: notification.type.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatTime(notification.time),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                notification.message,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Dismiss'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
