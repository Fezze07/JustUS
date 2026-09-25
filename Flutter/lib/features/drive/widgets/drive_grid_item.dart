// =============================================================================
// DriveGridItem - Grid item for drive photos/videos
// =============================================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:justus/all_imports.dart';

class DriveGridItem extends StatelessWidget {
  final DriveItem item;
  final VoidCallback onTap;

  const DriveGridItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.loc.drive_openTooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Content
            ClipRect(child: _buildContent()),

            // Favorite indicator
            if (item.isFavorite == 1)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.scrim,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Icon(Icons.favorite,
                      color: AppColors.danger, size: 16),
                ),
              ),

            // Video indicator
            if (item.type == 'video')
              Positioned(
                bottom: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.scrim,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Icon(Icons.videocam,
                      color: AppColors.contentPrimary, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final mediaUrl = ApiService.resolveProtectedMediaUrl(item.contentThumb);

    switch (item.type) {
      case 'image':
        if (mediaUrl == null) {
          return Container(
            color: AppColors.neutralMuted,
            child: const Icon(Icons.broken_image),
          );
        }

        return CachedNetworkImage(
          imageUrl: mediaUrl,
          httpHeaders: ApiService.authHeaders,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: AppColors.neutralMuted,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.neutralMuted,
            child: const Icon(Icons.broken_image),
          ),
        );
      case 'video':
        return mediaUrl == null
            ? Container(
                color: AppColors.neutralMuted,
                child: const Icon(Icons.broken_image),
              )
            : _VideoThumbnail(url: mediaUrl);
      case 'audio':
        return Container(
          color: AppColors.infoSurface,
          child: const Center(
            child: Icon(Icons.audiotrack, size: 48, color: AppColors.info),
          ),
        );
      default:
        return Container(
          color: AppColors.neutralMuted,
          child: const Center(
            child: Icon(Icons.insert_drive_file, size: 48),
          ),
        );
    }
  }
}

class _VideoThumbnail extends StatefulWidget {
  final String url;
  const _VideoThumbnail({required this.url});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: ApiService.authHeaders,
    );
    unawaited(_initializeController());
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      AnsiLogger.error('Error initializing video: $e', tag: 'VideoThumbnail');
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        color: AppColors.neutralStrong,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
        Container(
          color: AppColors.shadowSoft,
          child: const Center(
            child: Icon(Icons.play_circle_outline,
                size: 40, color: AppColors.contentSecondary),
          ),
        ),
      ],
    );
  }
}
