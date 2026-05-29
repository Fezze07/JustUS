import 'package:justus/all_imports.dart';

class MissYouRepository extends BaseRepository {
  MissYouRepository({super.sbClient});

  Future<ResultWrapper<MissYouResponse>> sendMissYou() async {
    return tryCall(() async {
      await sbClient.rpc('send_missyou');

      final result = await fetchMissYouTotal();
      if (result is Success<MissYouResponse>) {
        return result.value;
      }

      return MissYouResponse(success: true, total: 0);
    });
  }

  Future<ResultWrapper<MissYouResponse>> fetchMissYouTotal() async {
    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      if (partnershipId == null) return MissYouResponse(success: true, total: 0);

      final count = await sbClient
          .from('missyou')
          .count()
          .eq('partnership_id', partnershipId);

      return MissYouResponse(success: true, total: count);
    });
  }
}
