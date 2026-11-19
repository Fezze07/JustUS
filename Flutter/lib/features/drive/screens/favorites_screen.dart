// =============================================================================
// FavoritesScreen - Display favorite drive items
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class FavoritesScreen extends TabScreen {
  const FavoritesScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with TabScreenMixin {
  @override
  Future<void> loadData({bool force = false}) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<DriveState>().loadFavorites());
    });
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      body: SafeArea(
        child: Column(
          children: [
            VPHeader(
              title: context.loc.drive_favoritesTitle,
              onBack: () => MainShell.of(context)?.switchToTab(0),
            ),
            Expanded(
              child: Selector<DriveState, (List<DriveItem>, bool, bool)>(
                selector: (_, s) => (
                  s.favoriteItems,
                  s.hasMoreFavorites,
                  s.isLoadingMoreFavorites,
                ),
                builder: (context, favData, _) {
                  final favorites = favData.$1;
                  final hasMore = favData.$2;
                  final isLoading = favData.$3;
                  final driveState = context.read<DriveState>();

                  if (isLoading && favorites.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (favorites.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '❤️',
                            style: TextStyle(fontSize: 64),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.loc.drive_noFavorites,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.loc.drive_noFavoritesSubtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: context.palette.neutralText,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: favorites.length,
                          itemBuilder: (context, index) {
                            final item = favorites[index];

                            return DriveGridItem(
                              item: item,
                              onTap: () {
                                driveState.loadSingleItem(item.id);
                                unawaited(Navigator.pushNamed(
                                  context,
                                  AppRoutes.driveItem,
                                  arguments: item.id,
                                ));
                              },
                            );
                          },
                        ),
                      ),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextButton.icon(
                            onPressed: isLoading
                                ? null
                                : () =>
                                    unawaited(driveState.loadMoreFavorites()),
                            icon: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(Icons.expand_more,
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
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
