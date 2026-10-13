import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/uncaught_app_error.dart';
import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/core/ui/loading_indicator.dart';

/// Minimal Material wrapper so widgets can call Theme.of / colorScheme.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // ── LoadingIndicator ──────────────────────────────────────────────────────

  group('LoadingIndicator (P1-05)', () {
    testWidgets('renders a progress indicator', (tester) async {
      await tester.pumpWidget(_wrap(const LoadingIndicator()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows optional message', (tester) async {
      await tester.pumpWidget(
        _wrap(const LoadingIndicator(message: 'Scanning…')),
      );

      expect(find.text('Scanning…'), findsOneWidget);
    });

    testWidgets('renders without a message', (tester) async {
      await tester.pumpWidget(_wrap(const LoadingIndicator()));

      expect(find.byType(Text), findsNothing);
    });
  });

  // ── EmptyState ────────────────────────────────────────────────────────────

  group('EmptyState (P1-05)', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(title: 'No videos yet')));

      expect(find.text('No videos yet'), findsOneWidget);
    });

    testWidgets('renders optional message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            title: 'No videos yet',
            message: 'Add a folder to get started.',
          ),
        ),
      );

      expect(find.text('Add a folder to get started.'), findsOneWidget);
    });

    testWidgets('renders action button and calls callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          EmptyState(
            title: 'Empty',
            action: EmptyStateAction(
              label: 'Add source',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Add source'), findsOneWidget);
      await tester.tap(find.text('Add source'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without action or message', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(title: 'Empty')));

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('falls back to inbox icon when no icon provided', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const EmptyState(title: 'Empty')));

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('shows custom icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(title: 'Empty', icon: Icons.video_library_outlined),
        ),
      );

      expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
    });
  });

  // ── ErrorState ────────────────────────────────────────────────────────────

  group('ErrorState (P1-05)', () {
    testWidgets('renders message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(message: 'Something went wrong.')),
      );

      expect(find.text('Something went wrong.'), findsOneWidget);
    });

    testWidgets('shows Retry button when onRetry provided', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        _wrap(ErrorState(message: 'Failed.', onRetry: () => retried = true)),
      );

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('hides Retry button when no callback', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState(message: 'Failed.')));

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('error icon is present', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState(message: 'Failed.')));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  // ── AsyncValueWidget ──────────────────────────────────────────────────────

  group('AsyncValueWidget (P1-05)', () {
    testWidgets('shows LoadingIndicator for AsyncLoading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueWidget<String>(
            value: const AsyncLoading(),
            onData: (v) => Text(v),
          ),
        ),
      );

      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('shows data widget for AsyncData', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueWidget<String>(
            value: const AsyncData('hello'),
            onData: (v) => Text(v),
          ),
        ),
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.byType(LoadingIndicator), findsNothing);
    });

    testWidgets('shows ErrorState for AsyncError with AppException', (
      tester,
    ) async {
      const error = AppException(
        userMessage: 'Video unavailable.',
        diagnosticMessage: 'https://cdn.example/v?sig=secret',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            AsyncValueWidget<String>(
              value: AsyncError(error, StackTrace.empty),
              onData: (v) => Text(v),
            ),
          ),
        ),
      );

      expect(find.text('Video unavailable.'), findsOneWidget);
      // Signed URL parameters must not be visible.
      expect(find.textContaining('sig='), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('shows fallback message for non-AppException errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            AsyncValueWidget<String>(
              value: AsyncError(StateError('boom'), StackTrace.empty),
              onData: (v) => Text(v),
            ),
          ),
        ),
      );

      expect(
        find.text(UncaughtAppErrorNotifier.fallbackUserMessage),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('shows Retry button when onRetry provided', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            AsyncValueWidget<String>(
              value: AsyncError(StateError('x'), StackTrace.empty),
              onData: (v) => Text(v),
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('uses custom loading widget when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueWidget<String>(
            value: const AsyncLoading(),
            onData: (v) => Text(v),
            onLoading: const Text('custom-loading'),
          ),
        ),
      );

      expect(find.text('custom-loading'), findsOneWidget);
      expect(find.byType(LoadingIndicator), findsNothing);
    });

    testWidgets('uses custom error widget when onError provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            AsyncValueWidget<String>(
              value: AsyncError(StateError('x'), StackTrace.empty),
              onData: (v) => Text(v),
              onError: (msg, _) => Text('custom:$msg'),
            ),
          ),
        ),
      );

      expect(find.textContaining('custom:'), findsOneWidget);
    });

    testWidgets('loading message is passed to LoadingIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueWidget<String>(
            value: const AsyncLoading(),
            onData: (v) => Text(v),
            loadingMessage: 'Please wait…',
          ),
        ),
      );

      expect(find.text('Please wait…'), findsOneWidget);
    });
  });
}
