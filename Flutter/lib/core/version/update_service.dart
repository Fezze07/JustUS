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

    final packageInfo = await PackageInfo.fromPlatform();
    final localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    AnsiLogger.log(
      'App locale: version=${packageInfo.version} build=$localBuild',
      color: AnsiLogger.orange,
      tag: 'UpdateService',
    );

    final result = await _repo.checkAppVersion();

    final versionInfo = result.valueOrNull;
    if (versionInfo == null) return;

    AnsiLogger.log(
      'Server: version=${versionInfo.version} build=${versionInfo.build} '
      'min_build=${versionInfo.minBuild}',
      color: AnsiLogger.orange,
      tag: 'UpdateService',
    );

    final serverBuild = versionInfo.build;

    if (localBuild >= serverBuild) return;

    final bool mandatory = versionInfo.forceUpdate ||
        localBuild < versionInfo.minBuild;

    if (context.mounted) {
      _showUpdateDialog(context, versionInfo, mandatory);
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    AppVersionResponse versionInfo,
    bool mandatory,
  ) {
    _isDialogShowing = true;

    unawaited(() async {
      await showDialog(
        context: context,
        barrierDismissible: !mandatory,
        builder: (context) => VPDialog(
          title: context.loc.update_availableTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.loc.update_newVersion),
              if (versionInfo.changelog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.loc.update_changelogTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(versionInfo.changelog),
              ],
            ],
          ),
          actions: [
            if (!mandatory &&
                !kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.windows))
              TextButton(
                onPressed: () {
                  _isDialogShowing = false;
                  Navigator.pop(context);
                },
                child: Text(context.loc.update_later),
              ),
            FilledButton(
              onPressed: () {
                unawaited(_launchUpdateUrl(versionInfo.apkUrl));
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
      AnsiLogger.error('Could not launch $url', tag: 'UpdateService');
    }
  }
}
