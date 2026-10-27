import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/skeleton.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/core/util/relative_time.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart'
    show VideoItemCard;
import 'package:mytube/features/player/player_item_details.dart';

/// Title, meta line and the disclosure that opens the description card
/// (design §4, VP3.3).
///
/// The two-line title is the disclosure target, as in the design ("tap to
/// expand the description section"), and the trailing chevron is the same
/// toggle for anyone aiming at a control rather than text. The card itself is
/// built from [playerItemDetailsProvider]: file name, provider, location label,
/// size, resolution, date added, tags and availability — codec, bitrate and fps
/// are absent because neither the engine nor the schema reports them.
class PlayerMetadataPanel extends ConsumerStatefulWidget {
  const PlayerMetadataPanel({super.key, required this.item});

  final VideoItemSummary item;

  @override
  ConsumerState<PlayerMetadataPanel> createState() =>
      _PlayerMetadataPanelState();
}

class _PlayerMetadataPanelState extends ConsumerState<PlayerMetadataPanel> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final details = ref.watch(playerItemDetailsProvider(item.id));
    final meta = playerMetaLine(item, sizeBytes: details.value?.sizeBytes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('player_title_toggle'),
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      item.title,
                      key: const ValueKey('player_title'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('player_more_button'),
                tooltip: _expanded ? 'Show less' : 'Show more',
                onPressed: _toggle,
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Text(
              meta,
              key: const ValueKey('player_metadata_line'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_expanded) _DescriptionCard(item: item, details: details.value),
        ],
      ),
    );
  }
}

/// The expandable description card itself.
class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.item, required this.details});

  final VideoItemSummary item;

  /// Null while the source/tag read is still in flight.
  final PlayerItemDetails? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = details;
    final primary = data?.primary;
    final tags = data?.tags ?? const <LibraryTag>[];

    return Container(
      key: const ValueKey('player_description_card'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm, right: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data == null)
            // The card is already open, so the wait is shown as skeleton rows
            // rather than an empty box.
            const _DetailsSkeleton()
          else if (primary == null)
            Text(
              'No source recorded for this video.',
              key: const ValueKey('player_detail_missing'),
              style: theme.textTheme.bodySmall,
            )
          else
            ..._sourceRows(primary, colorScheme),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              key: const ValueKey('player_detail_tags'),
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in tags)
                  Chip(
                    label: Text(tag.name),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The known facts about [primary], in reading order.
  List<Widget> _sourceRows(SourceLocation primary, ColorScheme colorScheme) {
    final described = describeSourceLocation(primary);
    final size = primary.sizeBytes;
    final resolution = resolutionLabel(item.widthPx, item.heightPx);

    return [
      _DetailRow(
        label: 'File',
        value: described.fileName,
        valueKey: const ValueKey('player_detail_file_name'),
      ),
      _DetailRow(
        label: 'Source',
        value: VideoItemCard.providerLabel(primary.providerType),
        valueKey: const ValueKey('player_detail_provider'),
      ),
      _DetailRow(
        label: 'Location',
        value: described.locationLabel,
        valueKey: const ValueKey('player_detail_location'),
      ),
      if (size != null && size > 0)
        _DetailRow(
          label: 'Size',
          value: formatBytes(size),
          valueKey: const ValueKey('player_detail_size'),
        ),
      if (resolution.isNotEmpty)
        _DetailRow(
          label: 'Resolution',
          value: resolution,
          valueKey: const ValueKey('player_detail_resolution'),
        ),
      if (item.durationMs case final durationMs? when durationMs > 0)
        _DetailRow(
          label: 'Duration',
          value: formatDuration(Duration(milliseconds: durationMs)),
          valueKey: const ValueKey('player_detail_duration'),
        ),
      _DetailRow(
        label: 'Added',
        value: formatRelativeDate(item.createdAt),
        valueKey: const ValueKey('player_detail_date'),
      ),
      _DetailRow(
        label: 'Status',
        value: availabilityLabel(primary.availability),
        valueKey: const ValueKey('player_detail_availability'),
        valueColor: switch (primary.availability) {
          AvailabilityState.available => null,
          AvailabilityState.unknown ||
          AvailabilityState.offline => colorScheme.onSurfaceVariant,
          _ => colorScheme.error,
        },
      ),
    ];
  }
}

/// One `label   value` line inside the card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.valueKey,
    this.valueColor,
  });

  final String label;
  final String value;
  final Key valueKey;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three grey rows while the source and tag reads are in flight.
class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        key: ValueKey('player_details_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 180, height: 10),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 240, height: 10),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 140, height: 10),
        ],
      ),
    );
  }
}
