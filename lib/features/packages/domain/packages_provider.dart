import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/packages/data/package_service.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';

/// Estado paginado de paquetes (memoria acotada).
class PackagesPagedNotifier extends Notifier<PagedListState<Package>> {
  String _search = '';
  PackageStatus? _statusFilter;

  @override
  PagedListState<Package> build() {
    // Reload when session/bootstrap changes
    ref.watch(bootstrapProvider);
    // Fuera del ciclo de build de widgets
    Future(() => refresh());
    return const PagedListState<Package>();
  }

  String get search => _search;
  PackageStatus? get statusFilter => _statusFilter;

  Future<void> refresh({String? search, PackageStatus? statusFilter}) async {
    if (search != null) _search = search;
    if (statusFilter != null || statusFilter == null && search != null) {
      // allow explicit clear via setStatusFilter
    }
    state = state.copyWith(
      isInitialLoading: true,
      isLoadingMore: false,
      clearError: true,
      items: [],
      nextPage: 0,
      hasMore: true,
    );
    await _loadPage(0, replace: true);
  }

  void setSearch(String value) {
    _search = value;
  }

  void setStatusFilter(PackageStatus? filter) {
    _statusFilter = filter;
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isInitialLoading || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(state.nextPage, replace: false);
  }

  Future<void> _loadPage(int page, {required bool replace}) async {
    try {
      final bootstrap = ref.read(bootstrapProvider).valueOrNull;
      final tripId = bootstrap?.trip?.id ?? '';

      var result = tripId.isNotEmpty
          ? await PackageService.instance.fetchPackagesForTripPage(
              tripId,
              page: page,
              pageSize: AppConstants.packagesPageSize,
              search: _search.isEmpty ? null : _search,
            )
          : await PackageService.instance.fetchEmpresaPackagesPage(
              page: page,
              pageSize: AppConstants.packagesPageSize,
              search: _search.isEmpty ? null : _search,
            );

      // Offline sin snapshot de paquetes: usar lista del bootstrap
      if (result.items.isEmpty &&
          page == 0 &&
          bootstrap != null &&
          bootstrap.packages.isNotEmpty) {
        result = PageResult(
          items: bootstrap.packages
              .map(
                (bp) => Package(
                  id: bp.id,
                  trackingNumber: bp.trackingNumber,
                  recipientName: bp.recipientName,
                  status: _statusFromBootstrap(bp.status),
                  priority: PackagePriority.normal,
                  weight: bp.weight ?? '—',
                ),
              )
              .toList(),
          page: 0,
          pageSize: AppConstants.packagesPageSize,
          hasMore: false,
          total: bootstrap.packages.length,
        );
      }

      var items = result.items;
      if (_statusFilter != null) {
        items = items.where((p) => p.status == _statusFilter).toList();
      }

      const maxInMemory = AppConstants.packagesPageSize * 10;
      final merged = replace ? items : [...state.items, ...items];
      final capped = merged.length > maxInMemory
          ? merged.sublist(merged.length - maxInMemory)
          : merged;

      state = state.copyWith(
        items: capped,
        nextPage: page + 1,
        hasMore: result.hasMore,
        isInitialLoading: false,
        isLoadingMore: false,
        total: result.total,
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

  PackageStatus _statusFromBootstrap(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('entreg') || s == 'delivered') {
      return PackageStatus.delivered;
    }
    if (s.contains('ruta') ||
        s.contains('transit') ||
        s == 'intransit' ||
        s == 'in_transit') {
      return PackageStatus.inTransit;
    }
    return PackageStatus.pending;
  }
}

final packagesPagedProvider =
    NotifierProvider<PackagesPagedNotifier, PagedListState<Package>>(
  PackagesPagedNotifier.new,
);

/// Compat: primera página (detalle / router).
final packagesProvider = FutureProvider<List<Package>>((ref) async {
  ref.watch(bootstrapProvider);
  final bootstrap = ref.watch(bootstrapProvider).valueOrNull;
  final tripId = bootstrap?.trip?.id;
  if (tripId != null && tripId.isNotEmpty) {
    final page = await PackageService.instance.fetchPackagesForTripPage(
      tripId,
      page: 0,
    );
    if (page.items.isNotEmpty) return page.items;
  }
  final page = await PackageService.instance.fetchEmpresaPackagesPage(page: 0);
  return page.items;
});
