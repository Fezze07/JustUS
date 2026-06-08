// =============================================================================
// FavoritesScreen - Display favorite drive items
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    // Load drive items if not already loaded
    final driveState = context.read<DriveState>();
    if (driveState.driveItems.isEmpty) {
      unawaited(driveState.initialLoad());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.drive_favoritesTitle),
        centerTitle: true,
      ),
      body: Consumer<DriveState>(
        builder: (context, state, _) {
          final favorites = state.favoriteItems;

          if (state.isLoading && favorites.isEmpty) {
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
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
                  state.loadSingleItem(item.id);
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
    );
  }
}
