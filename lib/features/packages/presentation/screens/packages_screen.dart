import 'package:flutter/material.dart';

// ==================== MODELOS ====================

enum PackageStatus { pending, inTransit, delivered }

enum PackagePriority { urgent, high, normal, low }

class PackageItem {
  final String trackingNumber;
  final String recipientName;
  final String address;
  final PackageStatus status;
  final PackagePriority priority;
  final String weight;
  final String? notes;

  const PackageItem({
    required this.trackingNumber,
    required this.recipientName,
    required this.address,
    required this.status,
    required this.priority,
    required this.weight,
    this.notes,
  });
}

// ==================== EXTENSIONES PARA UI ====================

extension PackageStatusUI on PackageStatus {
  String get label {
    switch (this) {
      case PackageStatus.pending:
        return 'Pendiente';
      case PackageStatus.inTransit:
        return 'En tránsito';
      case PackageStatus.delivered:
        return 'Entregado';
    }
  }

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (this) {
      case PackageStatus.pending:
        return Colors.orange;
      case PackageStatus.inTransit:
        return scheme.primary;
      case PackageStatus.delivered:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case PackageStatus.pending:
        return Icons.schedule;
      case PackageStatus.inTransit:
        return Icons.local_shipping;
      case PackageStatus.delivered:
        return Icons.check_circle;
    }
  }
}

extension PackagePriorityUI on PackagePriority {
  String get label {
    switch (this) {
      case PackagePriority.urgent:
        return 'Urgente';
      case PackagePriority.high:
        return 'Alta';
      case PackagePriority.normal:
        return 'Normal';
      case PackagePriority.low:
        return 'Baja';
    }
  }

  Color get color {
    switch (this) {
      case PackagePriority.urgent:
        return Colors.red;
      case PackagePriority.high:
        return Colors.orange;
      case PackagePriority.normal:
        return Colors.blue;
      case PackagePriority.low:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case PackagePriority.urgent:
        return Icons.priority_high;
      case PackagePriority.high:
        return Icons.arrow_upward;
      case PackagePriority.normal:
        return Icons.remove;
      case PackagePriority.low:
        return Icons.arrow_downward;
    }
  }
}

// ==================== SCREEN ====================

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final _searchController = TextEditingController();
  PackageStatus? _selectedFilter;
  bool _isSearching = false;

  // Datos simulados — en producción vendrían de un BLoC/Provider
  final List<PackageItem> _packages = const [
    PackageItem(
      trackingNumber: 'PKG-2026-001',
      recipientName: 'Juan García',
      address: 'Av. Principal 123, Col. Centro',
      status: PackageStatus.inTransit,
      priority: PackagePriority.high,
      weight: '2.5 kg',
    ),
    PackageItem(
      trackingNumber: 'PKG-2026-002',
      recipientName: 'María López',
      address: 'Calle Roble 456, Col. Norte',
      status: PackageStatus.pending,
      priority: PackagePriority.normal,
      weight: '1.2 kg',
    ),
    PackageItem(
      trackingNumber: 'PKG-2026-003',
      recipientName: 'Carlos Hernández',
      address: 'Blvd. Pinos 789, Zona Industrial',
      status: PackageStatus.delivered,
      priority: PackagePriority.low,
      weight: '5.0 kg',
    ),
    PackageItem(
      trackingNumber: 'PKG-2026-004',
      recipientName: 'Ana Martínez',
      address: 'Calle Olmo 321, Col. Sur',
      status: PackageStatus.inTransit,
      priority: PackagePriority.urgent,
      weight: '3.8 kg',
    ),
    PackageItem(
      trackingNumber: 'PKG-2026-005',
      recipientName: 'Roberto Sánchez',
      address: 'Av. Arces 654, Col. Poniente',
      status: PackageStatus.pending,
      priority: PackagePriority.normal,
      weight: '0.8 kg',
    ),
    PackageItem(
      trackingNumber: 'PKG-2026-006',
      recipientName: 'Laura Torres',
      address: 'Calle Cedro 987, Col. Oriente',
      status: PackageStatus.delivered,
      priority: PackagePriority.high,
      weight: '4.2 kg',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PackageItem> get _filteredPackages {
    var filtered = _packages;

    // Filtro por estado
    if (_selectedFilter != null) {
      filtered = filtered.where((p) => p.status == _selectedFilter).toList();
    }

    // Filtro por búsqueda
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((p) {
        return p.trackingNumber.toLowerCase().contains(query) ||
            p.recipientName.toLowerCase().contains(query) ||
            p.address.toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  // Contadores para badges en filtros
  int _countByStatus(PackageStatus? status) {
    if (status == null) return _packages.length;
    return _packages.where((p) => p.status == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paquetes'),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Cerrar búsqueda' : 'Buscar paquete',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
            },
          ),
          IconButton(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda animada
          _buildSearchBar(theme),

          // Filtros horizontales con contadores
          _buildFilters(theme),

          // Contador de resultados
          _buildResultsCount(theme),

          // Lista de paquetes
          Expanded(child: _buildPackageList(theme)),
        ],
      ),
    );
  }

  // ==================== SEARCH BAR ====================
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

  // ==================== FILTERS ====================
  Widget _buildFilters(ThemeData theme) {
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
          final count = _countByStatus(filter);
          final label = filter?.label ?? 'Todos';

          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: 6),
                // Badge con contador
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

  // ==================== RESULTS COUNT ====================
  Widget _buildResultsCount(ThemeData theme) {
    final count = _filteredPackages.length;
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
          // Botón para escanear rápido
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

  // ==================== PACKAGE LIST ====================
  Widget _buildPackageList(ThemeData theme) {
    final packages = _filteredPackages;

    if (packages.isEmpty) {
      return _buildEmptyState(theme);
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

  Widget _buildEmptyState(ThemeData theme) {
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
              'Sin resultados',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No se encontraron paquetes con los filtros aplicados.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedFilter = null;
                  _searchController.clear();
                });
              },
              child: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ),
    );
  }

  void _onPackageTap(PackageItem package) {
    debugPrint('Tapped: ${package.trackingNumber}');
  }
}

// ==================== PACKAGE CARD ====================

class _PackageCard extends StatelessWidget {
  final PackageItem package;
  final VoidCallback onTap;

  const _PackageCard({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = package.status.color(context);
    final priorityColor = package.priority.color;
    final isUrgent = package.priority == PackagePriority.urgent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUrgent
                    ? Colors.red.withOpacity(0.4)
                    : theme.dividerColor.withOpacity(0.15),
                width: isUrgent ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icono de estado a la izquierda
                  _buildStatusIcon(theme, statusColor),
                  const SizedBox(width: 14),

                  // Contenido principal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Fila superior: tracking + status chip
                        _buildTopRow(theme, statusColor),
                        const SizedBox(height: 6),

                        // Nombre del destinatario
                        Text(
                          package.recipientName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Dirección
                        Text(
                          package.address,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),

                        // Fila inferior: peso + prioridad
                        _buildBottomRow(theme, priorityColor),
                      ],
                    ),
                  ),

                  // Flecha de navegación
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme, Color statusColor) {
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

  Widget _buildTopRow(ThemeData theme, Color statusColor) {
    return Row(
      children: [
        Text(
          package.trackingNumber,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
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

  Widget _buildBottomRow(ThemeData theme, Color priorityColor) {
    return Row(
      children: [
        // Peso
        _InfoChip(icon: Icons.scale, label: package.weight, theme: theme),
        const SizedBox(width: 8),

        // Prioridad
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

// ==================== CHIPS AUXILIARES ====================

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
