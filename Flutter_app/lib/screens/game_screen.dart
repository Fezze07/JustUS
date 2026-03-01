// =============================================================================
// GameScreen - Daily Couple Game with Violet-Punk Design
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../state/game_state.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: AppColors.neonPurple, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'JustUS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonPurple,
                          shadows: [
                            const BoxShadow(color: AppColors.neonPurple, blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildNotificationButton(),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Consumer<GameState>(
                builder: (context, state, _) {
                  if (state.isLoading && state.currentQuestion == null) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.neonPurple));
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        
                        // Daily Game Card
                        _buildDailyGameCard(state),
                        
                        const SizedBox(height: 32),
                        
                        // Status Section (You vs Partner)
                        _buildStatusSection(),
                        
                        const SizedBox(height: 48),
                        
                        // History Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'History',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Text(
                              'View All',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.neonBlue,
                                shadows: [const BoxShadow(color: AppColors.neonBlue, blurRadius: 8)],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHistoryList(),
                        const SizedBox(height: 32),
                      ],
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
            border: Border.all(color: AppColors.neonPurple.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Glow effect top right
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: AppColors.neonPurple, blurRadius: 50, spreadRadius: 10)],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neonPurple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
                  ),
                  child: Text(
                    'DAILY GAME',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.neonPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                if (state.currentQuestion != null) ...[
                   Text(
                    'Question of the Day',
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
                       fontSize: 20, // Reduced from 24 for better fit
                       fontWeight: FontWeight.bold,
                       color: Colors.white,
                       height: 1.3,
                     ),
                   ),
                   const SizedBox(height: 32),
                   
                   // Options
                   _buildOptionButton(context, state, 'A', state.currentQuestion!.optionA, Colors.blue),
                   const SizedBox(height: 16),
                   _buildOptionButton(context, state, 'B', state.currentQuestion!.optionB, Colors.purple),
                   
                ] else ...[
                   const Icon(Icons.check_circle, size: 64, color: AppColors.neonGreen),
                   const SizedBox(height: 16),
                   Text(
                     "You're all caught up!",
                     style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                   ),
                   const SizedBox(height: 8),
                   TextButton(
                     onPressed: () => state.fetchNewQuestion(),
                     child: const Text('Try Fetching Again', style: TextStyle(color: AppColors.neonBlue)),
                   ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(BuildContext context, GameState state, String answerCode, String text, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: state.isLoading ? null : () => state.submitAnswer(answerCode),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color.withOpacity(0.8), // Text color
          disabledBackgroundColor: Colors.white10,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withOpacity(0.5)),
          ),
        ),
        child: Text(
           text,
           style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatusAvatar(
          name: 'You',
          status: 'DONE',
          imageUrl: null, // Should pull from profile
          isDone: true,
        ),
        _buildStatusAvatar(
          name: 'Partner',
          status: 'Waiting...',
          imageUrl: null,
          isDone: false,
        ),
      ],
    );
  }

  Widget _buildStatusAvatar({required String name, required String status, String? imageUrl, required bool isDone}) {
    return Column(
      children: [
        Stack(
          children: [
             Container(
               width: 80,
               height: 80,
               decoration: BoxDecoration(
                 shape: BoxShape.circle,
                 border: Border.all(
                   color: isDone ? AppColors.neonPurple : Colors.white10,
                   width: 3,
                 ),
                 boxShadow: isDone ? [
                   const BoxShadow(color: AppColors.neonPurple, blurRadius: 15, spreadRadius: -2),
                 ] : [],
               ),
               child: CircleAvatar(
                 backgroundColor: AppColors.cardDark,
                 backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                 child: imageUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white24) : null,
               ),
             ),
             if (isDone)
               Positioned(
                 right: 0,
                 bottom: 0,
                 child: Container(
                   padding: const EdgeInsets.all(4),
                   decoration: const BoxDecoration(
                     color: AppColors.backgroundDark,
                     shape: BoxShape.circle,
                   ),
                   child: const Icon(Icons.check_circle, color: AppColors.neonPurple, size: 24),
                 ),
               ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        isDone 
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonPurple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
              ),
              child: Text(
                'DONE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.neonPurple,
                ),
              ),
            )
          : Text(
              'Waiting...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.white38,
              ),
            ),
      ],
    );
  }

  Widget _buildHistoryList() {
    // Mock history items
    return Column(
      children: [
        _buildHistoryItem(
          question: 'Who is better at saving money?',
          status: 'You both agreed!',
          badgeColor: AppColors.neonGreen,
          icon: Icons.check_circle,
        ),
        const SizedBox(height: 12),
        _buildHistoryItem(
          question: 'Who takes longer to get ready?',
          status: 'A playful disagreement',
          badgeColor: AppColors.neonPink,
          icon: Icons.cancel,
        ),
        const SizedBox(height: 12),
        _buildHistoryItem(
          question: 'Who fell in love first?',
          status: 'Matched 3 days ago',
          badgeColor: AppColors.neonBlue,
          icon: Icons.check_circle,
        ),
      ],
    );
  }

  Widget _buildHistoryItem({
    required String question,
    required String status,
    required Color badgeColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          // Subtle glow on hover effect simulation
          BoxShadow(
            color: badgeColor.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Icon(icon, color: badgeColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Mini avatars
          SizedBox(
            width: 50,
            child: Stack(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.backgroundDark, width: 2),
                  ),
                  child: const Icon(Icons.person, size: 16, color: Colors.white54),
                ),
                Positioned(
                  left: 16,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.backgroundDark, width: 2),
                    ),
                    child: const Icon(Icons.person, size: 16, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
