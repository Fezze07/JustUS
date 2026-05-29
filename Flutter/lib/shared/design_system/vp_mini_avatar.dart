import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class VPMiniAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const VPMiniAvatar({
    super.key,
    this.imageUrl,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveProtectedMediaUrl(imageUrl);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.backgroundDark, width: 2),
      ),
      child: ClipOval(
        child: resolved != null
            ? Image.network(
                resolved,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: Colors.white24,
      ),
    );
  }
}
