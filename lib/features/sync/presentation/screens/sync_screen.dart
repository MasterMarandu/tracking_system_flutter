import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/services/location_service.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

/// Lista de operaciones en cola (se refresca con el contador del engine).
final _syncQueueListProvider = FutureProvider.autoDispose<List<SyncOperation>>(
  (ref) async {
    ref.watch(syncEngineProvider.select((s) => s.pendingOperations));
    ref.watch(syncEngineProvider.select((s) => s.status));
    ref.watch(syncEngineProvider.select((s) => s.lastSyncTime));
    try {
      final queue = await SyncQueue.create();
      final ops = await queue.getPendingOperations();
      ops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ops;
    } catch (_) {
      return [];
    }
  },
);

final _gpsBufferCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(syncEngineProvider.select((s) => s.pendingOperations));
  ref.watch(syncEngineProvider.select((s) => s.status));
  try {
    return await LocationService.instance.pendingGpsCount();
  } catch (_) {
    return 0;
  }
});

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final syncState = ref.watch(syncEngineProvider);
    final opsAsync = ref.watch(_syncQueueListProvider);
    final gpsAsync = ref.watch(_gpsBufferCountProvider);
    final gpsCount = gpsAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de sincronización'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(_syncQueueListProvider);
              ref.invalidate(_gpsBufferCountProvider);
              ref.read(syncEngineProvider.notifier).syncNow();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_syncQueueListProvider);
          ref.invalidate(_gpsBufferCountProvider);
          await ref.read(syncEngineProvider.notifier).syncNow();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _ConnectionHero(syncState: syncState, theme: theme),
            const SizedBox(height: 12),
            if (!syncState.isOnline) ...[
              _InfoBanner(
                color: Colors.red.shade700,
                icon: Icons.cloud_off,
                text:
                    'Sin conexión. Las acciones se guardan en el dispositivo y se enviarán al recuperar señal.',
              ),
              const SizedBox(height: 12),
            ],
            if (syncState.isSyncing) ...[
              _InfoBanner(
                color: const Color(0xFF206B5C),
                icon: Icons.sync,
                text: 'Sincronizando cola y puntos GPS…',
                spinning: true,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Pendientes',
                    value: '${syncState.pendingOperations}',
                    color: syncState.pendingOperations > 0
                        ? Colors.orange
                        : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.gps_fixed,
                    label: 'GPS en buffer',
                    value: '$gpsCount',
                    color: gpsCount > 0 ? Colors.deepOrange : colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LastSyncCard(syncState: syncState, theme: theme),
            if (syncState.error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: syncState.error!, theme: theme),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: syncState.isSyncing || !syncState.isOnline
                    ? null
                    : () async {
                        await ref.read(syncEngineProvider.notifier).syncNow();
                        ref.invalidate(_syncQueueListProvider);
                        ref.invalidate(_gpsBufferCountProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sincronización solicitada'),
                              backgroundColor: Color(0xFF176351),
                            ),
                          );
                        }
                      },
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
                label: Text(
                  !syncState.isOnline
                      ? 'Sin red — no se puede enviar'
                      : syncState.isSyncing
                          ? 'Sincronizando…'
                          : 'Sincronizar ahora',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Cola de operaciones',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Entregas, incidencias y cambios guardados offline.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            opsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _EmptyOps(
                icon: Icons.error_outline,
                title: 'No se pudo leer la cola',
                subtitle: e.toString(),
              ),
              data: (ops) {
                if (ops.isEmpty) {
                  return const _EmptyOps(
                    icon: Icons.check_circle_outline,
                    title: 'Todo al día',
                    subtitle:
                        'No hay operaciones pendientes ni conflictos.',
                  );
                }
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ops.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 56,
                      endIndent: 16,
                      color: colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final op = ops[index];
                      return _OperationTile(
                        op: op,
                        onRetry: () async {
                          await ref
                              .read(syncEngineProvider.notifier)
                              .retryFailed(op.id);
                          ref.invalidate(_syncQueueListProvider);
                        },
                        onDismiss: () async {
                          await ref
                              .read(syncEngineProvider.notifier)
                              .dismissConflict(op.id);
                          ref.invalidate(_syncQueueListProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Operación descartada'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Consejo: en campo sin señal podés seguir entregando. '
              'Al recuperar red, tocá «Sincronizar ahora» o esperá el envío automático.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  final SyncState syncState;
  final ThemeData theme;

  const _ConnectionHero({required this.syncState, required this.theme});

  @override
  Widget build(BuildContext context) {
    final online = syncState.isOnline;
    final Color accent;
    final String title;
    final String subtitle;
    final IconData icon;

    if (syncState.isSyncing) {
      accent = const Color(0xFF206B5C);
      title = 'Sincronizando';
      subtitle = 'Enviando cambios pendientes al servidor';
      icon = Icons.sync;
    } else if (!online) {
      accent = Colors.red.shade700;
      title = 'Modo offline';
      subtitle = 'Usando datos del dispositivo';
      icon = Icons.cloud_off;
    } else if (syncState.pendingOperations > 0) {
      accent = Colors.orange.shade800;
      title = 'Conectado · hay pendientes';
      subtitle = '${syncState.pendingOperations} ítem(s) por enviar';
      icon = Icons.cloud_queue;
    } else {
      accent = Colors.green.shade700;
      title = 'Conectado y al día';
      subtitle = syncState.lastSyncSuccess
          ? 'Última sync correcta'
          : 'Listo para operar';
      icon = Icons.cloud_done;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final bool spinning;

  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.text,
    this.spinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (spinning)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastSyncCard extends StatelessWidget {
  final SyncState syncState;
  final ThemeData theme;

  const _LastSyncCard({required this.syncState, required this.theme});

  @override
  Widget build(BuildContext context) {
    final when = syncState.lastSyncTime;
    final label = when == null ? 'Nunca' : _relative(when);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(
          Icons.schedule,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Última sincronización'),
        subtitle: Text(label),
        trailing: Icon(
          syncState.lastSyncSuccess
              ? Icons.check_circle
              : Icons.help_outline,
          color: syncState.lastSyncSuccess
              ? Colors.green
              : theme.colorScheme.onSurfaceVariant,
          size: 22,
        ),
      ),
    );
  }

  String _relative(DateTime dt) {
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Hace un momento';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final ThemeData theme;

  const _ErrorCard({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
        title: const Text('Último error de sync'),
        subtitle: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _EmptyOps extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyOps({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  final SyncOperation op;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _OperationTile({
    required this.op,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(op.status);
    final clientOp = op.payload['clientOpId'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_typeIcon(op.type), color: color, size: 20),
        ),
        title: Text(
          _typeLabel(op.type),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              _formatWhen(op.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (clientOp != null && clientOp.length >= 8)
              Text(
                'Op ${clientOp.substring(0, 8)}…',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (op.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                op.lastError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: op.status == SyncOperationStatus.conflict
                      ? Colors.deepOrange
                      : theme.colorScheme.error,
                  fontSize: 11,
                ),
              ),
            ],
            if (op.retryCount > 0)
              Text(
                'Reintentos: ${op.retryCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        isThreeLine: op.lastError != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusChip(status: op.status),
            if (op.status == SyncOperationStatus.failed)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Reintentar'),
              ),
            if (op.status == SyncOperationStatus.conflict)
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  foregroundColor: Colors.deepOrange,
                ),
                child: const Text('Descartar'),
              ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(SyncOperationStatus s) {
    switch (s) {
      case SyncOperationStatus.pending:
        return Colors.orange;
      case SyncOperationStatus.processing:
        return Colors.blue;
      case SyncOperationStatus.completed:
        return Colors.green;
      case SyncOperationStatus.failed:
        return Colors.red;
      case SyncOperationStatus.conflict:
        return Colors.deepOrange;
    }
  }

  static IconData _typeIcon(SyncOperationType t) {
    switch (t) {
      case SyncOperationType.completeDelivery:
        return Icons.local_shipping_outlined;
      case SyncOperationType.updateChecklist:
        return Icons.checklist;
      case SyncOperationType.verifyOtp:
        return Icons.pin_outlined;
      case SyncOperationType.submitPhoto:
        return Icons.camera_alt_outlined;
      case SyncOperationType.submitSignature:
        return Icons.draw_outlined;
      case SyncOperationType.reportIncident:
        return Icons.report_outlined;
      case SyncOperationType.updateTripStatus:
        return Icons.route_outlined;
    }
  }

  static String _typeLabel(SyncOperationType t) {
    switch (t) {
      case SyncOperationType.completeDelivery:
        return 'Entrega';
      case SyncOperationType.updateChecklist:
        return 'Checklist';
      case SyncOperationType.verifyOtp:
        return 'Verificar OTP';
      case SyncOperationType.submitPhoto:
        return 'Foto de evidencia';
      case SyncOperationType.submitSignature:
        return 'Firma';
      case SyncOperationType.reportIncident:
        return 'Incidencia';
      case SyncOperationType.updateTripStatus:
        return 'Estado del viaje';
    }
  }

  static String _formatWhen(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}

class _StatusChip extends StatelessWidget {
  final SyncOperationStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    switch (status) {
      case SyncOperationStatus.pending:
        color = Colors.orange;
        label = 'Pendiente';
      case SyncOperationStatus.processing:
        color = Colors.blue;
        label = 'Enviando';
      case SyncOperationStatus.completed:
        color = Colors.green;
        label = 'Hecho';
      case SyncOperationStatus.failed:
        color = Colors.red;
        label = 'Error';
      case SyncOperationStatus.conflict:
        color = Colors.deepOrange;
        label = 'Conflicto';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
