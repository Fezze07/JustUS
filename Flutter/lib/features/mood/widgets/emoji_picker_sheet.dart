import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({super.key});

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  final TextEditingController _emojiController = TextEditingController();
  String? _errorText;
  List<String> _userEmojis = [];
  bool _isLoadingEmojis = true;

  final List<String> _defaultEmojis = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '🤣',
    '😂',
    '🙂',
    '🙃',
    '😉',
    '😊',
    '😇',
    '🥰',
    '😍',
    '🤩',
    '😘',
    '😗',
    '😚',
    '😙',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '🤐',
    '🤨',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '🤥',
    '😌',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadUserEmojis());
  }

  Future<void> _loadUserEmojis() async {
    final repo = context.read<MoodState>().repository;
    final result = await repo.fetchMoods();
    if (mounted) {
      final moods = result.valueOrNull;
      if (moods != null) {
        final uniqueEmojis = moods.map((e) => e.emoji).toSet().toList();
        setState(() {
          _userEmojis = uniqueEmojis;
          _isLoadingEmojis = false;
        });
      } else {
        setState(() {
          _isLoadingEmojis = false;
        });
      }
    }
  }

  List<String> get _displayEmojis {
    final display = <String>[];
    for (final emoji in _userEmojis) {
      if (!display.contains(emoji)) {
        display.add(emoji);
      }
    }
    for (final emoji in _defaultEmojis) {
      if (display.length >= _defaultEmojis.length) break;
      if (!display.contains(emoji)) {
        display.add(emoji);
      }
    }

    return display;
  }

  void _addEmoji() {
    final input = _emojiController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = context.loc.mood_enterEmoji);

      return;
    }

    if (input.characters.length != 1) {
      setState(() => _errorText = context.loc.mood_enterSingleEmoji);

      return;
    }

    final currentMood = context.read<MoodState>().userMood;
    if (input == currentMood) {
      ErrorHandler.handle(
        AppError(
            code: ErrorCodes.localMoodDuplicate,
            message: context.loc.mood_duplicateTechnicalMessage),
        context: context,
      );

      return;
    }

    unawaited(context.read<MoodState>().updateMood(input));
    Navigator.pop(context);
  }

  void _selectPredefinedEmoji(String emoji) {
    final currentMood = context.read<MoodState>().userMood;
    if (emoji == currentMood) {
      ErrorHandler.handle(
        AppError(
            code: ErrorCodes.localMoodDuplicate,
            message: context.loc.mood_duplicateTechnicalMessage),
        context: context,
      );

      return;
    }

    unawaited(context.read<MoodState>().updateMood(emoji));
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emojisToDisplay = _displayEmojis;

    return VPSheet(
      title: context.loc.mood_sheetTitle,
      maxHeightFactor: 0.85,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: VPTextField(
                controller: _emojiController,
                hint: context.loc.mood_enterEmoji,
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
                onSubmitted: (_) => _addEmoji(),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _addEmoji,
              child: Container(
                height: 56, // Match the typical TextField height
                width: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientAccent, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add,
                    color: AppColors.contentPrimary, size: 28),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: AppColors.surfaceOverlay),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoadingEmojis
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: emojisToDisplay.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () =>
                          _selectPredefinedEmoji(emojisToDisplay[index]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.borderDark,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(emojisToDisplay[index],
                            style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
