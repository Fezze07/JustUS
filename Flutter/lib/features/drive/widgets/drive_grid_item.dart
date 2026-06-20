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
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Content
          ClipRect(child: _buildContent()),

          // Favorite indicator
          if (item.isFavorite == 1)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.favorite, color: Colors.red, size: 16),
              ),
            ),

          // Video indicator
          if (item.type == 'video')
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.videocam, color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final mediaUrl = ApiService.resolveProtectedMediaUrl(item.content);

    switch (item.type) {
      case 'image':
        if (mediaUrl == null) {
          return Container(
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image),
          );
        }

        return CachedNetworkImage(
          imageUrl: mediaUrl,
          httpHeaders: ApiService.authHeaders,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image),
          ),
        );
      case 'video':
        return mediaUrl == null
            ? Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image),
              )
            : _VideoThumbnail(url: mediaUrl);
      case 'audio':
        return Container(
          color: Colors.blue[100],
          child: const Center(
            child: Icon(Icons.audiotrack, size: 48, color: Colors.blue),
          ),
        );
      default:
        return Container(
          color: Colors.grey[300],
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
        color: Colors.grey[800],
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
          color: Colors.black26,
          child: const Center(
            child: Icon(Icons.play_circle_outline, size: 40, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
