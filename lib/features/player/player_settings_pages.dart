import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/features/player/captions_notifier.dart';
import 'package:mytube/features/player/playback_controls.dart'
    show PlaybackControls, formatSpeed;
import 'package:mytube/features/player/player_settings_rows.dart';
import 'package:mytube/features/player/sleep_timer_notifier.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/features/player/video_loop_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// The playback-speed range the player offers (design §7, VP4.2).
///
/// 0.25× and 2× are the design's outer presets, so the custom slider cannot ask
/// for something the preset list does not cover. Anything outside is clamped
/// here rather than at the call sites, so the sheet, a restored engine value and
/// a drag all get the same answer.
const double minPlaybackSpeed = 0.25;
const double maxPlaybackSpeed = 2.0;

/// [speed] forced into [[minPlaybackSpeed], [maxPlaybackSpeed]].
///
/// A non-finite value (an engine that has not settled, a division by zero in a
/// future gesture) answers 1× — normal playback — instead of poisoning the
/// slider, whose `value` must be finite.
double clampPlaybackSpeed(double speed) {
  if (!speed.isFinite) return 1.0;
  return speed.clamp(minPlaybackSpeed, maxPlaybackSpeed).toDouble();
}

/// Stable option id for a speed, e.g. `speed_0_25` (VP4.2).
String speedOptionId(double speed) =>
    'speed_${speed.toString().replaceAll('.', '_')}';

