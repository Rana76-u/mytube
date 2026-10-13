import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';

void main() {
  group('Result (P1-06)', () {
    test('Ok carries value and isOk is true', () {
      const result = Ok<int>(42);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.value, 42);
      expect(result.valueOrThrow, 42);
    });

    test('Err carries error and isErr is true', () {
      const error = NetworkUnavailableError(
        diagnosticMessage: 'no connectivity',
      );
      const result = Err<int>(error);

      expect(result.isErr, isTrue);
      expect(result.isOk, isFalse);
      expect(result.error, same(error));
    });

    test('valueOrThrow on Err throws StateError', () {
      const result = Err<int>(NotFoundError(diagnosticMessage: 'item gone'));

      expect(() => result.valueOrThrow, throwsStateError);
    });

    test('map transforms Ok value', () {
      const ok = Ok<int>(10);
      final mapped = ok.map((v) => v * 2);

      expect(mapped, isA<Ok<int>>());
      expect((mapped as Ok<int>).value, 20);
    });

    test('map preserves Err', () {
      const error = UnexpectedError(diagnosticMessage: 'oops');
      const err = Err<int>(error);
      final mapped = err.map((v) => v * 2);

      expect(mapped, isA<Err<int>>());
      expect((mapped as Err<int>).error, same(error));
    });

    test('factory constructors produce correct subtypes', () {
      final ok = Result.ok(99);
      final err = Result<int>.err(
        const UnexpectedError(diagnosticMessage: 'fail'),
      );

      expect(ok, isA<Ok<int>>());
      expect(err, isA<Err<int>>());
    });

    test('pattern match on Ok', () {
      final result = Result.ok('video-id');
      String? extracted;
      switch (result) {
        case Ok(:final value):
          extracted = value;
        case Err():
          fail('should not be Err');
      }
      expect(extracted, 'video-id');
    });

    test('pattern match on Err', () {
      final result = Result<String>.err(
        const PermissionDeniedError(diagnosticMessage: 'no perm'),
      );
      AppError? captured;
      switch (result) {
        case Ok():
          fail('should not be Ok');
        case Err(:final error):
          captured = error;
      }
      expect(captured, isA<PermissionDeniedError>());
    });
  });

  group('AppError user messages (P1-06)', () {
    test('PermissionDeniedError has non-empty user message', () {
      const e = PermissionDeniedError(diagnosticMessage: 'denied');
      expect(e.userMessage, isNotEmpty);
    });

    test('NetworkUnavailableError has non-empty user message', () {
      const e = NetworkUnavailableError(diagnosticMessage: 'offline');
      expect(e.userMessage, isNotEmpty);
    });

    test('UnexpectedError accepts optional cause', () {
      final cause = Exception('root');
      final e = UnexpectedError(diagnosticMessage: 'oops', cause: cause);
      expect(e.cause, same(cause));
    });

    test('user messages do not contain diagnostic detail', () {
      const e = UnexpectedError(diagnosticMessage: 'token=abc123');
      expect(e.userMessage, isNot(contains('token')));
      expect(e.userMessage, isNot(contains('abc123')));
    });
  });

  group('AvailabilityState helpers (P1-06)', () {
    test('offline and unknown are transient', () {
      expect(AvailabilityState.offline.isTransient, isTrue);
      expect(AvailabilityState.unknown.isTransient, isTrue);
    });

    test('available, missing, unsupported are not transient', () {
      expect(AvailabilityState.available.isTransient, isFalse);
      expect(AvailabilityState.missing.isTransient, isFalse);
      expect(AvailabilityState.unsupported.isTransient, isFalse);
    });

    test(
      'reconnectRequired, permissionRevoked, expiredLink require user action',
      () {
        expect(AvailabilityState.reconnectRequired.requiresUserAction, isTrue);
        expect(AvailabilityState.permissionRevoked.requiresUserAction, isTrue);
        expect(AvailabilityState.expiredLink.requiresUserAction, isTrue);
      },
    );

    test('available and offline do not require user action', () {
      expect(AvailabilityState.available.requiresUserAction, isFalse);
      expect(AvailabilityState.offline.requiresUserAction, isFalse);
    });
  });
}
