import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/notifications/data/notification_service.dart';
import 'package:tracking_system_app/features/notifications/domain/app_notification.dart';

class NotificationsPagedNotifier
    extends Notifier<PagedListState<AppNotification>> {
  final Set<String> _locallyRead = {};

  @override
  PagedListState<AppNotification> build() {
    ref.watch(bootstrapProvider);
    Future(() => refresh());
    return const PagedListState<AppNotification>();
  }

  Future<void> refresh() async {
    state = state.copyWith(
      isInitialLoading: true,
      isLoadingMore: false,
      items: [],
      nextPage: 0,
      hasMore: true,
      clearError: true,
    );
    await _load(0, replace: true);
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isInitialLoading || !state.hasMore) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    await _load(state.nextPage, replace: false);
  }

  Future<void> markRead(AppNotification n) async {
    _locallyRead.add(n.id);
    await NotificationService.instance.markAsRead(n);
    state = state.copyWith(
      items: state.items
          .map((x) => x.id == n.id ? x.copyWith(isRead: true) : x)
          .toList(),
    );
  }

  Future<void> markAllRead() async {
    for (final n in state.items) {
      _locallyRead.add(n.id);
    }
    final bootstrap = ref.read(bootstrapProvider).valueOrNull;
    final userId = bootstrap?.user.id;
    if (userId != null && userId.isNotEmpty) {
      await NotificationService.instance.markAllCommsAsRead(userId);
    }
    state = state.copyWith(
      items: state.items.map((x) => x.copyWith(isRead: true)).toList(),
    );
  }

  Future<void> _load(int page, {required bool replace}) async {
    try {
      final result = await NotificationService.instance.fetchPage(
        page: page,
        pageSize: AppConstants.notificationsPageSize,
      );

      final items = result.items
          .map(
            (n) => _locallyRead.contains(n.id) ? n.copyWith(isRead: true) : n,
          )
          .toList();

      const maxInMemory = AppConstants.notificationsPageSize * 8;
      final merged = replace ? items : [...state.items, ...items];
      // Dedup
      final byId = <String, AppNotification>{};
      for (final n in merged) {
        byId[n.id] = n;
      }
      var list = byId.values.toList()
        ..sort((a, b) => b.time.compareTo(a.time));
      if (list.length > maxInMemory) {
        list = list.sublist(0, maxInMemory);
      }

      state = state.copyWith(
        items: list,
        nextPage: page + 1,
        hasMore: result.hasMore,
        isInitialLoading: false,
        isLoadingMore: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isInitialLoading: false,
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }
}

final notificationsPagedProvider = NotifierProvider<
    NotificationsPagedNotifier, PagedListState<AppNotification>>(
  NotificationsPagedNotifier.new,
);
