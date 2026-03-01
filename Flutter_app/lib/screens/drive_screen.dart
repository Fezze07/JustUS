// =============================================================================
// DriveScreen - "Our Memories" Gallery with Violet-Punk Design
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants/app_colors.dart';
import '../state/drive_state.dart';
import 'drive_item_screen.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  final _imagePicker = ImagePicker();
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DriveState>().initialLoad();
    });
  }

  Future<void> _pickFile() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepViolet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.neonPurple),
              title: Text('Take Photo', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accentAqua),
              title: Text('From Gallery', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera);
    if (photo != null) await _uploadFile(photo);
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) await _uploadFile(image);
  }

  Future<void> _uploadFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    context.read<DriveState>().addFileItem(
      bytes,
      file.name,
      bytes.length,
      file.mimeType ?? 'image/jpeg',
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
                color: AppColors.neonPurple.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonPurple.withOpacity(0.3),
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
                        _buildCircleButton(
                          icon: Icons.chevron_left,
                          color: AppColors.neonPurple,
                          onTap: () => Navigator.pop(context),
                        ),
                        Column(
                          children: [
                            Text(
                              'Our Memories',
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
                              'VIOLET ARCHIVE',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.neonPurple.withOpacity(0.8),
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'SELECT',
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
                        _buildFilterChip('All', isActive: true),
                        const SizedBox(width: 12),
                        _buildFilterChip('Photos'),
                        const SizedBox(width: 12),
                        _buildFilterChip('Videos'),
                        const SizedBox(width: 12),
                        _buildFilterChip('Likes', icon: Icons.favorite, iconColor: Colors.red),
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
                          'LATEST VIBES',
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
                                  AppColors.neonPurple.withOpacity(0.5),
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
                              Icon(Icons.photo_library_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                'No Vibes Yet',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white.withOpacity(0.5),
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
                          childAspectRatio: 1.0,
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
              if (state.isUploading) {
                return Positioned(
                  bottom: 100,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0B36),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonPurple)
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Uploading...', 
                          style: GoogleFonts.plusJakartaSans(color: Colors.white)
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {bool isActive = false, IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? AppColors.neonPurple : const Color(0xFF1E0B36),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.neonPurple.withOpacity(0.3),
        ),
        boxShadow: isActive ? [
          const BoxShadow(
            color: AppColors.neonPurple,
            blurRadius: 8,
            spreadRadius: 0,
          )
        ] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: isActive ? Colors.white : Colors.grey[300],
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, dynamic item, int index) {
    // Determine if we should highlight this item (e.g. first item borders)
    final isHighlighted = index == 0;
    
    return GestureDetector(
      onTap: () {
        context.read<DriveState>().loadSingleItem(item.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriveItemScreen(itemId: item.id),
          ),
        );
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
            // Use CachedNetworkImage for better performance and caching
            CachedNetworkImage(
              imageUrl: item.content,
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
            
            // Video indicator overlay if needed (mocked based on mime type or extension)
            if (item.type.contains('video') || item.content.endsWith('.mp4'))
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
            color: AppColors.accentAqua.withOpacity(0.5),
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

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            color: color,
            size: 24,
            shadows: [
              BoxShadow(
                color: color,
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


