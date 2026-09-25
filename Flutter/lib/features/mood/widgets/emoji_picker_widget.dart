// =============================================================================
// EmojiPickerWidget - Widget for selecting emojis
// =============================================================================

import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

abstract class EmojiPickerWidget {}

class EmojiButton extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isSelected;

  const EmojiButton({
    super.key,
    required this.emoji,
    required this.onTap,
    required this.isLoading,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: emoji,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            color: isSelected
                ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                : AppColors.neutralText.withValues(alpha: 0.1),
            border: isSelected
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
          ),
          child: FittedBox(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ),
      ),
    );
  }
}
