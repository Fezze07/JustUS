import 'package:justus/all_imports.dart';

mixin CheckpointMixin {
  /// Saves the max-timestamp checkpoint from [timestamps].
  ///
  /// [writerToken]/[currentToken] implement the R-1 write-order guard: the
  /// caller captures a monotonic per-feature token at fetch *start* and passes
  /// it as [writerToken]; if a newer refresh began (bumping [currentToken]) the
  /// stale writer is skipped so an older-observed snapshot can never REGRESS a
  /// checkpoint already written by a newer one (F-RT10). null disables the
  /// guard.
  Future<void> saveMaxTimestampCheckpoint({
    required String checkpointKey,
    required List<String?> timestamps,
    int? epoch,
    int? writerToken,
    int? currentToken,
  }) async {
    if (writerToken != null && writerToken != currentToken) return;

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
        epoch: epoch,
      );
    } else {
      await CacheService.saveCheckpoint(
        checkpointKey,
        CacheService.kCheckpointEmpty,
        epoch: epoch,
      );
    }
  }

  /// Like [saveMaxTimestampCheckpoint], reading timestamps from [items].
  Future<void> saveMaxTimestampCheckpointFromItems({
    required String checkpointKey,
    required List<dynamic> items,
    required String Function(dynamic item) timestampField,
    int? epoch,
    int? writerToken,
    int? currentToken,
  }) async {
    if (writerToken != null && writerToken != currentToken) return;

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
        epoch: epoch,
      );
    } else {
      await CacheService.saveCheckpoint(
        checkpointKey,
        CacheService.kCheckpointEmpty,
        epoch: epoch,
      );
    }
  }
}
