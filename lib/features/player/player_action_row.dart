import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/motion.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_controller.dart'
    show providerIsDownloadable;
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/player/download_pill.dart';
import 'package:mytube/features/player/playback_controls.dart'
    show DisplayModeMenu;

/// Whether the toolbar offers a Download pill for [item] (VP3.4 gate, VP6.4
/// behaviour).
///
/// Only a remote copy can be downloaded — a MediaStore/SAF item already *is* a
/// file on this device, so a Download there would duplicate it or lie about
/// having fetched anything. A direct URL is now downloadable ("eligible if
/// fetchable", P12-01) and the cloud providers light up as their adapters land.
/// This is the cheap synchronous mount gate; [DownloadPill] + its controller
/// then refine it (a prohibited source or one with no location renders nothing).
bool downloadOfferedFor(VideoItemSummary item) =>
    providerIsDownloadable(item.primaryProvider);

/// The player's action row: Like, Save, Share, Tag, Loop, Download, Sources and
/// the display-mode pill as one horizontally scrollable strip with a fade at
/// the right edge (design §4, VP3.4).
///
/// Every entry except Loop and Download reuses [videoItemActionsFor], so the
/// page offers exactly what a card's `⋮` offers and cannot advertise an action
/// it does not perform. [actions] exists for tests and read-only hosts; the
/// page passes null and gets the shared bundle.
class PlayerActionRow extends ConsumerWidget {
  const PlayerActionRow({
    super.key,
    required this.item,
    this.actions,
    this.loop = false,
    this.onToggleLoop,
  });

  final VideoItemSummary item;

  /// Overrides the shared action bundle (tests, read-only surfaces).
  final VideoItemActions? actions;

  /// Whether the video is currently looping.
  final bool loop;

  /// Flips [loop]. Null disables the pill.
  final VoidCallback? onToggleLoop;

  /// Width of the fade that hints at more pills to the right.
  static const double fadeWidth = 32;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = actions ?? videoItemActionsFor(context, ref, item);

    return SizedBox(
      height: AppSizes.minTapTarget,
      child: Stack(
        children: [
          SingleChildScrollView(
            key: const ValueKey('player_action_toolbar'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _LikePill(
                  active: item.isFavourite,
                  onPressed: bundle.onToggleFavourite,
                ),
                _Pill(
                  pillKey: const ValueKey('player_action_save'),
                  icon: Icons.playlist_add,
                  label: 'Save',
                  onPressed: bundle.onSaveToCollection,
                ),
                _Pill(
                  pillKey: const ValueKey('player_action_share'),
                  icon: Icons.share,
                  label: 'Share',
                  onPressed: bundle.onShare,
                ),
                _Pill(
                  pillKey: const ValueKey('player_action_tags'),
                  icon: Icons.sell_outlined,
                  label: 'Tags',
                  onPressed: bundle.onManageTags,
                ),
                _Pill(
                  pillKey: const ValueKey('player_action_loop'),
                  icon: loop ? Icons.repeat_on : Icons.repeat,
                  label: 'Loop',
                  active: loop,
                  onPressed: onToggleLoop,
                ),
                // The VP3.4 slot, now a working download action (VP6.4). The
                // synchronous gate avoids mounting a controller for local items;
                // the pill still hides itself when its source turns out to be
                // non-downloadable or absent.
                if (downloadOfferedFor(item)) DownloadPill(item: item),
                _Pill(
                  pillKey: const ValueKey('player_action_sources'),
                  icon: Icons.link,
                  label: 'Sources',
                  onPressed: bundle.onManageSources,
                ),
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: DisplayModeMenu(),
                ),
              ],
            ),
          ),
          // The strip is wider than the page on a phone, so the right edge
          // fades into the background instead of cutting a pill in half.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('player_action_fade'),
                width: fadeWidth,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pill: icon left of the label, tinted when it represents a live state.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.pillKey,
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
  });

  final Key pillKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? colorScheme.primary : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ActionChip(
        key: pillKey,
        avatar: Icon(
          icon,
          size: 18,
          color: onPressed == null ? null : foreground,
        ),
        label: Text(label),
        labelStyle: TextStyle(color: onPressed == null ? null : foreground),
        onPressed: onPressed,
        backgroundColor: active
            ? colorScheme.primaryContainer
            : colorScheme.surface,
        side: BorderSide(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// The Like pill: the shared favourite action plus the design's pop and tick
/// (haptic + scale) so a toggle feels acknowledged.
class _LikePill extends StatefulWidget {
  const _LikePill({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback? onPressed;

  @override
  State<_LikePill> createState() => _LikePillState();
}

class _LikePillState extends State<_LikePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// 1 → 1.16 → 1, so the pill "pops" without changing layout.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.16,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.16,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _tap() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    unawaited(HapticFeedback.lightImpact());
    if (!AppMotion.reduceAnimations(context)) _pop.forward(from: 0);
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: _Pill(
        pillKey: const ValueKey('player_action_like'),
        icon: widget.active ? Icons.favorite : Icons.favorite_border,
        label: 'Like',
        active: widget.active,
        onPressed: widget.onPressed == null ? null : _tap,
      ),
    );
  }
}
