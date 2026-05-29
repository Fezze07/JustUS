import 'package:justus/all_imports.dart';

class VersionRepository extends BaseRepository {
  final ApiService _api;

  VersionRepository({super.sbClient, ApiService? api}) 
      : _api = api ?? ApiService();

  Future<ResultWrapper<AppVersionResponse>> checkAppVersion() async {
    return _api.getAppVersion();
  }
}
