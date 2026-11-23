import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/core/network/api_client.dart';
import 'package:ridesync/core/storage/location_queue.dart';
import 'package:ridesync/features/offline_sync/sync_manager.dart';
import 'package:ridesync/models/location_point.dart';

import 'helpers/fakes.dart';

int _seq = 0;

Future<LocationQueue> _queue({int max = 10000}) async =>
    LocationQueue(await openTempBox('location_queue_${_seq++}'), maxPoints: max);

LocationPoint _p(int i) => LocationPoint(
      lat: 20 + i / 1000,
      lng: 85,
      recordedAt: DateTime.utc(2026, 1, 1, 10).add(Duration(seconds: 4 * i)),
    );

void main() {
  test('enqueue keeps FIFO order and survives as JSON maps', () async {
    final q = await _queue();
    for (var i = 0; i < 3; i++) {
      await q.enqueue(_p(i));
    }
    final (keys, pts) = q.peek(10);
    expect(keys, hasLength(3));
    expect([for (final p in pts) p.lat], [20.0, 20.001, 20.002]);
    expect(pts.first.toJson()['recorded_at'], '2026-01-01T10:00:00.000Z');
  });

  test('flush uploads oldest-first in batches and clears on success', () async {
    final q = await _queue();
    for (var i = 0; i < 5; i++) {
      await q.enqueue(_p(i));
    }
    final batches = <List<Map<String, dynamic>>>[];
    final sync = SyncManager(
      queue: q,
      batchSize: 2,
      upload: (pts) async {
        batches.add(pts);
        return pts.length;
      },
    );
    expect(await sync.flush(), SyncResult.synced);
    expect([for (final b in batches) b.length], [2, 2, 1]);
    expect(batches.first.first['lat'], 20.0);
    expect(q.isEmpty, isTrue);
    expect(await sync.flush(), SyncResult.nothingToDo);
  });

  test('a failed upload keeps every queued point', () async {
    final q = await _queue();
    for (var i = 0; i < 3; i++) {
      await q.enqueue(_p(i));
    }
    final sync = SyncManager(
      queue: q,
      upload: (_) async => throw const ApiException(ApiErrorKind.network),
    );
    expect(await sync.flush(), SyncResult.failedKept);
    expect(q.length, 3);

    final server = SyncManager(
      queue: q,
      upload: (_) async => throw const ApiException(ApiErrorKind.server, 500),
    );
    expect(await server.flush(), SyncResult.failedKept);
    expect(q.length, 3);
  });

  test('partial failure keeps only the batches not yet accepted', () async {
    final q = await _queue();
    for (var i = 0; i < 4; i++) {
      await q.enqueue(_p(i));
    }
    var calls = 0;
    final sync = SyncManager(
      queue: q,
      batchSize: 2,
      upload: (pts) async {
        if (++calls == 2) throw const ApiException(ApiErrorKind.network);
        return pts.length;
      },
    );
    expect(await sync.flush(), SyncResult.failedKept);
    final (_, left) = q.peek(10);
    expect([for (final p in left) p.lat], [20.002, 20.003]);
  });

  test('ride gone (410/404/403) drops points that can never be accepted', () async {
    for (final kind in [ApiErrorKind.gone, ApiErrorKind.notFound, ApiErrorKind.forbidden]) {
      final q = await _queue();
      await q.enqueue(_p(0));
      final sync = SyncManager(queue: q, upload: (_) async => throw ApiException(kind));
      expect(await sync.flush(), SyncResult.dropped, reason: '$kind');
      expect(q.isEmpty, isTrue);
    }
  });

  test('queue is capped, dropping the oldest points', () async {
    final q = await _queue(max: 3);
    for (var i = 0; i < 5; i++) {
      await q.enqueue(_p(i));
    }
    final (_, pts) = q.peek(10);
    expect([for (final p in pts) p.lat], [20.002, 20.003, 20.004]);
  });

  test('concurrent flushes do not double-upload', () async {
    final q = await _queue();
    await q.enqueue(_p(0));
    var uploads = 0;
    final sync = SyncManager(queue: q, upload: (pts) async {
      uploads++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return pts.length;
    });
    final results = await Future.wait([sync.flush(), sync.flush()]);
    expect(results, containsAll([SyncResult.synced, SyncResult.busy]));
    expect(uploads, 1);
  });
}