/// Playback speed: the design's presets plus a custom slider (VP4.2, §7).
///
/// The engine is the only store of the current speed — [PlaybackState.speed]
/// comes straight back from it, so the check mark cannot disagree with what the
/// video is actually doing, and a preset chosen here is what the overlay's own
/// speed chip reads.
class PlayerSpeedPage extends ConsumerWidget {
  const PlayerSpeedPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final speed = clampPlaybackSpeed(state.speed);
        return Column(
          key: const ValueKey('player_settings_page_speed'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsPageHeader(title: 'Playback speed', onBack: onBack),
            for (final preset in PlaybackControls.speedPresets)
              SettingsOptionRow(
                id: speedOptionId(preset),
                label: formatSpeed(preset),
                selected: preset == speed,
                onTap: () => controller.setSpeed(preset),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Custom')),
                      Text(
                        formatSpeed(speed),
                        key: const ValueKey('player_settings_speed_value'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  Slider(
                    key: const ValueKey('player_settings_speed_slider'),
                    value: speed,
                    min: minPlaybackSpeed,
                    max: maxPlaybackSpeed,
                    // 14 steps of 0.125×: fine enough to feel custom, coarse
                    // enough that a drag lands on a readable number.
                    divisions: 14,
                    label: formatSpeed(speed),
                    onChanged: (value) =>
                        controller.setSpeed(clampPlaybackSpeed(value)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What each aspect option does, in one line (VP4.4).
///
/// Kept next to the page so a new mode cannot be added without explaining
/// itself: [VideoSurface] applies [VideoDisplayMode], and this is the only
/// place the six entries are described to the user.
String aspectOptionCaption(VideoDisplayMode mode) => switch (mode) {
  VideoDisplayMode.fit => 'Whole picture, black bars kept',
  VideoDisplayMode.fill => 'Fill the frame, edges cropped',
  VideoDisplayMode.stretch => 'Distort the picture to the frame',
  VideoDisplayMode.widescreen => 'Picture inside a 16:9 window',
  VideoDisplayMode.standard => 'Picture inside a 4:3 window',
  VideoDisplayMode.zoom => 'Span the width, crop top and bottom',
};

/// Aspect ratio: the six options of design §7 on the one existing notifier, plus
/// the ratio lock (VP4.4).
///
/// The page writes [videoDisplayModeNotifierProvider] — the same provider the
/// overlay's display-mode pill and `VideoSurface` read — so the sheet and the
/// pill can never disagree, and picking an option here changes the picture
/// immediately.
class PlayerAspectPage extends ConsumerWidget {
  const PlayerAspectPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(videoDisplayModeProvider);
    final locked = ref.watch(aspectRatioLockedProvider);
    return Column(
      key: const ValueKey('player_settings_page_aspect'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(title: 'Aspect ratio', onBack: onBack),
        for (final option in VideoDisplayMode.values)
          SettingsOptionRow(
            id: 'aspect_${option.name}',
            label: option.label,
            caption: aspectOptionCaption(option),
            selected: option == mode,
            onTap: () => ref
                .read(videoDisplayModeNotifierProvider.notifier)
                .setMode(option),
          ),
        SettingsSwitchRow(
          id: 'aspect_lock',
          icon: Icons.aspect_ratio,
          label: 'Keep this ratio',
          caption: 'Applies to the next video as well as this one',
          value: locked,
          onChanged: (value) =>
              ref.read(aspectRatioLockNotifierProvider.notifier).set(value),
        ),
      ],
    );
  }
}

/// Sleep timer: off / 15 / 30 / 45 / 60 min / end of video (VP4.5, §7).
///
/// Choosing a length arms the countdown in [SleepTimerNotifier]; choosing
/// "end of this video" also stops looping in the same tap, because a looping
/// video never ends and the promise would then be un-keepable.
class PlayerSleepTimerPage extends ConsumerWidget {
  const PlayerSleepTimerPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sleepTimerProvider);
    return Column(
      key: const ValueKey('player_settings_page_sleep'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(title: 'Sleep timer', onBack: onBack),
        for (final option in SleepTimerLength.values)
          SettingsOptionRow(
            id: 'sleep_${option.name}',
            label: option.label,
            caption: option.stopsAtVideoEnd
                ? 'Pauses when this video finishes'
                : null,
            selected: option == current,
            onTap: () => _choose(ref, option),
          ),
      ],
    );
  }

  void _choose(WidgetRef ref, SleepTimerLength option) {
    ref.read(sleepTimerProvider.notifier).set(option);
    if (option.stopsAtVideoEnd) {
      applyPlayerLoop(ref, looping: false);
    }
  }
}

/// The label for a [ThemeMode] in the sheet (VP4.5).
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System default',
  ThemeMode.dark => 'Dark',
  ThemeMode.light => 'Light',
};

/// Theme: System / Dark / Light, reusing the app's own [ThemeModeNotifier] so
/// the sheet and the Settings screen write the same persisted preference
/// (VP4.5, SET-001).
class PlayerThemePage extends ConsumerWidget {
  const PlayerThemePage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Column(
      key: const ValueKey('player_settings_page_theme'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(title: 'Theme', onBack: onBack),
        for (final option in ThemeMode.values)
          SettingsOptionRow(
            id: 'theme_${option.name}',
            label: themeModeLabel(option),
            selected: option == mode,
            onTap: () =>
                ref.read(themeModeNotifierProvider.notifier).setMode(option),
          ),
      ],
    );
  }
}

/// Captions: load a sidecar `.srt`/`.vtt`, toggle it, and pick size and
/// background (design §7, VP4.3).
///
/// Embedded subtitle and audio-track selection are deliberately absent: the
/// `video_player` engine exposes no track picker, so showing one would be a
/// dead affordance (AGENTS). Only the sidecar path the app actually implements
/// is offered. The visible text is painted by the player's own caption overlay,
/// which is what makes the size and background choices meaningful.
class PlayerCaptionsPage extends ConsumerWidget {
  const PlayerCaptionsPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionsProvider);
    final notifier = ref.read(captionsProvider.notifier);
    return Column(
      key: const ValueKey('player_settings_page_captions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(title: 'Captions', onBack: onBack),
        // Off / on once a file exists; the switch disables itself until one is
        // loaded so there is never a live toggle with nothing to show.
        SettingsSwitchRow(
          id: 'captions_enabled',
          icon: Icons.closed_caption,
          label: 'Enable captions',
          value: captions.enabled,
          onChanged: captions.hasFile ? notifier.setEnabled : null,
        ),
        ListTile(
          key: const ValueKey('player_settings_load_sidecar'),
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Load .srt / .vtt file'),
          subtitle: Text(
            captions.label ?? 'No file loaded',
            key: const ValueKey('player_settings_caption_file'),
          ),
          onTap: () async {
            final message = await notifier.load();
            if (message == null || !context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          },
        ),
        // Size and background only mean something with a file on screen, so
        // they render only once one is loaded.
        if (captions.hasFile) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              'Text size',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final option in CaptionTextSize.values)
            SettingsOptionRow(
              id: 'caption_size_${option.name}',
              label: option.label,
              selected: option == captions.size,
              onTap: () => notifier.setSize(option),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              'Background',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final option in CaptionBackground.values)
            SettingsOptionRow(
              id: 'caption_bg_${option.name}',
              label: option.label,
              selected: option == captions.background,
              onTap: () => notifier.setBackground(option),
            ),
        ],
      ],
    );
  }
}
