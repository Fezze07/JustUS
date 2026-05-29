// =============================================================================
// JustUs App - Version Control Models
// =============================================================================

abstract class VersionModels {}

class AppVersionResponse {
  final String version;
  final String apkUrl;
  final String changelog;

  AppVersionResponse({
    required this.version,
    required this.apkUrl,
    required this.changelog,
  });

  factory AppVersionResponse.fromJson(Map<String, dynamic> json) {
    return AppVersionResponse(
      version: (json['version'] as String?) ?? '',
      apkUrl: (json['apk_url'] as String?) ?? '',
      changelog: (json['changelog'] as String?) ?? '',
    );
  }
}
