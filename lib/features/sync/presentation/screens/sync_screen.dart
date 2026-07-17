import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final syncState = ref.watch(syncEngineProvider);
    final syncNotifier = ref.read(syncEngineProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: syncState.isSyncing
                ? null
                : () => syncNotifier.syncNow(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(syncState, colorScheme, theme),
            const SizedBox(height: 16),
            _buildPendingCard(syncState, colorScheme, theme),
            const SizedBox(height: 16),
            if (syncState.isSyncing) _buildProgressCard(syncState, colorScheme, theme),
            if (syncState.isSyncing) const SizedBox(height: 16),
            _buildSyncButton(syncState, syncNotifier, colorScheme),
            const SizedBox(height: 24),
            _buildErrorSection(syncState, colorScheme, theme),
            const SizedBox(height: 24),
            _buildOperationsList(syncState, colorScheme, theme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(SyncState syncState, ColorScheme colorScheme, ThemeData theme) {
    final isOnline = syncState.isOnline;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusRow(
              icon: Icons.wifi,
              label: 'Internet',
              isConnected: isOnline,
              colorScheme: colorScheme,
              theme: theme,
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Last Sync',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  syncState.lastSyncTime != null
                      ? _formatDateTime(syncState.lastSyncTime!)
                      : 'Never',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required bool isConnected,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (isConnected ? Colors.green : Colors.red).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isConnected ? 'Connected' : 'Disconnected',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingCard(SyncState syncState, ColorScheme colorScheme, ThemeData theme) {
    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 32,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pending Items',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${syncState.pendingOperations} items waiting to sync',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(SyncState syncState, ColorScheme colorScheme, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF206B5C),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Syncing...',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(
                minHeight: 8,
                backgroundColor: Color(0xFFE0E0E0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncButton(
    SyncState syncState,
    SyncEngine syncNotifier,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: syncState.isSyncing ? null : () => syncNotifier.syncNow(),
        icon: syncState.isSyncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.sync),
        label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Now'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorSection(SyncState syncState, ColorScheme colorScheme, ThemeData theme) {
    if (syncState.error == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'No sync errors',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last Sync Error',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
          ),
          child: ListTile(
            leading: Icon(
              Icons.error_outline,
              color: colorScheme.error,
            ),
            title: Text(
              syncState.error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperationsList(SyncState syncState, ColorScheme colorScheme, ThemeData theme) {
    return FutureBuilder<List<SyncOperation>>(
      future: _loadOperations(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final operations = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Queued Operations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: operations.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: colorScheme.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final op = operations[index];
                  return ListTile(
                    leading: Icon(
                      _getOperationIcon(op.type),
                      color: _getOperationColor(op.status),
                    ),
                    title: Text(
                      _getOperationLabel(op.type),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      _formatDateTime(op.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: _buildOperationStatusBadge(op.status, theme),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<SyncOperation>> _loadOperations() async {
    try {
      final queue = await SyncQueue.create();
      return await queue.getPendingOperations();
    } catch (_) {
      return [];
    }
  }

  Widget _buildOperationStatusBadge(SyncOperationStatus status, ThemeData theme) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case SyncOperationStatus.pending:
        color = Colors.orange;
        label = 'Pending';
        icon = Icons.schedule;
      case SyncOperationStatus.processing:
        color = Colors.blue;
        label = 'Processing';
        icon = Icons.sync;
      case SyncOperationStatus.completed:
        color = Colors.green;
        label = 'Done';
        icon = Icons.check_circle;
      case SyncOperationStatus.failed:
        color = Colors.red;
        label = 'Failed';
        icon = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getOperationIcon(SyncOperationType type) {
    switch (type) {
      case SyncOperationType.completeDelivery:
        return Icons.check_circle_outline;
      case SyncOperationType.updateChecklist:
        return Icons.checklist;
      case SyncOperationType.verifyOtp:
        return Icons.pin;
      case SyncOperationType.submitPhoto:
        return Icons.camera_alt;
      case SyncOperationType.submitSignature:
        return Icons.draw;
      case SyncOperationType.reportIncident:
        return Icons.warning_amber;
      case SyncOperationType.updateTripStatus:
        return Icons.update;
    }
  }

  Color _getOperationColor(SyncOperationStatus status) {
    switch (status) {
      case SyncOperationStatus.pending:
        return Colors.orange;
      case SyncOperationStatus.processing:
        return Colors.blue;
      case SyncOperationStatus.completed:
        return Colors.green;
      case SyncOperationStatus.failed:
        return Colors.red;
    }
  }

  String _getOperationLabel(SyncOperationType type) {
    switch (type) {
      case SyncOperationType.completeDelivery:
        return 'Complete Delivery';
      case SyncOperationType.updateChecklist:
        return 'Update Checklist';
      case SyncOperationType.verifyOtp:
        return 'Verify OTP';
      case SyncOperationType.submitPhoto:
        return 'Submit Photo';
      case SyncOperationType.submitSignature:
        return 'Submit Signature';
      case SyncOperationType.reportIncident:
        return 'Report Incident';
      case SyncOperationType.updateTripStatus:
        return 'Update Trip Status';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    return '$day/$month/${dateTime.year} $hour:$minute';
  }
}
