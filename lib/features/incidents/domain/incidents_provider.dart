import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/incidents/data/incident_service.dart';
import 'package:tracking_system_app/features/incidents/domain/incident.dart';

class IncidentsPagedNotifier extends Notifier<PagedListState<Incident>> {
  @override
  PagedListState<Incident> build() {
    ref.watch(bootstrapProvider);
    Future(() => refresh());
    return const PagedListState<Incident>();
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
    if (state.isLoadingMore || state.isInitialLoading || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _load(state.nextPage, replace: false);
  }

  Future<void> report({
    required IncidentType type,
    required String description,
    String? tripId,
    String? packageId,
    double? lat,
    double? lng,
  }) async {
    final created = await IncidentService.instance.reportIncident(
      type: type,
      description: description,
      tripId: tripId,
      packageId: packageId,
      lat: lat,
      lng: lng,
    );
    state = state.copyWith(
      items: [created, ...state.items],
    );
  }

  Future<void> _load(int page, {required bool replace}) async {
    try {
      final result = await IncidentService.instance.fetchPage(
        page: page,
        pageSize: AppConstants.defaultPageSize,
      );
      const maxInMemory = AppConstants.defaultPageSize * 8;
      final merged = replace ? result.items : [...state.items, ...result.items];
      final byId = <String, Incident>{};
      for (final i in merged) {
        byId[i.id] = i;
      }
      var list = byId.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
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

final incidentsPagedProvider =
    NotifierProvider<IncidentsPagedNotifier, PagedListState<Incident>>(
  IncidentsPagedNotifier.new,
);
