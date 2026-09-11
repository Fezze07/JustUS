// =============================================================================
// JustUs App - Version Control Models
// =============================================================================

abstract class VersionModels {}

class AppVersionResponse {
  final String version;
  final int build;
  final int minBuild;
  final bool forceUpdate;
  final String apkUrl;
  final String changelog;

  AppVersionResponse({
    required this.version,
    required this.build,
    required this.minBuild,
    required this.forceUpdate,
    required this.apkUrl,
    required this.changelog,
  });

  factory AppVersionResponse.fromJson(Map<String, dynamic> json) {
    return AppVersionResponse(
      version: (json['version'] as String?) ?? '',
      build: (json['build'] as num?)?.toInt() ?? 0,
      minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
      forceUpdate: json['force_update'] == true,
      apkUrl: (json['apk_url'] as String?) ?? '',
      changelog: (json['changelog'] as String?) ?? '',
    );
  }
}
