// =============================================================================
// EmojiPickerWidget - Widget for selecting emojis
// =============================================================================

import 'package:flutter/material.dart';

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
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected 
              ? Theme.of(context).primaryColor.withValues(alpha: 0.2) 
              : Colors.grey.withValues(alpha: 0.1),
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
    );
  }
}
