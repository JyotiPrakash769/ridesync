import '../../core/network/api_client.dart';
import '../../core/storage/location_queue.dart';
import '../../models/location_point.dart';

enum SyncResult { nothingToDo, synced, failedKept, dropped, busy }

typedef SyncUploader = Future<int> Function(List<Map<String, dynamic>> points);

/// Flushes queued points to POST /rides/{id}/sync.
///
/// It does not reconnect anything itself: ConvoyController calls [flush]
/// when the WsClient (the single owner of reconnect/backoff) reports
/// `connected`. The queue is cleared only after a successful response; a
/// failure keeps every point for the next reconnect. The exception is a
/// final answer from the server (ride gone / not a rider): those points can
/// never be accepted, so they are dropped.
class SyncManager {
  SyncManager({required this.queue, required this.upload, this.batchSize = 500});

  final LocationQueue queue;
  final SyncUploader upload;
  final int batchSize;
  bool _running = false;

  Future<void> enqueue(LocationPoint p) => queue.enqueue(p);

  Future<SyncResult> flush() async {
    if (_running) return SyncResult.busy;
    if (queue.isEmpty) return SyncResult.nothingToDo;
    _running = true;
    try {
      while (!queue.isEmpty) {
        final (keys, points) = queue.peek(batchSize);
        if (points.isNotEmpty) {
          await upload([for (final p in points) p.toJson()]);
        }
        await queue.remove(keys); // only after the server accepted the batch
      }
      return SyncResult.synced;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.gone ||
          e.kind == ApiErrorKind.notFound ||
          e.kind == ApiErrorKind.forbidden) {
        await queue.clear();
        return SyncResult.dropped;
      }
      return SyncResult.failedKept;
    } catch (_) {
      return SyncResult.failedKept;
    } finally {
      _running = false;
    }
  }
}
