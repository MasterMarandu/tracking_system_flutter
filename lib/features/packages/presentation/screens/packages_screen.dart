import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';
import 'package:tracking_system_app/features/packages/domain/packages_provider.dart';

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key});

  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen> {
  final _searchController = TextEditingController();
  PackageStatus? _selectedFilter;
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Package> _filteredPackages(List<Package> all) {
    var filtered = all;

    if (_selectedFilter != null) {
      filtered = filtered.where((p) => p.status == _selectedFilter).toList();
    }

    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((p) {
        return p.trackingNumber.toLowerCase().contains(query) ||
            (p.recipientName?.toLowerCase().contains(query) ?? false) ||
            (p.address?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packagesAsync = ref.watch(packagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paquetes'),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar paquete',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) _searchController.clear();
            }),
          ),
          IconButton(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: packagesAsync.when(
        data: (packages) {
          if (packages.isEmpty) {
            return _buildEmptyState(theme, 'Sin paquetes',
                'No hay paquetes asignados a tu viaje actual.');
          }
          return _buildBody(theme, packages);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildErrorState(theme, e.toString()),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<Package> packages) {
    final filtered = _filteredPackages(packages);

    return Column(
      children: [
        _buildSearchBar(theme),
        _buildFilters(theme, packages),
        _buildResultsCount(theme, filtered.length),
        Expanded(child: _buildPackageList(filtered)),
      ],
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
              hintText: 'Buscar por tracking, nombre o dirección...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          setState(() => _searchController.clear()),
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(
                0.5,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme, List<Package> packages) {
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
          final isSelected = _selectedFilter == filter;
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer.withOpacity(0.15)
                        : theme.colorScheme.onSurface.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedFilter = filter),
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

  Widget _buildResultsCount(ThemeData theme, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Text(
            '$count paquete${count != 1 ? 's' : ''} encontrado${count != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Escanear'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageList(List<Package> packages) {
    if (packages.isEmpty) {
      return _buildEmptyState(Theme.of(context), 'Sin resultados',
          'No se encontraron paquetes con los filtros aplicados.');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: packages.length,
      itemBuilder: (context, index) {
        return _PackageCard(
          package: packages[index],
          onTap: () => _onPackageTap(packages[index]),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
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
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => setState(() {
                _selectedFilter = null;
                _searchController.clear();
              }),
              child: const Text('Limpiar filtros'),
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
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Error al cargar paquetes',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => ref.invalidate(packagesProvider),
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
    final scheme = Theme.of(context).colorScheme;
    final statusColor = package.status.color(context);
    final priorityColor = package.priority.color;
    final isUrgent = package.priority == PackagePriority.urgent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUrgent
                  ? Colors.red.withOpacity(0.4)
                  : scheme.outlineVariant.withOpacity(0.5),
              width: isUrgent ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusIcon(scheme, statusColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopRow(scheme, statusColor),
                    const SizedBox(height: 6),
                    Text(
                      package.recipientName ?? 'Sin nombre',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      package.address ?? 'Sin dirección registrada',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    _buildBottomRow(scheme, priorityColor),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme scheme, Color statusColor) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(package.status.icon, color: statusColor, size: 22),
    );
  }

  Widget _buildTopRow(ColorScheme scheme, Color statusColor) {
    return Row(
      children: [
        Text(
          package.trackingNumber,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            package.status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomRow(ColorScheme scheme, Color priorityColor) {
    return Row(
      children: [
        _InfoChip(icon: Icons.scale, label: package.weight),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: priorityColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(package.priority.icon, size: 12, color: priorityColor),
              const SizedBox(width: 4),
              Text(
                package.priority.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: priorityColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
