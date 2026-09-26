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
      final driveState = context.read<DriveState>();
      if (driveState.driveItems.isEmpty) {
        unawaited(driveState.initialLoad());
      }
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
              onBack: () => MainShell.shellKey.currentState?.switchToTab(0),
            ),
            Expanded(
              child: Selector<DriveState, (bool, List<DriveItem>)>(
        selector: (_, s) => (s.isLoading, s.favoriteItems),
        builder: (context, favData, _) {
          final isLoading = favData.$1;
          final favorites = favData.$2;
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: context.palette.canvas,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.loc.drive_noFavoritesSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.palette.neutralText,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                  unawaited(Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriveItemScreen(itemId: item.id),
                    ),
                  ));
                },
              );
            },
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
