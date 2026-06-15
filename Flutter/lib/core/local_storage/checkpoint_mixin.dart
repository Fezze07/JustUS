import 'package:justus/all_imports.dart';

mixin CheckpointMixin {
  Future<void> saveMaxTimestampCheckpoint({
    required String checkpointKey,
    required List<String?> timestamps,
  }) async {
    final parsed = timestamps
        .whereType<String>()
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (parsed.isNotEmpty) {
      await CacheService.saveCheckpoint(
        checkpointKey,
        parsed.first.toUtc().toIso8601String(),
      );
    } else {
      await CacheService.saveCheckpoint(
        checkpointKey,
        CacheService.kCheckpointEmpty,
      );
    }
  }

  Future<void> saveMaxTimestampCheckpointFromItems({
    required String checkpointKey,
    required List<dynamic> items,
    required String Function(dynamic item) timestampField,
  }) async {
    final rawTimestamps = items.map(timestampField).toList();
    final parsed = rawTimestamps
        .whereType<String>()
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (parsed.isNotEmpty) {
      await CacheService.saveCheckpoint(
        checkpointKey,
        parsed.first.toUtc().toIso8601String(),
      );
    } else {
      await CacheService.saveCheckpoint(
        checkpointKey,
        CacheService.kCheckpointEmpty,
      );
    }
  }
}
