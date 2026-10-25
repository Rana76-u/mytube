import 'dart:ui' show Size;

/// An integer aspect ratio (width : height) for the Android PiP float window.
///
/// Android constrains the ratio to between 1:2.39 and 2.39:1; [pipAspectFor]
/// already clamps into that range, so a value here is always valid to hand to
/// `PictureInPictureParams.Builder.setAspectRatio`.
class PipAspect {
  const PipAspect(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipAspect && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PipAspect($width:$height)';
}

/// Android accepts PiP aspect ratios from 1:2.39 to 2.39:1 (inclusive).
const double _minPipRatio = 1 / 2.39;
const double _maxPipRatio = 2.39;

/// Derives a small, reduced integer aspect ratio from the loaded picture [size]
/// for the PiP window, or null when the size is unknown.
///
/// The result is clamped into Android's legal PiP range so it can always be
/// passed to `setAspectRatio`. Kept top-level and pure so it is unit-testable
/// without a channel (house style — no mocking package).
PipAspect? pipAspectFor(Size? size) {
  if (size == null || size.isEmpty) {
    return null;
  }
  final ratio = size.width / size.height;
  // Outside Android's legal band, fall back to the nearest allowed boundary so
  // the value can always reach setAspectRatio without throwing.
  if (ratio < _minPipRatio) {
    return const PipAspect(100, 239); // ≈ 1:2.39
  }
  if (ratio > _maxPipRatio) {
    return const PipAspect(239, 100); // ≈ 2.39:1
  }
  // Within range: reduce the pixel dimensions to their lowest integer terms,
  // which is what `Rational` requires and gives the true float shape (e.g.
  // 1920×1080 → 16:9, 1080×1920 → 9:16) instead of a raw pixel count.
  final width = size.width.round();
  final height = size.height.round();
  if (width <= 0 || height <= 0) {
    return null;
  }
  final divisor = _gcd(width, height);
  return PipAspect(width ~/ divisor, height ~/ divisor);
}

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x == 0 ? 1 : x;
}

/// Contract for the Android Picture-in-Picture bridge (P13-04, PLAY-010,
/// PLAT-004).
///
/// The concrete implementation is a Kotlin method-channel bridge that drives
/// `Activity.enterPictureInPictureMode` / `setPictureInPictureParams`; this
/// contract lets the app-owned `PipCoordinator` request PiP and observe mode
/// changes without importing any Android type. Widgets must never use a bridge
/// directly.
///
/// Every method is safe to call where the plugin is absent or the device does
/// not support PiP: the implementation degrades to a no-op / reports
/// `isSupported` false, so a missing bridge neither shows dead controls nor
/// crashes playback (PLAY-013, NFR-006).
abstract interface class PipBridge {
  /// Whether the host supports Android PiP (API 26+ with the
  /// `FEATURE_PICTURE_IN_PICTURE` system feature). `false` on every other host.
  Future<bool> isSupported();

  /// Emits `true` when the app has entered PiP and `false` when it left, so the
  /// UI can hide overlay chrome while floating.
  Stream<bool> get modeChanges;

  /// Requests the activity enter PiP now, hinting the float window's aspect
  /// ratio from the loaded picture when known.
  Future<void> enter({int? aspectWidth, int? aspectHeight});

  /// Enables or disables auto-enter-on-leave (Android 12 / API 31+). On lower
  /// levels this is a no-op and only [enter] shrinks the video.
  Future<void> setAutoEnter(bool enabled);

  /// Clears any persisted PiP params and releases native state. Idempotent,
  /// best-effort, never throws.
  Future<void> release();
}
