// =============================================================================
// UpdateService - App update checker and downloader
// Dart equivalent of VersionUtils.kt
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../models/models.dart';

class UpdateService {
  final ApiRepository _repo = ApiRepository();
  bool _isDialogShowing = false;

  Future<void> checkVersion(BuildContext context) async {
    if (_isDialogShowing) return;

    // Get local version
    final packageInfo = await PackageInfo.fromPlatform();
    final localVersion = packageInfo.version;

    // Get server version
    final result = await _repo.checkAppVersion();

    if (result is Success<AppVersionResponse>) {
      final serverVersion = result.value.version;
      final apkUrl = result.value.apkUrl;
      final changelog = result.value.changelog;

      if (_isUpdateAvailable(localVersion, serverVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, apkUrl, changelog);
        }
      }
    }
  }

  bool _isUpdateAvailable(String local, String server) {
    // Simple semantic version check
    // Assumes format x.y.z
    try {
      final localParts = local.split('.').map(int.parse).toList();
      final serverParts = server.split('.').map(int.parse).toList();

      for (var i = 0; i < serverParts.length; i++) {
        if (i >= localParts.length) return true; // Server has more parts (e.g. 1.0.1 vs 1.0)
        
        if (serverParts[i] > localParts[i]) return true;
        if (serverParts[i] < localParts[i]) return false;
      }
      return false; // Equal
    } catch (e) {
      debugPrint('Error parsing versions: $e');
      return false;
    }
  }

  void _showUpdateDialog(BuildContext context, String apkUrl, String? changelog) {
    _isDialogShowing = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Aggiornamento disponibile! 🚀'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('È disponibile una nuova versione di JustUs.'),
            if (changelog != null && changelog.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Novità:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(changelog),
            ],
          ],
        ),
        actions: [
          if (Platform.isAndroid || Platform.isWindows) // Allow skip on these, force on others?
            TextButton(
              onPressed: () {
                _isDialogShowing = false;
                Navigator.pop(context);
              },
              child: const Text('Più tardi'),
            ),
          FilledButton(
            onPressed: () {
              _launchUpdateUrl(apkUrl);
              // Don't close dialog immediately on click if we want to show progress
              // But for simple URL launch, we can close or keep open
              _isDialogShowing = false;
              Navigator.pop(context);
            },
            child: const Text('Aggiorna ora'),
          ),
        ],
      ),
    ).then((_) => _isDialogShowing = false);
  }

  Future<void> _launchUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $url');
    }
  }
}
