import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:justus/all_imports.dart';

class ProtectedNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit? fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final double? width;
  final double? height;
  final BaseCacheManager? cacheManager;

  const ProtectedNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.cacheManager,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ApiService.resolveProtectedMediaUrl(url) ?? url;

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      httpHeaders: ApiService.authHeaders,
      fit: fit,
      width: width,
      height: height,
      cacheManager: cacheManager,
      placeholder: placeholder ?? (_, __) => const Center(child: CircularProgressIndicator()),
      errorWidget: errorWidget ?? (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64)),
    );
  }
}
