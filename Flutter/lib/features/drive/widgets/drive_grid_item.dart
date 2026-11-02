// =============================================================================
// DriveGridItem - Grid item for drive photos/videos
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
            ClipRect(child: _buildContent(context)),

            // Favorite indicator
            if (item.isFavorite == 1)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: context.palette.scrim,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Icon(Icons.favorite,
                      color: context.palette.danger, size: 16),
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
                    color: context.palette.scrim,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Icon(Icons.videocam,
                      color: context.palette.contentPrimary, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (item.type) {
      case 'image':
      case 'video':
        final mediaUrl = ApiService.resolveProtectedMediaUrl(item.contentThumb);

        if (mediaUrl == null) {
          return Container(
            color: context.palette.neutralMuted,
            child: Icon(
              item.type == 'video'
                  ? Icons.play_circle_outline
                  : Icons.image_not_supported,
              color: context.palette.contentTertiary,
            ),
          );
        }

        return CachedNetworkImage(
          imageUrl: mediaUrl,
          httpHeaders: ApiService.authHeaders,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: context.palette.neutralMuted,
            child: Center(
              child:
                  CircularProgressIndicator(color: context.palette.accentBlue),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: context.palette.neutralMuted,
            child: Icon(Icons.broken_image,
                color: context.palette.contentTertiary),
          ),
        );
      case 'audio':
        return Container(
          color: context.palette.infoSurface,
          child: Center(
            child:
                Icon(Icons.audiotrack, size: 48, color: context.palette.info),
          ),
        );
      default:
        return Container(
          color: context.palette.neutralMuted,
          child: Center(
            child: Icon(Icons.picture_as_pdf,
                size: 48, color: context.palette.contentTertiary),
          ),
        );
    }
  }
}
