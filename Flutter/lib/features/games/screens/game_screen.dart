// =============================================================================
// GameScreen - Daily Couple Game with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class GameScreen extends StatefulWidget {
  final bool isActive;
  const GameScreen({super.key, this.isActive = false});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _dataLoadedOnce = false;

  Future<void> _loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kGameAnswers]);
    }

    if (!mounted) return;

    await context.read<GameState>().init();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isActive && !_dataLoadedOnce) {
      _dataLoadedOnce = true;
      unawaited(_loadData(force: true));
    }
    return VPScaffold(
      showAppBar: false,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            VPHeader(
              title: context.loc.appTitle,
              showBackButton: false,
              leading: const Icon(Icons.favorite,
                  color: AppColors.neonPurple, size: 28),
              trailing: [_buildNotificationButton()],
            ),

            // Content
            Expanded(
              child: Consumer<GameState>(
                builder: (context, state, _) {
                  return RefreshIndicator(
                    onRefresh: () => _loadData(force: true),
                    color: AppColors.primary,
                    backgroundColor: AppColors.backgroundDark,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),

                          // Daily Game Card
                          _buildDailyGameCard(state),

                          const SizedBox(height: 32),

                          // Status Section (You vs Partner)
                          Consumer<ProfileState>(
                            builder: (context, profile, _) =>
                                _buildStatusSection(profile, state),
                          ),

                          const SizedBox(height: 48),

                          // History Section
                          VPSectionHeader(
                            title: context.loc.game_historyTitle,
                            actionLabel: context.loc.home_viewAll,
                            onActionTap: () {},
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 16),
                          if (state.history.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Text(
                                  context.loc.game_noMatches,
                                  style: VpWidgets.googleFont(
                                    color: Colors.white38,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          else
                            Builder(
                              builder: (context) {
                                final profile = context.read<ProfileState>();

                                return Column(
                                  children: state.history.take(5).map((item) {
                                    String status;
                                    Color badgeColor;
                                    IconData icon;

                                    if (item.isMatched) {
                                      status =
                                          context.loc.game_statusBothAgreed;
                                      badgeColor = AppColors.neonGreen;
                                      icon = Icons.check_circle;
                                    } else if (item.isDisagreed) {
                                      status = context.loc.game_statusDisagreed;
                                      badgeColor = AppColors.neonPink;
                                      icon = Icons.cancel;
                                    } else if (item.userOption == null &&
                                        item.partnerOption != null) {
                                      status =
                                          context.loc.game_statusWaitingForYou;
                                      badgeColor = AppColors.neonBlue;
                                      icon = Icons.access_time;
                                    } else {
                                      status = context.loc.game_statusWaiting;
                                      badgeColor = AppColors.neonBlue;
                                      icon = Icons.access_time;
                                    }

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: GameHistoryCard(
                                        question: item.question,
                                        status: status,
                                        badgeColor: badgeColor,
                                        icon: icon,
                                        userImageUrl:
                                            profile.userProfile?.profilePicUrl,
                                        partnerImageUrl: profile
                                            .partnerProfile?.profilePicUrl,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          const SizedBox(height: 32),
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

  Widget _buildNotificationButton() {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            shape: BoxShape.circle,
            border:
                Border.all(color: AppColors.neonPurple.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.notifications, color: Colors.white, size: 24),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.neonBlue,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.backgroundDark, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyGameCard(GameState state) {
    return VPCard(
      padding: EdgeInsets.zero,
      borderColor: AppColors.neonPurple.withValues(alpha: 0.3),
      shadowColor: AppColors.neonPurple.withValues(alpha: 0.2),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.neonPurple,
                      blurRadius: 50,
                      spreadRadius: 10)
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neonPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: AppColors.neonPurple.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    context.loc.game_dailyGame,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.neonPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (state.isFetchingQuestion) ...[
                  const CircularProgressIndicator(color: AppColors.neonPurple),
                  const SizedBox(height: 16),
                  Text(
                    context.loc.game_generatingQuestion,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.loc.game_aiGeneratingSubtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Colors.white54,
                    ),
                  ),
                ] else if (state.currentQuestion != null) ...[
                  Text(
                    context.loc.game_questionOfDay,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.currentQuestion!.question,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildOptionButton(context, state, 'A',
                      state.currentQuestion!.optionA, Colors.blue),
                  const SizedBox(height: 16),
                  _buildOptionButton(context, state, 'B',
                      state.currentQuestion!.optionB, Colors.purple),
                ] else ...[
                  const Icon(Icons.check_circle,
                      size: 64, color: AppColors.neonGreen),
                  const SizedBox(height: 16),
                  Text(
                    context.loc.game_allCaughtUp,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => state.fetchNewQuestion(),
                    child: Text(
                      context.loc.game_tryFetchingAgain,
                      style: const TextStyle(color: AppColors.neonBlue),
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
      child: ElevatedButton(
        onPressed: (state.isLoading || hasAnswered)
            ? null
            : () => state.submitAnswer(answerCode),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.2),
          foregroundColor: color.withValues(alpha: 0.8),
          disabledBackgroundColor: Colors.white10,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStatusSection(ProfileState profile, GameState game) {
    final userDone = game.currentQuestion?.hasAnswered ?? false;
    final partnerDone = game.currentQuestion?.partnerAnswered ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        VPUserAvatar(
          name: profile.userProfile?.username ?? context.loc.common_youTitle,
          imageUrl: profile.userProfile?.profilePicUrl,
          indicator: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                color: AppColors.backgroundDark, shape: BoxShape.circle),
            child: Icon(
              userDone ? Icons.check_circle : Icons.access_time,
              color: userDone ? AppColors.neonPurple : Colors.white38,
              size: 24,
            ),
          ),
        ),
        VPUserAvatar(
          name: profile.partnerProfile?.username ?? context.loc.common_partner,
          imageUrl: profile.partnerProfile?.profilePicUrl,
          indicator: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                color: AppColors.backgroundDark, shape: BoxShape.circle),
            child: Icon(
              partnerDone ? Icons.check_circle : Icons.access_time,
              color: partnerDone ? AppColors.neonPurple : Colors.white38,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
