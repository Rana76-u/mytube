import 'package:mytube/domain/models/app_error.dart';

/// A discriminated union of success and failure (ARCHITECTURE §3 — Data layer:
/// "Use typed results/errors").
///
/// Repository methods and source adapters return [Result<T>] instead of
/// throwing. Callers pattern-match on [Ok] / [Err] without needing try-catch.
///
/// ```dart
/// final result = await repository.fetchVideos();
/// switch (result) {
///   case Ok(:final value): renderList(value);
///   case Err(:final error): showError(error.userMessage);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Wraps a successful value.
  factory Result.ok(T value) => Ok(value);

  /// Wraps a domain error.
  factory Result.err(AppError error) => Err(error);

  /// Returns [value] on success, or throws [StateError] on failure.
  /// Prefer pattern-matching over this in production code.
  T get valueOrThrow {
    return switch (this) {
      Ok(:final value) => value,
      Err(:final error) => throw StateError(error.diagnosticMessage),
    };
  }

  /// True when this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// True when this is an [Err].
  bool get isErr => this is Err<T>;

  /// Maps the success value without touching errors.
  Result<U> map<U>(U Function(T value) transform) {
    return switch (this) {
      Ok(:final value) => Ok(transform(value)),
      Err(:final error) => Err(error),
    };
  }
}

/// Success branch of [Result].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

/// Failure branch of [Result].
final class Err<T> extends Result<T> {
  const Err(this.error);

  final AppError error;
}
