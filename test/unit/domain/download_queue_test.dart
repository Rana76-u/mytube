import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/download_queue.dart';

void main() {
  group('ordering and concurrency', () {
    test('fills slots in FIFO order up to maxConcurrent', () {
      final q = DownloadQueue<String>(maxConcurrent: 2);
      q.enqueue('a');
      q.enqueue('b');
      q.enqueue('c');
      expect(q.running, ['a', 'b']);
      expect(q.queued, ['c']);
      expect(q.runningCount, lessThanOrEqualTo(2));
    });

    test('promotes the next queued job when one completes', () {
      final q = DownloadQueue<String>(maxConcurrent: 2);
      for (final id in ['a', 'b', 'c', 'd']) {
        q.enqueue(id);
      }
      q.complete('a');
      expect(q.running, ['b', 'c']);
      expect(q.queued, ['d']);

      q.complete('b');
      expect(q.running, ['c', 'd']);
      expect(q.queued, isEmpty);
    });

    test('maxConcurrent 1 runs strictly one at a time', () {
      final q = DownloadQueue<String>(maxConcurrent: 1);
      q.enqueue('a');
      q.enqueue('b');
      expect(q.running, ['a']);
      expect(q.queued, ['b']);
      q.complete('a');
      expect(q.running, ['b']);
    });
  });

  group('queued cap', () {
    test('refuses new jobs once the queue is full', () {
      final q = DownloadQueue<String>(maxConcurrent: 1, maxQueued: 2);
      expect(q.enqueue('run'), isTrue); // occupies the slot
      expect(q.enqueue('q1'), isTrue);
      expect(q.enqueue('q2'), isTrue);
      expect(q.enqueue('q3'), isFalse); // over cap
      expect(q.queuedCount, 2);
    });
  });

  group('idempotence', () {
    test('re-enqueueing a tracked job is ignored', () {
      final q = DownloadQueue<String>(maxConcurrent: 2);
      q.enqueue('a');
      expect(q.enqueue('a'), isFalse);
      expect(q.runningCount, 1);
    });
  });

  group('pause and resume', () {
    test('pause frees a slot and promotes the next queued job', () {
      final q = DownloadQueue<String>(maxConcurrent: 1);
      q.enqueue('a');
      q.enqueue('b');
      q.pause('a');
      expect(q.isPaused('a'), isTrue);
      expect(q.running, ['b']);
    });

    test('resume re-queues a paused job and can take a free slot', () {
      final q = DownloadQueue<String>(maxConcurrent: 2);
      q.enqueue('a');
      q.pause('a');
      expect(q.running, isEmpty);
      expect(q.resume('a'), isTrue);
      expect(q.running, ['a']);
    });

    test('resume of a non-paused job returns false', () {
      final q = DownloadQueue<String>();
      expect(q.resume('ghost'), isFalse);
    });

    test('a paused-then-queued job resumes at the tail', () {
      final q = DownloadQueue<String>(maxConcurrent: 1);
      q.enqueue('a');
      q.enqueue('b');
      q.enqueue('c'); // queued: b, c  (a running)
      q.pause('b'); // b paused; a still running
      q.resume('b');
      expect(q.queued, ['c', 'b']);
    });
  });

  group('cancel', () {
    test('cancel removes a running job and promotes the next', () {
      final q = DownloadQueue<String>(maxConcurrent: 1);
      q.enqueue('a');
      q.enqueue('b');
      q.cancel('a');
      expect(q.isActive('a'), isFalse);
      expect(q.running, ['b']);
    });

    test('cancel removes a queued job without promoting', () {
      final q = DownloadQueue<String>(maxConcurrent: 1);
      q.enqueue('a');
      q.enqueue('b');
      q.cancel('b');
      expect(q.queued, isEmpty);
      expect(q.running, ['a']);
    });
  });
}
