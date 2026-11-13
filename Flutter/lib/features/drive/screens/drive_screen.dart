// =============================================================================
// DriveScreen - "Our Memories" Gallery with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

enum _DriveFilter { all, photos, videos, likes }

class DriveScreen extends TabScreen {
  const DriveScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen>
    with TabScreenMixin, StateMessageListener<DriveState, DriveScreen> {
  _DriveFilter _filter = _DriveFilter.all;

  @override
  DriveState get messageSource => context.read<DriveState>();

  bool _matchesFilter(DriveItem item) {
    final type = item.type.toLowerCase();
    return switch (_filter) {
      _DriveFilter.all => true,
      _DriveFilter.photos => type == 'image',
      _DriveFilter.videos =>
        type == 'video' || item.content.toLowerCase().endsWith('.mp4'),
      _DriveFilter.likes => item.isFavorite == 1,
    };
  }

  @override
  Future<void> loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kDriveItems]);
    }

    if (!mounted) return;

    await context.read<DriveState>().initialLoad();
  }

  Future<void> _pickFile() async {
    final XFile? file = await MediaPickerService.showPickerSheet(context);
    if (file != null) await _uploadFile(file);
  }

  Future<void> _uploadFile(XFile file) async {
    if (!mounted) return;
    // Use new R2-based upload: compress → signed URL → R2 → Supabase metadata
    await context.read<DriveState>().addFileItemR2(
          filePath: file.path,
          mimeType: file.mimeType ?? 'image/jpeg',
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.surfaceSunken,
      body: Stack(
        children: [
          // Background Gradient effect (optional subtleness)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.accentPurple.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(
                    color: context.palette.accentPurple.withValues(alpha: 0.3),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              onRefresh: () => loadData(force: true),
              color: context.palette.primary,
              backgroundColor: context.palette.canvas,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Custom App Bar
                  SliverToBoxAdapter(
                    child: VPHeader(
                      title: context.loc.drive_title,
                      onBack: () => MainShell.of(context)?.switchToTab(0),
                    ),
                  ),

                  // Filter Chips
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          VPFilterChip(
                              label: context.loc.drive_filterAll,
                              isActive: _filter == _DriveFilter.all,
                              onTap: () =>
                                  setState(() => _filter = _DriveFilter.all)),
                          const SizedBox(width: 12),
                          VPFilterChip(
                              label: context.loc.drive_filterPhotos,
                              isActive: _filter == _DriveFilter.photos,
                              onTap: () => setState(
                                  () => _filter = _DriveFilter.photos)),
                          const SizedBox(width: 12),
                          VPFilterChip(
                              label: context.loc.drive_filterVideos,
                              isActive: _filter == _DriveFilter.videos,
                              onTap: () => setState(
                                  () => _filter = _DriveFilter.videos)),
                          const SizedBox(width: 12),
                          VPFilterChip(
                              label: context.loc.drive_filterLikes,
                              icon: Icons.favorite,
                              iconColor: context.palette.danger,
                              isActive: _filter == _DriveFilter.likes,
                              onTap: () =>
                                  setState(() => _filter = _DriveFilter.likes)),
                        ],
                      ),
                    ),
                  ),

                  // "Latest Vibes" Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Row(
                        children: [
                          Text(
                            context.loc.drive_latestVibes,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: context.palette.accentPurple,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    context.palette.accentPurple
                                        .withValues(alpha: 0.5),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Selector<DriveState, (bool, List<DriveItem>)>(
                    selector: (_, s) => (s.isLoading, s.driveItems),
                    builder: (context, driveData, _) {
                      final isLoading = driveData.$1;
                      final allItems = driveData.$2;
                      final items = allItems.where(_matchesFilter).toList();

                      if (isLoading && allItems.isEmpty) {
                        return SliverFillRemaining(
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: context.palette.accentPurple)),
                        );
                      }

                      if (items.isEmpty) {
                        return SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.photo_library_outlined,
                                    size: 64, color: context.palette.glass),
                                const SizedBox(height: 16),
                                Text(
                                  allItems.isEmpty
                                      ? context.loc.drive_emptyTitle
                                      : context.loc.drive_noFilteredResults,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: context.palette.contentPrimary
                                        .withValues(alpha: 0.5),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _buildGridItem(
                                  context, items[index], index);
                            },
                            childCount: items.length,
                          ),
                        ),
                      );
                    },
                  ),

                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),

          // Upload FAB
          Positioned(
            bottom: 32,
            right: 24,
            child: _buildFloatingActionButton(),
          ),

          const DriveUploadProgressBanner(),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, DriveItem item, int index) {
    // Determine if we should highlight this item (e.g. first item borders)
    final isHighlighted = index == 0;

    return GestureDetector(
      onTap: () {
        context.read<DriveState>().loadSingleItem(item.id);
        unawaited(Navigator.pushNamed(
          context,
          AppRoutes.driveItem,
          arguments: item.id,
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: isHighlighted
              ? Border.all(color: context.palette.accentPurple, width: 2)
              : null,
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: context.palette.accentPurple,
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildGridContent(context, item),

            // Video indicator overlay
            if (item.type.toLowerCase().contains('video') ||
                item.content.toLowerCase().endsWith('.mp4'))
              Container(
                color: context.palette.shadowSoft,
                child: Center(
                  child: Icon(Icons.play_circle,
                      color: context.palette.contentPrimary, size: 32),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridContent(BuildContext context, DriveItem item) {
    final type = item.type.toLowerCase();

    if (type == 'image' || type == 'video') {
      final thumb = item.contentThumb;
      if (thumb == null) {
        return _gridPlaceholder(
          context,
          type == 'video'
              ? Icons.play_circle_outline
              : Icons.image_not_supported,
        );
      }

      // CachedNetworkImage via MediaCacheManager: R2 filename → signed URL → cached locally
      return CachedNetworkImage(
        imageUrl: thumb,
        cacheManager: MediaCacheManager(),
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: context.palette.surfaceElevated,
          child: Center(
            child:
                Icon(Icons.image, color: context.palette.contentHint, size: 24),
          ),
        ),
        errorWidget: (context, url, error) => _gridPlaceholder(
          context,
          Icons.broken_image,
        ),
      );
    }

    return _gridPlaceholder(
      context,
      type == 'audio' ? Icons.audiotrack : Icons.picture_as_pdf,
    );
  }

  Widget _gridPlaceholder(BuildContext context, IconData icon) {
    return Container(
      color: context.palette.surfaceElevated,
      child: Center(
        child: Icon(icon, color: context.palette.contentHint, size: 24),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: context.palette.primary,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: context.palette.primary.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Center(
            child: Icon(
              Icons.add_photo_alternate,
              color: context.palette.onPrimary,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}
