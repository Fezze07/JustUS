// =============================================================================
// MoodScreen - Interactive Mood Board with Violet-Punk Design
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../state/mood_state.dart';

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
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final moodState = context.read<MoodState>();
    await moodState.loadCache();
    await moodState.fetchMyMood();
    await moodState.fetchRecentEmojis();
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => _EmojiPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Mood Board',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
      ),
      body: Consumer<MoodState>(
        builder: (context, state, _) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Recents Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'YOUR RECENTS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white54,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'Edit',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: state.recentEmojis.isNotEmpty ? state.recentEmojis.length : 5,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      if (state.recentEmojis.isEmpty) {
                         // Mock recents if empty
                         const mocks = ['😊', '😌', '🥰', '⚡', '😴'];
                         return _buildRecentItem(mocks[index], "Mood", index == 0);
                      }
                      return _buildRecentItem(state.recentEmojis[index], "Mood", index == 0);
                    },
                  ),
                ),

                // Add New Mood Button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: GestureDetector(
                    onTap: _showEmojiPicker,
                    child: Container(
                      height: 100, // Increased height
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFA855F7), AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 16,
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
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'How are you feeling?',
                                style: GoogleFonts.plusJakartaSans(
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
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Icon(Icons.add, color: AppColors.deepViolet, size: 30),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Timeline
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Timeline',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Today',
                          style: GoogleFonts.plusJakartaSans(
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
                       emoji: state.userMood.isNotEmpty ? state.userMood : '😌',
                       title: 'You felt ${state.userMood.isNotEmpty ? "Updated" : "Calm"}',
                       time: 'Now',
                       description: 'Just updated your mood.',
                       color: AppColors.primary,
                       isLast: false,
                     ),
                     _buildTimelineItem(
                       emoji: '🤩',
                       title: 'Partner felt Excited',
                       time: '9:15 AM',
                       description: 'Booked tickets! 🎫',
                       color: Colors.orange,
                       isLast: false,
                     ),
                     _buildTimelineItem(
                       emoji: '😴',
                       title: 'You felt Tired',
                       time: '7:00 AM',
                       description: 'Need coffee ☕',
                       color: Colors.blueGrey,
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
            color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.backgroundDark.withOpacity(0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.primary.withOpacity(0.5) : Colors.white10,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
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
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.4), width: 2),
                  boxShadow: [
                     BoxShadow(color: Colors.black26, blurRadius: 4, offset:const Offset(0,2))
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
                         style: GoogleFonts.plusJakartaSans(
                           fontWeight: FontWeight.bold,
                           color: Colors.white,
                           fontSize: 14,
                         ),
                       ),
                       Text(
                         time,
                         style: GoogleFonts.plusJakartaSans(
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
                    style: GoogleFonts.plusJakartaSans(
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

class _EmojiPickerSheet extends StatelessWidget {
  final List<String> emojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', 
    '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩',
    '😘', '😗', '😚', '😙', '😋', '😛', '😜', '🤪',
    '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨',
    '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
    '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: AppColors.neonPurple, blurRadius: 4, offset: Offset(0, -2))
        ]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
             'Pick a Mood',
             style: GoogleFonts.plusJakartaSans(
               fontSize: 18,
               fontWeight: FontWeight.bold,
               color: Colors.white,
             ),
           ),
           const SizedBox(height: 24),
           Expanded(
             child: GridView.builder(
               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                 crossAxisCount: 6,
                 crossAxisSpacing: 12,
                 mainAxisSpacing: 12,
               ),
               itemCount: emojis.length,
               itemBuilder: (context, index) {
                 return GestureDetector(
                   onTap: () {
                     context.read<MoodState>().updateMood(emojis[index]);
                     Navigator.pop(context);
                   },
                   child: Container(
                     decoration: BoxDecoration(
                       color: Colors.white.withOpacity(0.05),
                       shape: BoxShape.circle,
                     ),
                     alignment: Alignment.center,
                     child: Text(emojis[index], style: const TextStyle(fontSize: 24)),
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
