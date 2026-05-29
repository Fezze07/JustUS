import 'package:justus/all_imports.dart';

class BucketRepository extends BaseRepository {
  BucketRepository({super.sbClient});

  Future<ResultWrapper<List<BucketItem>>> fetchBucketList() async {
    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      if (partnershipId == null) return <BucketItem>[];

      final List<dynamic> data = await sbClient
          .from('bucket_items')
          .select()
          .eq('partnership_id', partnershipId)
          .order('created_at', ascending: false);

      return data.map((b) => BucketItem.fromJson(b as Map<String, dynamic>)).toList();
    });
  }

  Future<ResultWrapper<BucketItem>> addBucketItem(String text, String? category) async {
    return withPartnership((partnershipId) async {
      final dataToInsert = {
        'text': text,
        'done': false,
        'partnership_id': partnershipId,
      };

      if (category != null && category.isNotEmpty) {
        dataToInsert['category'] = category;
      }

      final data = await sbClient.from('bucket_items').insert(dataToInsert).select().maybeSingle();

      if (data == null) throw Exception("Errore durante l'aggiunta");

      return BucketItem.fromJson(data);
    });
  }

  Future<ResultWrapper<BucketItem>> toggleBucketItem(int id, bool done) async {
    return tryCall(() async {
      final data = await sbClient
          .from('bucket_items')
          .update({'done': done})
          .eq('id', id)
          .select()
          .maybeSingle();
      if (data == null) throw Exception("Errore aggiornamento item");

      return BucketItem.fromJson(data);
    });
  }

  Future<ResultWrapper<void>> deleteBucketItem(int id) async {
    return tryCall(() async {
      await sbClient.from('bucket_items').delete().eq('id', id);
    });
  }
}
