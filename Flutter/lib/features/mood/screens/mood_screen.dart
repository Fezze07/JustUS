// =============================================================================
// MoodScreen - Interactive Mood Board with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import 'package:justus/all_imports.dart';

class MoodScreen extends TabScreen {
  const MoodScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> with TabScreenMixin {
  @override
  Future<void> loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kMoods]);
    }
    if (!mounted) return;
    await context.read<MoodState>().initMoodScreen();
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
      showAppBar: false,
      body: SafeArea(
        child: Column(
          children: [
            VPHeader(
              title: context.loc.mood_boardTitle,
              onBack: () => MainShell.shellKey.currentState?.switchToTab(0),
            ),
            Expanded(
              child: Selector<MoodState, (List<String>, List<MoodEntry>, bool)>(
        selector: (_, s) => (s.recentEmojis, s.timeline, s.hasMoreTimeline),
        builder: (context, moodData, _) {
          final recentEmojis = moodData.$1;
          final timeline = moodData.$2;
          final hasMore = moodData.$3;

          return RefreshIndicator(
            onRefresh: () => loadData(force: true),
            color: context.palette.primary,
            backgroundColor: context.palette.canvas,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VPSectionHeader(title: context.loc.mood_recents),
                  if (recentEmojis.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        context.loc.mood_noneSet,
                        style: VpWidgets.googleFont(
                          fontSize: 14,
                          color: context.palette.contentDisabled,
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
                        itemCount: recentEmojis.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) =>
                            _buildRecentItem(recentEmojis[index], index == 0),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: GestureDetector(
                      onTap: _showEmojiPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        decoration: BoxDecoration(
                          color: context.palette.isDark
                              ? null
                              : context.palette.surfaceGroup,
                          gradient: context.palette.isDark
                              ? LinearGradient(
                                  colors: [
                                    AppPalette.brandGradientAccent,
                                    context.palette.primary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: context.palette.isDark
                              ? null
                              : Border.all(
                                  color: context.palette.primary
                                      .withValues(alpha: 0.2)),
                          boxShadow: [
                            VpWidgets.boxShadow(
                              context,
                              color: context.palette.isDark
                                  ? context.palette.primary
                                      .withValues(alpha: 0.4)
                                  : context.palette.shadowSoft,
                              offset: const Offset(0, 4),
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
                                    color: context.palette.isDark
                                        ? context.palette.onPrimary
                                        : context.palette.contentPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.loc.mood_howFeeling,
                                  style: VpWidgets.googleFont(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: context.palette.isDark
                                        ? context.palette.onPrimary
                                            .withValues(alpha: 0.8)
                                        : context.palette.contentSecondary,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: context.palette.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  VpWidgets.boxShadow(
                                    context,
                                    color: context.palette.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Icon(Icons.add,
                                  color: context.palette.onPrimary, size: 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                            color: context.palette.contentPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: context.palette.overlay,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(
                            context.loc.mood_today,
                            style: VpWidgets.googleFont(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: context.palette.contentTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (timeline.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        context.loc.mood_noneSet,
                        style: VpWidgets.googleFont(
                          fontSize: 14,
                          color: context.palette.contentDisabled,
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
                        for (var i = 0; i < timeline.length; i++)
                          _buildTimelineItem(
                            emoji: timeline[i].emoji,
                            timestamp: timeline[i].createdAt,
                            color: timeline[i].isMine
                                ? context.palette.primary
                                : context.palette.accentPink,
                            isLast: i == timeline.length - 1 && !hasMore,
                          ),
                        if (hasMore)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: () => unawaited(context
                                    .read<MoodState>()
                                    .loadMoreTimeline()),
                                icon: Icon(Icons.expand_more,
                                    color: context.palette.primary),
                                label: Text(
                                  context.loc.mood_showMore,
                                  style: VpWidgets.googleFont(
                                    color: context.palette.primary,
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
            ),
          );
        },
      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItem(String emoji, bool isSelected) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: isSelected
            ? context.palette.primary.withValues(alpha: 0.1)
            : context.palette.canvas.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? context.palette.primary.withValues(alpha: 0.5)
              : context.palette.overlay,
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
                color: context.palette.contentPrimary,
                fontSize: 16,
              ),
            ),
            Text(
              timeFormat.format(parsed),
              style: VpWidgets.googleFont(
                fontWeight: FontWeight.w500,
                color: context.palette.contentDisabled,
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
            color: context.palette.contentPrimary,
            fontSize: 16,
          ),
        );
      }
    } else {
      content = Text(
        context.loc.mood_noneSet,
        style: VpWidgets.googleFont(
          fontWeight: FontWeight.bold,
          color: context.palette.contentPrimary,
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
                  context,
                  borderRadius: 16,
                  borderColor: color.withValues(alpha: 0.4),
                  boxShadow: [
                    VpWidgets.boxShadow(
                        context,
                        color: context.palette.shadowSoft,
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
                    color: context.palette.overlay,
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
