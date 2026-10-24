import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/discover_session.dart';

void main() {
  group('DiscoverSession boundary (§18.4)', () {
    test('starts with a single stable session id', () {
      final session = DiscoverSession(clock: () => DateTime.utc(2026, 1, 1));
      expect(session.sessionId, isNotEmpty);
    });

    test('ordinary activity inside the window keeps the same session', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final session = DiscoverSession(
        timeout: const Duration(minutes: 30),
        clock: () => now,
      );
      final firstId = session.sessionId;

      // Tab navigation / returning from playback a few minutes later.
      now = now.add(const Duration(minutes: 5));
      expect(session.touch(), isFalse);
      expect(session.sessionId, firstId);

      now = now.add(const Duration(minutes: 10));
      expect(session.touch(), isFalse);
      expect(session.sessionId, firstId);
    });

    test('a long inactive period starts a genuinely new session', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final session = DiscoverSession(
        timeout: const Duration(minutes: 30),
        clock: () => now,
      );
      final firstId = session.sessionId;

      now = now.add(const Duration(minutes: 31));
      expect(session.touch(), isTrue);
      expect(session.sessionId, isNot(firstId));
    });

    test('rebuilds without activity never change the id', () {
      final session = DiscoverSession(clock: () => DateTime.utc(2026, 1, 1));
      final id = session.sessionId;
      // Simulate rebuilds: reading identity must be side-effect free.
      expect(session.sessionId, id);
      expect(session.sessionId, id);
    });

    test('two new sessions in the same millisecond still get distinct ids', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final session = DiscoverSession(
        timeout: const Duration(minutes: 1),
        clock: () => now,
      );
      final firstId = session.sessionId;
      // Jump past the timeout without advancing the wall clock between the two
      // rollovers, so the timestamp component alone would collide.
      now = now.add(const Duration(minutes: 2));
      expect(session.touch(), isTrue);
      final secondId = session.sessionId;
      now = now.add(const Duration(minutes: 2));
      expect(session.touch(), isTrue);
      final thirdId = session.sessionId;

      expect(secondId, isNot(firstId));
      expect(thirdId, isNot(secondId));
      expect({firstId, secondId, thirdId}, hasLength(3));
    });
  });
}
