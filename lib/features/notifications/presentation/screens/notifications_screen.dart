import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/notifications/domain/app_notification.dart';
import 'package:tracking_system_app/features/notifications/domain/notifications_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with PagedScrollMixin {
  @override
  void onLoadMoreRequested() {
    ref.read(notificationsPagedProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(notificationsPagedProvider);
    final unreadCount = state.items.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        centerTitle: true,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () async {
                await ref
                    .read(notificationsPagedProvider.notifier)
                    .markAllRead();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Todas marcadas como leídas'),
                  ),
                );
              },
              child: const Text('Leer todas'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(notificationsPagedProvider.notifier).refresh(),
        child: state.isInitialLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : state.error != null && state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: _buildError(theme, state.error!),
                      ),
                    ],
                  )
                : state.items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.55,
                            child: _buildEmptyState(theme),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          if (unreadCount > 0) _buildUnreadBanner(theme, unreadCount),
                          Expanded(
                            child: ListView.separated(
                              controller: pagedScrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: state.items.length + 1,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 72),
                              itemBuilder: (context, index) {
                                if (index >= state.items.length) {
                                  return buildLoadMoreFooter(
                                    isLoadingMore: state.isLoadingMore,
                                    hasMore: state.hasMore,
                                  );
                                }
                                return _buildNotificationTile(
                                  theme,
                                  state.items[index],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildUnreadBanner(ThemeData theme, int unreadCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer,
      child: Text(
        '$unreadCount sin leer',
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
          Icon(
            Icons.notifications_none_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('Sin notificaciones', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Los eventos de tus viajes y entregas aparecerán aquí.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 12),
            const Text('No se pudieron cargar las notificaciones'),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  ref.read(notificationsPagedProvider.notifier).refresh(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(ThemeData theme, AppNotification notification) {
    return InkWell(
      onTap: () async {
        await ref
            .read(notificationsPagedProvider.notifier)
            .markRead(notification);
        if (!mounted) return;
        _showNotificationDetail(theme, notification.copyWith(isRead: true));
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
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return '${time.day}/${time.month}/${time.year}';
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
              Text(notification.message, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
