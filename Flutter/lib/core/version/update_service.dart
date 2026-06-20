// =============================================================================
// UpdateService - App update checker and downloader
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:justus/all_imports.dart';

class UpdateService {
  final VersionRepository _repo = VersionRepository();
  bool _isDialogShowing = false;

  Future<void> checkVersion(BuildContext context) async {
    if (_isDialogShowing) return;
    if (kIsWeb) return;

    // Get local version
    final packageInfo = await PackageInfo.fromPlatform();
    final localVersion = packageInfo.version;

    // Get server version
    final result = await _repo.checkAppVersion();

    final versionInfo = result.valueOrNull;
    if (versionInfo != null) {
      final serverVersion = versionInfo.version;
      final apkUrl = versionInfo.apkUrl;
      final changelog = versionInfo.changelog;

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
    
    unawaited(() async {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(context.loc.update_availableTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.loc.update_newVersion),
              if (changelog != null && changelog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.loc.update_changelogTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(changelog),
              ],
            ],
          ),
          actions: [
            if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows)) // Allow skip on these, force on others?
              TextButton(
                onPressed: () {
                  _isDialogShowing = false;
                  Navigator.pop(context);
                },
                child: Text(context.loc.update_later),
              ),
            FilledButton(
              onPressed: () {
                unawaited(_launchUpdateUrl(apkUrl));
                // Don't close dialog immediately on click if we want to show progress
                // But for simple URL launch, we can close or keep open
                _isDialogShowing = false;
                Navigator.pop(context);
              },
              child: Text(context.loc.update_now),
            ),
          ],
        ),
      );
      _isDialogShowing = false;
    }());
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
