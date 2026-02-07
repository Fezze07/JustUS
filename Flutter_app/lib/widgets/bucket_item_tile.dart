// =============================================================================
// BucketItemTile - List item for bucket list
// =============================================================================

import 'package:flutter/material.dart';
import '../models/models.dart';

class BucketItemTile extends StatelessWidget {
  final BucketItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const BucketItemTile({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = item.done == 1;

    return Card(
      elevation: isDone ? 0 : 2,
      color: isDone ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
      child: ListTile(
        leading: Checkbox(
          value: isDone,
          onChanged: (_) => onToggle(),
        ),
        title: Text(
          item.text,
          style: TextStyle(
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? Colors.grey : null,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
