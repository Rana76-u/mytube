import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';

void main() {
  group('DiscoverFeedFilterController (UI-2)', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    DiscoverFeedFilter state() => container.read(discoverFeedFilterProvider);
    DiscoverFeedFilterController controller() =>
        container.read(discoverFeedFilterProvider.notifier);

    test('defaults to the All state', () {
      expect(state(), isA<DiscoverFeedNoFilter>());
      expect(state().isAll, isTrue);
      expect(state().heading, isNull);
    });

    test('select stores a collection filter with its name as heading', () {
      controller().select(const DiscoverFeedCollection('c1', 'Travel'));
      expect(state(), const DiscoverFeedCollection('c1', 'Travel'));
      expect(state().isAll, isFalse);
      expect(state().heading, 'Travel');
    });

    test('select stores a tag filter with its name as heading', () {
      controller().select(const DiscoverFeedTag('t1', 'cooking'));
      expect(state().heading, 'cooking');
      expect(state(), const DiscoverFeedTag('t1', 'cooking'));
    });

    test('clear restores All', () {
      controller().select(const DiscoverFeedCollection('c1', 'Travel'));
      controller().clear();
      expect(state().isAll, isTrue);
    });

    test('toggle selects an inactive chip and de-selects the active one', () {
      const travel = DiscoverFeedCollection('c1', 'Travel');
      controller().toggle(travel);
      expect(state(), travel);
      // Re-tapping the same chip returns to All rather than staying selected.
      controller().toggle(travel);
      expect(state().isAll, isTrue);
    });

    test('toggle switches directly between two different chips', () {
      controller().toggle(const DiscoverFeedCollection('c1', 'Travel'));
      controller().toggle(const DiscoverFeedTag('t2', 'cooking'));
      expect(state(), const DiscoverFeedTag('t2', 'cooking'));
    });

    test('toggling the All chip keeps All', () {
      controller().toggle(const DiscoverFeedNoFilter());
      expect(state().isAll, isTrue);
    });
  });

  group('DiscoverFeedFilter value equality', () {
    test('identical group filters compare equal', () {
      expect(
        const DiscoverFeedCollection('c1', 'Travel'),
        const DiscoverFeedCollection('c1', 'Travel'),
      );
      expect(
        const DiscoverFeedTag('t1', 'a'),
        const DiscoverFeedTag('t1', 'a'),
      );
      expect(
        const DiscoverFeedCollection('c1', 'Travel'),
        isNot(const DiscoverFeedTag('c1', 'Travel')),
      );
      expect(
        const DiscoverFeedCollection('c1', 'Travel'),
        isNot(const DiscoverFeedCollection('c2', 'Travel')),
      );
    });

    test('all no-filter instances compare equal', () {
      expect(const DiscoverFeedNoFilter(), const DiscoverFeedNoFilter());
    });
  });
}
