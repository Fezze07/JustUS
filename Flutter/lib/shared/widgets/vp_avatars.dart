import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class VPAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final Color? borderColor;
  final bool isUploading;

  const VPAvatar({
    super.key,
    this.imageUrl,
    this.size = 80,
    this.borderColor,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveProtectedMediaUrl(imageUrl);
    final ring = borderColor ?? context.palette.accentPink;

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2),
            boxShadow: [
              BoxShadow(
                color: ring.withValues(alpha: 0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: resolved == null
              ? SizedBox(
                  width: size,
                  height: size,
                  child: Icon(Icons.person,
                      size: size / 2, color: context.palette.contentTertiary),
                )
              : ClipOval(
                  child: ProtectedNetworkImage(
                    url: imageUrl!,
                    cacheManager: MediaCacheManager(),
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    placeholder: (context, url) => SizedBox(
                      width: size,
                      height: size,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => SizedBox(
                      width: size,
                      height: size,
                      child: Icon(Icons.error,
                          color: context.palette.contentTertiary),
                    ),
                  ),
                ),
        ),
        if (isUploading)
          Positioned.fill(
            child: Center(
              child: CircularProgressIndicator(color: ring),
            ),
          ),
      ],
    );
  }
}

class VPUserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final Widget? indicator;
  final double size;

  const VPUserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.indicator,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            VPAvatar(
              imageUrl: imageUrl,
              size: size,
              borderColor: context.palette.overlay,
            ),
            if (indicator != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: indicator!,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: VpWidgets.googleFont(
            color: context.palette.contentPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
