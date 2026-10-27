import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/features/player/player_device_controls.dart';
import 'package:mytube/features/player/player_device_controls_impl.dart';

/// The player's brightness / volume / wakelock seam (VP2.3).
///
/// Override with a fake to drive the gesture and lifecycle tests without a
/// device; the default talks to the three platform plugins and fails soft
/// everywhere they are absent.
final playerDeviceControlsProvider = Provider<PlayerDeviceControls>(
  (ref) => PlatformPlayerDeviceControls(),
);
