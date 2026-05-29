import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
      if (result is Success<List<MoodEntry>>) {
        final uniqueEmojis = result.value.map((e) => e.emoji).toSet().toList();
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
      setState(() => _errorText = 'Inserisci un\'emoji');

      return;
    }

    if (input.characters.length != 1) {
      setState(() => _errorText = 'Inserisci una sola emoji');

      return;
    }

    final currentMood = context.read<MoodState>().userMood;
    if (input == currentMood) {
      ErrorHandler.handle(
        const AppError(
            code: ErrorCodes.localMoodDuplicate,
            message: 'Utente ha tentato di reinserire il mood corrente.'),
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
        const AppError(
            code: ErrorCodes.localMoodDuplicate,
            message: 'Utente ha tentato di reinserire il mood corrente.'),
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

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: AppColors.neonPurple,
                blurRadius: 4,
                offset: Offset(0, -2))
          ]),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
            margin: const EdgeInsets.only(bottom: 24),
          ),
          Text(
            'Scegli il tuo Mood',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _emojiController,
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Inserisci un\'emoji...',
                    hintStyle:
                        const TextStyle(color: Colors.white30, fontSize: 16),
                    errorText: _errorText,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
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
                      colors: [Color(0xFFA855F7), AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoadingEmojis
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                            color: Colors.white.withValues(alpha: 0.05),
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
      ),
    );
  }
}
