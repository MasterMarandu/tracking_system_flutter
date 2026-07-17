import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';
import 'package:tracking_system_app/features/packages/domain/packages_provider.dart';

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key});

  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen>
    with PagedScrollMixin {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void onLoadMoreRequested() {
    ref.read(packagesPagedProvider.notifier).loadMore();
  }

  Future<void> _refresh() async {
    await ref.read(packagesPagedProvider.notifier).refresh(
          search: _searchController.text.trim(),
        );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final n = ref.read(packagesPagedProvider.notifier);
      n.setSearch(value.trim());
      n.refresh(search: value.trim());
    });
  }

  void _onFilterSelected(PackageStatus? filter) {
    final n = ref.read(packagesPagedProvider.notifier);
    n.setStatusFilter(filter);
    n.refresh(search: _searchController.text.trim());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(packagesPagedProvider);
    final notifier = ref.read(packagesPagedProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paquetes'),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar paquete',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                notifier.setSearch('');
                notifier.refresh(search: '');
              }
            }),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: state.isInitialLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : state.error != null && state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: _buildErrorState(theme, state.error!),
                      ),
                    ],
                  )
                : state.items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.55,
                            child: _buildEmptyState(
                              theme,
                              'Sin paquetes',
                              'No hay paquetes en el inventario. '
                              'Créalos en Routio web o baja para reintentar.',
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildSearchBar(theme),
                          _buildFilters(theme, state.items, notifier.statusFilter),
                          _buildResultsCount(
                            theme,
                            state.items.length,
                            hasMore: state.hasMore,
                            total: state.total,
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: pagedScrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: state.items.length + 1,
                              itemBuilder: (context, index) {
                                if (index >= state.items.length) {
                                  return buildLoadMoreFooter(
                                    isLoadingMore: state.isLoadingMore,
                                    hasMore: state.hasMore,
                                  );
                                }
                                final package = state.items[index];
                                return _PackageCard(
                                  package: package,
                                  onTap: () => _onPackageTap(package),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _isSearching ? 64 : 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isSearching ? 1.0 : 0.0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            autofocus: _isSearching,
            decoration: InputDecoration(
              hintText: 'Buscar por tracking…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(
    ThemeData theme,
    List<Package> packages,
    PackageStatus? selected,
  ) {
    final filters = <PackageStatus?>[null, ...PackageStatus.values];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selected == filter;
          final count = filter != null
              ? packages.where((p) => p.status == filter).length
              : packages.length;
          final label = filter?.label ?? 'Todos';

          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (_) => _onFilterSelected(filter),
            selectedColor: theme.colorScheme.primaryContainer,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsCount(
    ThemeData theme,
    int count, {
    required bool hasMore,
    int? total,
  }) {
    final label = total != null
        ? 'Mostrando $count de $total'
        : hasMore
            ? '$count cargados · desliza para más'
            : '$count paquete${count != 1 ? 's' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Error al cargar paquetes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  void _onPackageTap(Package package) {
    context.push('/packages/${package.id}');
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final VoidCallback onTap;

  const _PackageCard({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = package.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: status.color(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(status.icon, color: status.color(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.trackingNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package.recipientName ?? package.weight,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status.color(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
