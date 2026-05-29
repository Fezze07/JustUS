// =============================================================================
// MoodScreen - Interactive Mood Board with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadData());
    });
  }

  Future<void> _loadData() async {
    final moodState = context.read<MoodState>();
    await moodState.init();
  }

  void _showEmojiPicker() {
    unawaited(showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const EmojiPickerSheet(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      title: 'Mood Board',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.analytics, color: AppColors.primary),
          onPressed: () {},
        ),
      ],
      body: Consumer<MoodState>(
        builder: (context, state, _) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Recents Section
                VPSectionHeader(
                  title: 'YOUR RECENTS',
                  actionLabel: 'Edit',
                  onActionTap: () {},
                ),

                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: state.recentEmojis.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      if (state.recentEmojis.isEmpty) {
                        const defaultEmojis = ['😊', '😌', '🥰', '⚡', '😴'];

                        return _buildRecentItem(
                            defaultEmojis[index], "Mood", index == 0);
                      }

                      return _buildRecentItem(
                          state.recentEmojis[index], "Mood", index == 0);
                    },
                  ),
                ),

                // Add New Mood Button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: GestureDetector(
                    onTap: _showEmojiPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFA855F7), AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          VpWidgets.boxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Update Status',
                                style: VpWidgets.googleFont(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'How are you feeling?',
                                style: VpWidgets.googleFont(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.neonGreen,
                              shape: BoxShape.circle,
                              boxShadow: [
                                VpWidgets.boxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Icon(Icons.add,
                                color: AppColors.deepViolet, size: 30),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Timeline Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Timeline',
                        style: VpWidgets.googleFont(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Today',
                          style: VpWidgets.googleFont(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Timeline List
                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _buildTimelineItem(
                      emoji: state.userMood.isNotEmpty ? state.userMood : '😐',
                      title:
                          'You felt ${state.userMood.isNotEmpty ? "Updated" : "Calm"}',
                      time: 'Now',
                      description: 'Just updated your mood.',
                      color: AppColors.primary,
                      isLast: false,
                    ),
                    _buildTimelineItem(
                      emoji: state.partnerMood.isNotEmpty
                          ? state.partnerMood
                          : '😐',
                      title:
                          'Partner felt ${state.partnerMood.isNotEmpty ? "Updated" : "Calm"}',
                      time: 'Recent',
                      description: 'Partner updated their mood.',
                      color: Colors.orange,
                      isLast: true,
                    ),
                  ],
                ),

                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentItem(String emoji, String label, bool isSelected) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.backgroundDark.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.white10,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: VpWidgets.googleFont(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required String emoji,
    required String title,
    required String time,
    required String description,
    required Color color,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Line
          Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: VpWidgets.cardDecoration(
                  borderRadius: 16,
                  borderColor: color.withValues(alpha: 0.4),
                  boxShadow: [
                    VpWidgets.boxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.white10,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: VpWidgets.googleFont(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        time,
                        style: VpWidgets.googleFont(
                          fontWeight: FontWeight.w500,
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: VpWidgets.googleFont(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
