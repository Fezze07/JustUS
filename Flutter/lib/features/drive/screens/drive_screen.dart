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

class DriveScreen extends StatefulWidget {
  final bool isActive;
  const DriveScreen({super.key, this.isActive = false});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  // ImagePicker moved to MediaPickerService
  
  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant DriveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadData();
    }
  }

  void _loadData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<DriveState>().initialLoad());
    });
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
      backgroundColor: AppColors.deepViolet,
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
                color: AppColors.neonPurple.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonPurple.withValues(alpha: 0.3),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Custom App Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        VPCircleButton(
                          icon: Icons.chevron_left,
                          color: AppColors.neonPurple,
                          onTap: () => Navigator.pop(context),
                        ),
                        Column(
                          children: [
                            Text(
                              context.loc.drive_title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  const BoxShadow(
                                    color: AppColors.neonPurple,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              context.loc.drive_subtitle,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.neonPurple.withValues(alpha: 0.8),
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            context.loc.drive_select,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.accentAqua,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Filter Chips
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        VPFilterChip(label: context.loc.drive_filterAll, isActive: true),
                        const SizedBox(width: 12),
                        VPFilterChip(label: context.loc.drive_filterPhotos),
                        const SizedBox(width: 12),
                        VPFilterChip(label: context.loc.drive_filterVideos),
                        const SizedBox(width: 12),
                        VPFilterChip(label: context.loc.drive_filterLikes, icon: Icons.favorite, iconColor: Colors.red),
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
                            color: AppColors.neonPurple,
                            letterSpacing: 2.0,
                            shadows: [
                              const BoxShadow(
                                color: AppColors.neonPurple,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.neonPurple.withValues(alpha: 0.5),
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

                // Grid Content
                Consumer<DriveState>(
                  builder: (context, state, _) {
                    if (state.isLoading && state.driveItems.isEmpty) {
                      return const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator(color: AppColors.neonPurple)),
                      );
                    }

                    if (state.driveItems.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                              const SizedBox(height: 16),
                              Text(
                                context.loc.drive_emptyTitle,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white.withValues(alpha: 0.5),
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
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = state.driveItems[index];
                            
                            return _buildGridItem(context, item, index);
                          },
                          childCount: state.driveItems.length,
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

          // Upload FAB
          Positioned(
            bottom: 32,
            right: 24,
            child: _buildFloatingActionButton(),
          ),
          
          // Upload Progress
          Consumer<DriveState>(
            builder: (context, state, _) {
              return const DriveUploadProgressBanner();
            },
          ),
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
        unawaited(Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriveItemScreen(itemId: item.id),
          ),
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isHighlighted ? Border.all(color: AppColors.neonPurple, width: 2) : null,
          boxShadow: isHighlighted ? [
            const BoxShadow(
              color: AppColors.neonPurple,
              blurRadius: 8,
            )
          ] : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // CachedNetworkImage via MediaCacheManager: R2 filename → signed URL → cached locally
            CachedNetworkImage(
              imageUrl: item.content,
              cacheManager: MediaCacheManager(),
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: const Color(0xFF1E0B36),
                child: const Center(
                  child: Icon(Icons.image, color: Colors.white24, size: 24),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF1E0B36),
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.white24),
                ),
              ),
            ),
            
            // Video indicator overlay
            if (item.type.toLowerCase().contains('video') || item.content.toLowerCase().endsWith('.mp4'))
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(Icons.play_circle, color: Colors.white, size: 32),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.accentAqua,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentAqua.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(20),
          child: const Center(
            child: Icon(
              Icons.add_photo_alternate,
              color: AppColors.deepViolet,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}
