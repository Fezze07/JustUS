import 'package:flutter_test/flutter_test.dart';

/// Lets every already-scheduled microtask and zero-duration timer callback run.
///
/// Replaces the hand-rolled `for (var i = 0; i < 20; i++) await
/// Future.delayed(Duration.zero)` loops that used to be copy-pasted into each
/// cache-write test: the loop count was a magic number that silently under-ran
/// whenever a production step added another `await`, turning a real ordering
/// bug into a green test.
Future<void> settleMicrotasks([int times = 50]) {
  return pumpEventQueue(times: times);
}
