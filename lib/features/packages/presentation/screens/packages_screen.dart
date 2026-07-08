import 'package:flutter/material.dart';

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final _searchController = TextEditingController();
  String _selectedFilter = 'All';
  bool _isSearching = false;

  final List<String> _filters = ['All', 'Pending', 'In Transit', 'Delivered'];

  final List<Map<String, dynamic>> _packages = [
    {
      'trackingNumber': 'PKG-2026-001',
      'recipientName': 'John Smith',
      'address': '123 Main St, New York, NY 10001',
      'status': 'In Transit',
      'priority': 'High',
      'weight': '2.5 kg',
    },
    {
      'trackingNumber': 'PKG-2026-002',
      'recipientName': 'Sarah Johnson',
      'address': '456 Oak Ave, Los Angeles, CA 90001',
      'status': 'Pending',
      'priority': 'Normal',
      'weight': '1.2 kg',
    },
    {
      'trackingNumber': 'PKG-2026-003',
      'recipientName': 'Michael Brown',
      'address': '789 Pine Rd, Chicago, IL 60601',
      'status': 'Delivered',
      'priority': 'Low',
      'weight': '5.0 kg',
    },
    {
      'trackingNumber': 'PKG-2026-004',
      'recipientName': 'Emily Davis',
      'address': '321 Elm St, Houston, TX 77001',
      'status': 'In Transit',
      'priority': 'Urgent',
      'weight': '3.8 kg',
    },
    {
      'trackingNumber': 'PKG-2026-005',
      'recipientName': 'Robert Wilson',
      'address': '654 Maple Dr, Phoenix, AZ 85001',
      'status': 'Pending',
      'priority': 'Normal',
      'weight': '0.8 kg',
    },
    {
      'trackingNumber': 'PKG-2026-006',
      'recipientName': 'Lisa Anderson',
      'address': '987 Cedar Ln, Philadelphia, PA 19101',
      'status': 'Delivered',
      'priority': 'High',
      'weight': '4.2 kg',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredPackages {
    var filtered = _packages;
    if (_selectedFilter != 'All') {
      filtered = filtered.where((p) => p['status'] == _selectedFilter).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((p) {
        return p['trackingNumber'].toLowerCase().contains(query) ||
            p['recipientName'].toLowerCase().contains(query) ||
            p['address'].toLowerCase().contains(query);
      }).toList();
    }
    return filtered;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFFFC107);
      case 'In Transit':
        return const Color(0xFF2196F3);
      case 'Delivered':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'Urgent':
        return Icons.error;
      case 'High':
        return Icons.keyboard_arrow_up;
      case 'Normal':
        return Icons.remove;
      case 'Low':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.remove;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Urgent':
        return const Color(0xFFF44336);
      case 'High':
        return const Color(0xFFFF9800);
      case 'Normal':
        return const Color(0xFF2196F3);
      case 'Low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packages'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => _buildFilterSheet(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by tracking #, name, or address',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() => _searchController.clear());
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedFilter = filter);
                  },
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  showCheckmark: false,
                );
              },
            ),
          ),
          Expanded(
            child: _filteredPackages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No packages found',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredPackages.length,
                    itemBuilder: (context, index) {
                      final package = _filteredPackages[index];
                      return _PackageCard(
                        trackingNumber: package['trackingNumber'],
                        recipientName: package['recipientName'],
                        address: package['address'],
                        status: package['status'],
                        priority: package['priority'],
                        statusColor: _getStatusColor(package['status']),
                        priorityIcon: _getPriorityIcon(package['priority']),
                        priorityColor: _getPriorityColor(package['priority']),
                        onTap: () {
                          print('Tapped package: ${package['trackingNumber']}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSheet() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Filter Packages',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...ListTile.divideTiles(
            context: context,
            tiles: _filters.map((filter) {
              return ListTile(
                title: Text(filter),
                trailing: _selectedFilter == filter
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedFilter = filter);
                  Navigator.pop(context);
                },
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final String trackingNumber;
  final String recipientName;
  final String address;
  final String status;
  final String priority;
  final Color statusColor;
  final IconData priorityIcon;
  final Color priorityColor;
  final VoidCallback onTap;

  const _PackageCard({
    required this.trackingNumber,
    required this.recipientName,
    required this.address,
    required this.status,
    required this.priority,
    required this.statusColor,
    required this.priorityIcon,
    required this.priorityColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          trackingNumber,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipientName,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            address,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          priorityIcon,
                          size: 16,
                          color: priorityColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
