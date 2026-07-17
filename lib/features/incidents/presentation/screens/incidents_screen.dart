import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/incidents/domain/incident.dart';
import 'package:tracking_system_app/features/incidents/domain/incidents_provider.dart';

class IncidentsScreen extends ConsumerStatefulWidget {
  const IncidentsScreen({super.key});

  @override
  ConsumerState<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends ConsumerState<IncidentsScreen>
    with PagedScrollMixin {
  @override
  void onLoadMoreRequested() {
    ref.read(incidentsPagedProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(incidentsPagedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidencias'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(incidentsPagedProvider.notifier).refresh(),
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
                    : ListView.builder(
                        controller: pagedScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: state.items.length + 1,
                        itemBuilder: (context, index) {
                          if (index >= state.items.length) {
                            return buildLoadMoreFooter(
                              isLoadingMore: state.isLoadingMore,
                              hasMore: state.hasMore,
                            );
                          }
                          return _buildIncidentCard(theme, state.items[index]);
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReportIncidentSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Reportar'),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Sin incidencias', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Las incidencias de tus viajes aparecerán aquí.',
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
            const Text('No se pudieron cargar las incidencias'),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  ref.read(incidentsPagedProvider.notifier).refresh(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(ThemeData theme, Incident incident) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    incident.type.icon,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.type.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          if (incident.tripCode != null) incident.tripCode!,
                          incident.id.substring(0, 8),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(incident.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(incident.description, style: theme.textTheme.bodyMedium),
            if (incident.packageTracking != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    incident.packageTracking!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _formatDate(incident.date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(IncidentStatus status) {
    return Chip(
      label: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: status.color,
        ),
      ),
      backgroundColor: status.color.withValues(alpha: 0.1),
      side: BorderSide(color: status.color.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showReportIncidentSheet(BuildContext context) {
    final theme = Theme.of(context);
    IncidentType? selectedType;
    final descriptionController = TextEditingController();
    var submitting = false;

    final bootstrap = ref.read(bootstrapProvider).valueOrNull;
    final tripId = bootstrap?.trip?.id;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final maxHeight = media.size.height * 0.85;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Reportar incidencia',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (bootstrap?.trip?.code != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Viaje ${bootstrap!.trip!.code}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      // Selector de tipo sin DropdownButtonFormField:
                      // evita hasSize/Flexible en overlay del menú.
                      Text(
                        'Tipo de incidencia',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: IncidentType.values.map((type) {
                          final selected = selectedType == type;
                          return FilterChip(
                            selected: selected,
                            avatar: Icon(type.icon, size: 16),
                            label: Text(type.label),
                            onSelected: (_) {
                              setSheetState(() => selectedType = type);
                            },
                            showCheckmark: false,
                            selectedColor: theme.colorScheme.primaryContainer,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                if (selectedType == null ||
                                    descriptionController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Completa tipo y descripción',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                setSheetState(() => submitting = true);
                                try {
                                  await ref
                                      .read(incidentsPagedProvider.notifier)
                                      .report(
                                        type: selectedType!,
                                        description:
                                            descriptionController.text.trim(),
                                        tripId: tripId,
                                      );
                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Incidencia reportada correctamente',
                                      ),
                                      backgroundColor: Color(0xFF176351),
                                    ),
                                  );
                                } catch (e) {
                                  setSheetState(() => submitting = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Enviar reporte'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(descriptionController.dispose);
  }
}

