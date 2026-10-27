import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/core/ui/motion.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/captions_notifier.dart';
import 'package:mytube/features/player/playback_controls.dart' show formatSpeed;
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_settings_pages.dart';
import 'package:mytube/features/player/player_settings_rows.dart';
import 'package:mytube/features/player/sleep_timer_notifier.dart';
import 'package:mytube/features/player/player_stats.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/features/player/video_loop_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// The pages the player settings sheet can show (VP4.1, design §7).
///
/// One enum rather than a stack of routes: the sheet is a single modal with
/// sub-pages that slide in and a back arrow that returns to the list, so there
/// is nothing to pop and nothing can leak a route the player page does not own.
enum PlayerSettingsPage {
  settings('Settings'),
  speed('Playback speed'),
  captions('Captions'),
  aspect('Aspect ratio'),
  sleep('Sleep timer'),
  theme('Theme'),
  stats('Stats for nerds');

  const PlayerSettingsPage(this.title);

  /// Heading shown on the page.
  final String title;
}

/// Opens the settings sheet and holds the overlay chrome up while it is open.
///
/// Design §5 says the controls never auto-hide while a settings sheet is open,
/// and [PlayerChromeController] already has that hold; taking it here means the
/// release cannot be missed on any exit path (tap-through scrim, drag-to-dismiss
/// or an explicit close), so the countdown resumes whatever happened.
Future<void> openPlayerSettingsSheet(
  BuildContext context, {
  required VideoItemSummary item,
  PlayerChromeController? chrome,
  PlayerSettingsPage? initialPage,
}) async {
  chrome?.setSettingsSheetOpen(true);
  try {
    await showModalBottomSheet<void>(
      context: context,
      // The list plus a six-option page does not fit in the default half-height
      // sheet, and the speed page carries a slider a thumb must not fight.
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PlayerSettingsSheet(item: item, initialPage: initialPage),
    );
  } finally {
    chrome?.setSettingsSheetOpen(false);
  }
}

/// The player's settings sheet: a list of rows that each open a sub-page
/// (VP4.1).
///
/// The sheet reads and writes the same providers as the page behind it — the
/// playback controller, the display-mode and loop notifiers, the app theme and
/// the sleep timer — so a choice lands immediately and the overlay's own chips
/// can never show something else. It holds no state of its own beyond which page
/// is on screen.
class PlayerSettingsSheet extends ConsumerStatefulWidget {
  const PlayerSettingsSheet({super.key, required this.item, this.initialPage});

  /// The video being played; the info page describes it (VP4.6).
  final VideoItemSummary item;

  /// The page to open on, so the top-bar CC button can jump straight to
  /// Captions; null opens the root list (VP4.1).
  final PlayerSettingsPage? initialPage;

  @override
  ConsumerState<PlayerSettingsSheet> createState() =>
      _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends ConsumerState<PlayerSettingsSheet> {
  late PlayerSettingsPage _page =
      widget.initialPage ?? PlayerSettingsPage.settings;

  void _open(PlayerSettingsPage page) => setState(() => _page = page);

  void _back() => setState(() => _page = PlayerSettingsPage.settings);

  @override
  Widget build(BuildContext context) {
    final body = switch (_page) {
      PlayerSettingsPage.settings => _SettingsListPage(
        onOpen: _open,
        item: widget.item,
      ),
      PlayerSettingsPage.speed => PlayerSpeedPage(onBack: _back),
      PlayerSettingsPage.captions => PlayerCaptionsPage(onBack: _back),
      PlayerSettingsPage.aspect => PlayerAspectPage(onBack: _back),
      PlayerSettingsPage.sleep => PlayerSleepTimerPage(onBack: _back),
      PlayerSettingsPage.theme => PlayerThemePage(onBack: _back),
      PlayerSettingsPage.stats => PlayerStatsPage(
        item: widget.item,
        onBack: _back,
      ),
    };

    final reduce = AppMotion.reduceAnimations(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      // The outgoing page disappears instead of sliding back out: one duration
      // per navigation keeps the transition honest and keeps a widget test from
      // waiting on an animation it cannot observe (the house rule for fixed
      // durations over `pumpAndSettle`).
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : AppMotion.emphasized,
        reverseDuration: Duration.zero,
        transitionBuilder: (child, animation) {
          if (reduce) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.standard,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: SingleChildScrollView(
          key: ValueKey('player_settings_scroll_${_page.name}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: body,
        ),
      ),
    );
  }
}

/// The short value shown on the Captions row: what the user would get if they
/// opened it (design §7).
String _captionsValue(CaptionsState state) {
  if (!state.hasFile) return 'Off';
  return state.enabled ? state.label ?? 'On' : 'Off';
}

/// The sheet's first page: one row per setting, each showing its current value
/// (design §7).
class _SettingsListPage extends ConsumerWidget {
  const _SettingsListPage({required this.onOpen, required this.item});

  final void Function(PlayerSettingsPage page) onOpen;
  final VideoItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            PlayerSettingsPage.settings.title,
            key: const ValueKey('player_settings_root_title'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        // The speed row mirrors the engine, not a copy of it: the value shown is
        // what `PlaybackState.speed` reports back, so a speed the engine could
        // not apply is never advertised as applied.
        ValueListenableBuilder<PlaybackState>(
          valueListenable: controller.state,
          builder: (context, state, _) => SettingsNavRow(
            id: 'speed',
            icon: Icons.speed,
            label: 'Playback speed',
            value: formatSpeed(clampPlaybackSpeed(state.speed)),
            onTap: () => onOpen(PlayerSettingsPage.speed),
          ),
        ),
        SettingsNavRow(
          id: 'captions',
          icon: Icons.closed_caption,
          label: 'Captions',
          value: _captionsValue(ref.watch(captionsProvider)),
          onTap: () => onOpen(PlayerSettingsPage.captions),
        ),
        SettingsNavRow(
          id: 'aspect',
          icon: Icons.aspect_ratio,
          label: 'Aspect ratio',
          value: ref.watch(videoDisplayModeProvider).label,
          onTap: () => onOpen(PlayerSettingsPage.aspect),
        ),
        SettingsSwitchRow(
          id: 'loop',
          icon: Icons.repeat,
          label: 'Loop video',
          value: ref.watch(videoLoopNotifierProvider),
          onChanged: (value) => applyPlayerLoop(ref, looping: value),
        ),
        SettingsNavRow(
          id: 'sleep',
          icon: Icons.bedtime_outlined,
          label: 'Sleep timer',
          value: ref.watch(sleepTimerProvider).label,
          onTap: () => onOpen(PlayerSettingsPage.sleep),
        ),
        SettingsNavRow(
          id: 'theme',
          icon: Icons.brightness_6_outlined,
          label: 'Theme',
          value: themeModeLabel(ref.watch(themeModeProvider)),
          onTap: () => onOpen(PlayerSettingsPage.theme),
        ),
        SettingsNavRow(
          id: 'stats',
          icon: Icons.info_outline,
          label: 'Video info',
          onTap: () => onOpen(PlayerSettingsPage.stats),
        ),
      ],
    );
  }
}
