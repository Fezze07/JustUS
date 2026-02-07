// =============================================================================
// MoodScreen - Emoji picker for mood selection
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/mood_state.dart';
import '../widgets/emoji_picker_widget.dart';

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  // Common emoji list
  static const List<String> _defaultEmojis = [
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
    '🥲',
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
    '🤢',
    '🤮',
    '🤧',
    '🥵',
    '🥶',
    '🥴',
    '😵',
    '🤯',
    '🤠',
    '🥳',
    '🥸',
    '😎',
    '🤓',
    '🧐',
    '😕',
    '😟',
    '🙁',
    '☹️',
    '😮',
    '😯',
    '😲',
    '😳',
    '🥺',
    '😦',
    '😧',
    '😨',
    '😰',
    '😥',
    '😢',
    '😭',
    '😱',
    '😖',
    '😣',
    '😞',
    '😓',
    '😩',
    '😫',
    '🥱',
    '😤',
    '😡',
    '😠',
    '🤬',
    '😈',
    '👿',
    '💀',
    '☠️',
    '💩',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final moodState = context.read<MoodState>();
    await moodState.loadCache();
    await moodState.fetchRecentEmojis();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Il tuo Mood'),
        centerTitle: true,
      ),
      body: Consumer<MoodState>(
        builder: (context, state, _) {
          // Show messages
          if (state.message != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message!)),
              );
              state.clearMessage();
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current mood display
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Il tuo mood attuale',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.userMood,
                          style: const TextStyle(fontSize: 64),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Recent emojis
                if (state.recentEmojis.isNotEmpty) ...[
                  Text(
                    'Usati di recente',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: state.recentEmojis.map((emoji) {
                      return EmojiButton(
                        emoji: emoji,
                        onTap: () => state.updateMood(emoji),
                        isLoading: state.isLoading,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // All emojis
                Text(
                  'Scegli un mood',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _defaultEmojis.length,
                  itemBuilder: (context, index) {
                    return EmojiButton(
                      emoji: _defaultEmojis[index],
                      onTap: () => state.updateMood(_defaultEmojis[index]),
                      isLoading: state.isLoading,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
