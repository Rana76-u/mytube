import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/pressable.dart';

/// The MyTube brand mark used by the shell header (DESIGN.md §2).
///
/// A red play-button tile with a tiny blue badge in its corner, followed by the
/// wordmark. The mark is a button: tapping it scrolls the active tab back to the
/// top, so the logo never sits in the header as a dead affordance.
class MyTubeLogo extends StatelessWidget {
  const MyTubeLogo({super.key, this.onTap, this.compact = false});

  /// Called when the mark is tapped (the shell scrolls the active tab to top).
  final VoidCallback? onTap;

  /// Renders the mark without the wordmark, for very narrow headers.
  final bool compact;

  /// Size of the red tile.
  static const double tileWidth = 30;
  static const double tileHeight = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final mark = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: tileWidth,
          height: tileHeight,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            size: 18,
            color: colorScheme.onPrimary,
          ),
        ),
        // DESIGN.md's "tiny badge": a personal-library dot, not a notification
        // count — nothing here can be unread.
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            key: const ValueKey('mytube_logo_badge'),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.scaffoldBackgroundColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );

    final content = compact
        ? mark
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: AppSpacing.sm),
              Text(
                'MyTube',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          );

    if (onTap == null) return content;
    return PressableScale(
      key: const ValueKey('shell_logo'),
      onTap: onTap,
      haptic: PressHaptic.selection,
      semanticLabel: 'MyTube, scroll to top',
      child: content,
    );
  }
}
