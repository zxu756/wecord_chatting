import 'package:flutter/material.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/ui/motion.dart';
import 'package:wecord/shared/ui/wecord_pressable.dart';
import 'package:wecord/shared/ui/wecord_switch.dart';

/// The tint of a [SettingsIconTile].
enum SettingsTone { neutral, accent, success, warning, danger }

/// The 32px rounded icon tile at the start of a settings row.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({
    required this.icon,
    this.tone = SettingsTone.neutral,
    this.size = 32,
    super.key,
  });

  final IconData icon;
  final SettingsTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (fill, foreground) = switch (tone) {
      SettingsTone.neutral => (c.raised, c.ink),
      SettingsTone.accent => (c.accentSoft, c.accentText),
      SettingsTone.success => (c.successSoft, c.successText),
      SettingsTone.warning => (c.warningSoft, c.warningText),
      SettingsTone.danger => (c.dangerSoft, c.dangerText),
    };
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: fill,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size * 0.34),
        ),
      ),
      child: Icon(icon, size: size * 0.56, color: foreground),
    );
  }
}

/// A small bold label above a group ("Appearance", "Privacy & Safety").
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A rounded card of settings rows with hairline separators between them
/// (inset past the icon tiles), optionally under a [header] and above a
/// [footer] note. White on the paper background.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.children,
    this.header,
    this.footer,
    this.color,
    this.separatorIndent = 58,
    this.padding,
    super.key,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// The card's fill; the panel color by default.
  final Color? color;

  /// Where separators start; 58 lines them up with row titles after an
  /// icon tile, 14 for rows without one.
  final double separatorIndent;

  /// Padding inside the card, for groups that hold something other than
  /// rows (the theme picker).
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: separatorIndent),
            child: Container(height: 1, color: c.lineSoft),
          ),
        );
      }
      rows.add(children[i]);
    }
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
    if (header == null && footer == null) {
      return card;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) SettingsSectionHeader(header!),
        card,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(
              footer!,
              style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// One settings row: icon tile, title (15/600) and optional subtitle, then
/// a [value] and chevron (when it opens something), a [trailing] widget,
/// or a switch (see [SettingsRow.toggle]). At least 52 tall.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.icon,
    this.tone = SettingsTone.neutral,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.destructive = false,
    super.key,
  }) : _switchValue = null,
       _onSwitch = null;

  /// A row with a switch; tapping anywhere on it flips the switch.
  const SettingsRow.toggle({
    required this.title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    this.icon,
    this.tone = SettingsTone.neutral,
    this.subtitle,
    super.key,
  }) : _switchValue = value,
       _onSwitch = onChanged,
       value = null,
       trailing = null,
       onTap = null,
       showChevron = false,
       destructive = false;

  final String title;
  final IconData? icon;
  final SettingsTone tone;
  final String? subtitle;

  /// The current choice, muted, before the chevron ("English", "2").
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to showing a chevron when the row has [onTap] and no
  /// [trailing].
  final bool? showChevron;

  /// Red title, for sign out and delete.
  final bool destructive;

  final bool? _switchValue;
  final ValueChanged<bool>? _onSwitch;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final switchValue = _switchValue;
    final onSwitch = _onSwitch;
    final isToggle = switchValue != null;
    final tap = isToggle
        ? (onSwitch == null ? null : () => onSwitch(!switchValue))
        : onTap;
    final chevron = showChevron ?? (onTap != null && trailing == null);

    return WeCordPressable(
      onPressed: tap == null
          ? null
          : () {
              if (isToggle) {
                WeCordHaptics.selection();
              }
              tap();
            },
      pressedScale: 1,
      toggled: isToggle ? switchValue : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: highlighted
              ? c.ink.withValues(alpha: 0.04)
              : c.ink.withValues(alpha: 0),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                SettingsIconTile(
                  icon: icon!,
                  tone: destructive ? SettingsTone.danger : tone,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: destructive ? c.dangerText : c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.muted,
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (isToggle) ...[
                const SizedBox(width: 8),
                // The row handles taps and semantics; the switch only shows.
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: WeCordSwitch(
                      value: switchValue,
                      onChanged: onSwitch == null ? null : (_) {},
                    ),
                  ),
                ),
              ],
              if (chevron) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
              ],
            ],
          ),
        );
      },
    );
  }
}
