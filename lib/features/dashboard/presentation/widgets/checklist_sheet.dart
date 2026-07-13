import 'package:flutter/material.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';

void showChecklistSheet(
  BuildContext context, {
  required List<ChecklistItem> items,
  required ValueChanged<List<ChecklistItem>> onChanged,
}) {
  final theme = Theme.of(context);
  final itemsNotifier = ValueNotifier(List<ChecklistItem>.from(items));

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return ValueListenableBuilder<List<ChecklistItem>>(
        valueListenable: itemsNotifier,
        builder: (context, currentItems, _) {
          final allDone = currentItems.every((i) => i.isDone);
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Checklist Pre-Viaje',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        Text(
                          '${currentItems.where((i) => i.status == ChecklistStatus.completed).length}/${currentItems.length}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: _groupByCategory(currentItems)
                            .entries
                            .expand((entry) => [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 12, bottom: 4),
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  ...entry.value.map(
                                    (item) => ChecklistTile(
                                      item: item,
                                      onToggle: () {
                                        final updatedItems =
                                            currentItems.map((i) {
                                          if (i.id != item.id) return i;
                                          return i.copyWith(
                                            status:
                                                i.status ==
                                                        ChecklistStatus
                                                            .completed
                                                    ? ChecklistStatus.pending
                                                    : ChecklistStatus.completed,
                                          );
                                        }).toList();

                                        itemsNotifier.value = updatedItems;
                                        onChanged(updatedItems);
                                      },
                                    ),
                                  ),
                                ])
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: allDone ? () => Navigator.pop(ctx) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        disabledBackgroundColor: Colors.grey.shade300,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('CHECKLIST COMPLETADO'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  ).then((_) => itemsNotifier.dispose());
}

class ChecklistTile extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;

  const ChecklistTile({
    super.key,
    required this.item,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: item.status == ChecklistStatus.completed
                ? Colors.green.withValues(alpha: 0.05)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.status == ChecklistStatus.completed
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(item.statusIcon, size: 20, color: item.statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    decoration: item.status == ChecklistStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                    color: item.status == ChecklistStatus.completed
                        ? Colors.grey
                        : null,
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

Map<String, List<ChecklistItem>> _groupByCategory(List<ChecklistItem> items) {
  final map = <String, List<ChecklistItem>>{};
  for (final item in items) {
    map.putIfAbsent(item.category, () => []).add(item);
  }
  return map;
}
