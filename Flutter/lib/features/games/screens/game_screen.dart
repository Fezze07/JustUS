// =============================================================================
// GameScreen - Daily Couple Game with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class GameScreen extends TabScreen {
  const GameScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TabScreenMixin {
  @override
  Future<void> loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kGameAnswers]);
    }

    if (!mounted) return;

    await context.read<GameState>().init();
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            VPHeader(
              title: context.loc.appTitle,
              showBackButton: false,
              leading: Icon(Icons.favorite,
                  color: context.palette.accentPurple, size: 28),
              trailing: [_buildNotificationButton()],
            ),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => loadData(force: true),
                color: context.palette.primary,
                backgroundColor: context.palette.canvas,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),

                      // Daily Game Card
                      Selector<GameState,
                          (GameNewQuestionResponse?, bool, bool)>(
                        selector: (_, s) => (
                          s.currentQuestion,
                          s.isFetchingQuestion,
                          s.isLoading
                        ),
                        builder: (context, _, __) =>
                            _buildDailyGameCard(context.read<GameState>()),
                      ),

                      const SizedBox(height: 32),

                      // Status Section (You vs Partner)
                      Consumer2<GameState, ProfileState>(
                        builder: (context, gs, ps, _) => _buildStatusSection(
                          gs.currentQuestion?.hasAnswered ?? false,
                          gs.currentQuestion?.partnerAnswered ?? false,
                          ps.userProfile,
                          ps.partnerProfile,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // History Section
                      Selector<GameState, List<GameHistoryItem>>(
                        selector: (_, s) => s.history,
                        builder: (context, history, _) {
                          final profile = context.read<ProfileState>();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              VPSectionHeader(
                                title: context.loc.game_historyTitle,
                                actionLabel: context.loc.home_viewAll,
                                onActionTap: () {},
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 16),
                              if (history.isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: Text(
                                      context.loc.game_noMatches,
                                      style: VpWidgets.googleFont(
                                        color: context.palette.contentDisabled,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ...history.take(5).map((item) {
                                  String status;
                                  Color badgeColor;
                                  IconData icon;

                                  if (item.isMatched) {
                                    status = context.loc.game_statusBothAgreed;
                                    badgeColor = context.palette.accentGreen;
                                    icon = Icons.check_circle;
                                  } else if (item.isDisagreed) {
                                    status = context.loc.game_statusDisagreed;
                                    badgeColor = context.palette.accentPink;
                                    icon = Icons.cancel;
                                  } else if (item.userOption == null &&
                                      item.partnerOption != null) {
                                    status =
                                        context.loc.game_statusWaitingForYou;
                                    badgeColor = context.palette.accentBlue;
                                    icon = Icons.access_time;
                                  } else {
                                    status = context.loc.game_statusWaiting;
                                    badgeColor = context.palette.accentBlue;
                                    icon = Icons.access_time;
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GameHistoryCard(
                                      question: item.question,
                                      status: status,
                                      badgeColor: badgeColor,
                                      icon: icon,
                                      userImageUrl:
                                          profile.userProfile?.profilePicUrl,
                                      partnerImageUrl:
                                          profile.partnerProfile?.profilePicUrl,
                                    ),
                                  );
                                }),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: context.palette.surface,
            shape: BoxShape.circle,
            border:
                Border.all(color: context.palette.accentPurple.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: context.palette.shadowStrong,
                  blurRadius: 8,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Icon(Icons.notifications,
              color: context.palette.contentPrimary, size: 24),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: context.palette.accentBlue,
              shape: BoxShape.circle,
              border: Border.all(color: context.palette.canvas, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyGameCard(GameState state) {
    return VPCard(
      padding: EdgeInsets.zero,
      borderColor: context.palette.accentPurple.withValues(alpha: 0.3),
      shadowColor: context.palette.accentPurple.withValues(alpha: 0.2),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: context.palette.accentPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: context.palette.accentPurple,
                      blurRadius: 50,
                      spreadRadius: 10)
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.palette.accentPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: context.palette.accentPurple.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    context.loc.game_dailyGame,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: context.palette.accentPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (state.isFetchingQuestion) ...[
                  CircularProgressIndicator(color: context.palette.accentPurple),
                  const SizedBox(height: 16),
                  Text(
                    context.loc.game_generatingQuestion,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.palette.contentPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.loc.game_aiGeneratingSubtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: context.palette.contentTertiary,
                    ),
                  ),
                ] else if (state.currentQuestion != null) ...[
                  Text(
                    context.loc.game_questionOfDay,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.palette.contentTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.currentQuestion!.question,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.palette.contentPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildOptionButton(context, state, 'A',
                      state.currentQuestion!.optionA, context.palette.info),
                  const SizedBox(height: 16),
                  _buildOptionButton(context, state, 'B',
                      state.currentQuestion!.optionB, context.palette.accentPurple),
                ] else ...[
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            size: 64, color: context.palette.accentGreen),
                        const SizedBox(height: 16),
                        Text(
                          context.loc.game_allCaughtUp,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.palette.contentPrimary),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => state.fetchNewQuestion(),
                          child: Text(
                            context.loc.game_tryFetchingAgain,
                            style: TextStyle(color: context.palette.accentBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(BuildContext context, GameState state,
      String answerCode, String text, Color color) {
    final hasAnswered = state.currentQuestion?.hasAnswered ?? false;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (state.isLoading || hasAnswered)
            ? null
            : () => state.submitAnswer(answerCode),
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.2),
          foregroundColor: color.withValues(alpha: 0.8),
          disabledBackgroundColor: context.palette.overlay,
          padding: AppButtonStyle.padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: color.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.contentPrimary),
        ),
      ),
    );
  }

  Widget _buildStatusSection(bool userDone, bool partnerDone, User? userProfile,
      User? partnerProfile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        VPUserAvatar(
          name: userProfile?.username ?? context.loc.common_youTitle,
          imageUrl: userProfile?.profilePicUrl,
          indicator: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: context.palette.canvas, shape: BoxShape.circle),
            child: Icon(
              userDone ? Icons.check_circle : Icons.access_time,
              color:
                  userDone ? context.palette.accentPurple : context.palette.contentDisabled,
              size: 24,
            ),
          ),
        ),
        VPUserAvatar(
          name: partnerProfile?.username ?? context.loc.common_partner,
          imageUrl: partnerProfile?.profilePicUrl,
          indicator: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: context.palette.canvas, shape: BoxShape.circle),
            child: Icon(
              partnerDone ? Icons.check_circle : Icons.access_time,
              color: partnerDone
                  ? context.palette.accentPurple
                  : context.palette.contentDisabled,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
