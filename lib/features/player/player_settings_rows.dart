/// The row shapes the player settings sheet is built from (VP4.1).
///
/// Design §7 asks for "list rows with an icon, a label, and the current value on
/// the right" and "the selected value shows a check mark". `ListTile` is this
/// app's settings row (`settings_screen.dart`, the item-action sheet), so these
/// are thin wrappers that keep the geometry, the 48 dp target, the semantics and
/// the test keys in one place instead of re-rolling a `Row` per page.
///
/// They are presentation-only: no provider, no callback beyond what the host
/// passes, so every page in the sheet composes them and each stays testable on
/// its own.
library;

import 'package:flutter/material.dart';

import 'package:mytube/app/theme/app_tokens.dart';

/// Key for the row that opens [id]'s sub-page.
String settingsRowKey(String id) => 'player_settings_row_$id';

/// Key for the choice [id] inside a sub-page.
String settingsOptionKey(String id) => 'player_settings_option_$id';

/// A row that opens a sub-page: icon, label, the current value, chevron.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.id,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.showChevron = true,
  });

  /// Identifies the row in the tree; also the basis of its key.
  final String id;

  final IconData icon;
  final String label;

  /// The current choice, right-aligned before the chevron. Null shows nothing,
  /// which is how a page that has no meaningful value yet renders.
  final String? value;

  final VoidCallback? onTap;

  /// Off for a row that opens an information page rather than a choice list.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return ListTile(
      key: ValueKey(settingsRowKey(id)),
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value,
              key: ValueKey('player_settings_value_$id'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (showChevron) const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A choice in a sub-page. The selected one carries the check mark (design §7).
class SettingsOptionRow extends StatelessWidget {
  const SettingsOptionRow({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    this.caption,
    this.onTap,
  });

  final String id;
  final String label;

  /// Whether this row is the current value — drawn as a trailing check.
  final bool selected;

  /// Optional second line (e.g. what a mode actually does to the picture).
  final String? caption;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(settingsOptionKey(id)),
      title: Text(label),
      subtitle: caption == null ? null : Text(caption!),
      // The check is the only selection signal, so say it out loud for a screen
      // reader rather than leaving "selected" to a green glyph.
      selected: selected,
      selectedTileColor: Colors.transparent,
      trailing: selected
          ? Icon(
              Icons.check,
              key: ValueKey('player_settings_check_$id'),
              color: Theme.of(context).colorScheme.primary,
            )
          : const SizedBox(width: 24),
      onTap: onTap,
    );
  }
}

/// A boolean setting that answers immediately, design §7's "Loop video".
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.onChanged,
  });

  final String id;
  final IconData icon;
  final String label;
  final bool value;
  final String? caption;

  /// Null disables the switch — a setting the current source cannot honour.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: ValueKey(settingsRowKey(id)),
      secondary: Icon(icon),
      title: Text(label),
      subtitle: caption == null ? null : Text(caption!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A read-only label/value pair for the "Stats for nerds" page (VP4.6).
class SettingsStatRow extends StatelessWidget {
  const SettingsStatRow({
    super.key,
    required this.id,
    required this.label,
    this.value,
  });

  final String id;
  final String label;

  /// Null means the app does not know this fact, which is shown as "Unknown"
  /// rather than a blank or a dash so the gap reads as an answer.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            value ?? 'Unknown',
            key: ValueKey('player_settings_stat_$id'),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// The back arrow and title heading every sub-page (design §7: "Each sub-page
/// slides in with a back arrow").
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        right: AppSpacing.lg,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('player_settings_back'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              title,
              key: const ValueKey('player_settings_page_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
