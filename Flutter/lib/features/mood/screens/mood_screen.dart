// =============================================================================
// MoodScreen - Interactive Mood Board with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import 'package:justus/all_imports.dart';

class MoodScreen extends StatefulWidget {
  final bool isActive;
  const MoodScreen({super.key, this.isActive = false});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      unawaited(_loadData());
    }
  }

  @override
  void didUpdateWidget(covariant MoodScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_loadData());
    }
  }

  Future<void> _loadData() async {
    final moodState = context.read<MoodState>();
    await moodState.initMoodScreen();
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
      title: context.loc.mood_boardTitle,
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
                  title: context.loc.mood_recents,
                  actionLabel: context.loc.mood_edit,
                  onActionTap: () {},
                ),

                if (state.recentEmojis.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      context.loc.mood_noneSet,
                      style: VpWidgets.googleFont(
                        fontSize: 14,
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: state.recentEmojis.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) => _buildRecentItem(
                          state.recentEmojis[index], index == 0),
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
                                context.loc.home_updateStatus,
                                style: VpWidgets.googleFont(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.loc.mood_howFeeling,
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
                        context.loc.mood_timeline,
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
                          context.loc.mood_today,
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
                if (state.timeline.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      context.loc.mood_noneSet,
                      style: VpWidgets.googleFont(
                        fontSize: 14,
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      for (var i = 0; i < state.timeline.length; i++)
                        _buildTimelineItem(
                          emoji: state.timeline[i].emoji,
                          timestamp: state.timeline[i].createdAt,
                          color: state.timeline[i].isMine
                              ? AppColors.primary
                              : Colors.pinkAccent,
                          isLast: i == state.timeline.length - 1 &&
                              !state.hasMoreTimeline,
                        ),
                      if (state.hasMoreTimeline)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () =>
                                  unawaited(state.loadMoreTimeline()),
                              icon: const Icon(Icons.expand_more,
                                  color: AppColors.primary),
                              label: Text(
                                context.loc.mood_showMore,
                                style: VpWidgets.googleFont(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
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

  Widget _buildRecentItem(String emoji, bool isSelected) {
    return Container(
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
    );
  }

  Widget _buildTimelineItem({
    required String emoji,
    required String? timestamp,
    required Color color,
    required bool isLast,
  }) {
    Widget content;
    if (timestamp != null) {
      final parsed = AppDateUtils.tryParse(timestamp)?.toLocal();
      if (parsed != null) {
        final dateFormat = DateFormat('d MMMM', 'it');
        final timeFormat = DateFormat('HH:mm');
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dateFormat.format(parsed),
              style: VpWidgets.googleFont(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            Text(
              timeFormat.format(parsed),
              style: VpWidgets.googleFont(
                fontWeight: FontWeight.w500,
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        );
      } else {
        content = Text(
          context.loc.mood_noneSet,
          style: VpWidgets.googleFont(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        );
      }
    } else {
      content = Text(
        context.loc.mood_noneSet,
        style: VpWidgets.googleFont(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 16,
        ),
      );
    }

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
            child: Container(
              height: 48,
              alignment: Alignment.centerLeft,
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
