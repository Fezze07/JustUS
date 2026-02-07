// =============================================================================
// HomepageScreen - Main screen with Miss You, navigation buttons
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import '../state/homepage_state.dart';
import '../state/mood_state.dart';
import 'mood_screen.dart';
import 'bucket_list_screen.dart';
import 'game_screen.dart';
import 'drive_screen.dart';
import 'profile_screen.dart';
import 'favorites_screen.dart';

import '../services/update_service.dart';

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen> {
  final _updateService = UpdateService();
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    
    // Check for updates once after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_updateChecked) {
        _updateService.checkVersion(context);
        _updateChecked = true;
      }
    });
  }

  Future<void> _loadData() async {
    final homepageState = context.read<HomepageState>();
    final moodState = context.read<MoodState>();

    await homepageState.init();
    await moodState.loadPartnerMoodFromCache();
    await moodState.fetchPartnerMood();
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profilo'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Preferiti'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final partnerName = authState.partnerUsername ?? 'tuo partner';

    return Scaffold(
      appBar: AppBar(
        title: const Text('JustUs 💖'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Partner mood section
              Consumer<MoodState>(
                builder: (context, moodState, _) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'Mood di $partnerName',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            moodState.partnerMood,
                            style: const TextStyle(fontSize: 48),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Miss You section
              Consumer<HomepageState>(
                builder: (context, state, _) {
                  if (state.message != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.message!)),
                      );
                      state.clearMessage();
                    });
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'Mi manchi 💗',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Totale: ${state.totalMissYou}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: state.isLoading
                                ? null
                                : () => state.sendMissYou(),
                            icon: const Icon(Icons.favorite),
                            label: const Text('Invia Mi manchi'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // Navigation buttons grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _NavButton(
                    icon: Icons.mood,
                    label: 'Mood',
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MoodScreen()),
                    ),
                  ),
                  _NavButton(
                    icon: Icons.check_box,
                    label: 'Bucket List',
                    color: Colors.green,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BucketListScreen()),
                    ),
                  ),
                  _NavButton(
                    icon: Icons.games,
                    label: 'Gioco',
                    color: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GameScreen()),
                    ),
                  ),
                  _NavButton(
                    icon: Icons.photo_library,
                    label: 'Drive',
                    color: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DriveScreen()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.8), color],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
