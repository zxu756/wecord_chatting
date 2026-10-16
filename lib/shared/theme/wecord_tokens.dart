import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// WeCord's design tokens (design language "C", see
/// docs/design/wecord-design-language.md): the palette, shadows and glass
/// recipe for the current brightness, carried on the theme as a
/// [ThemeExtension]. Read them with `context.tokens` (or
/// [WeCordTokens.of]); sizes that don't change with the theme live in
/// [WeCordRadii], [WeCordSpace] and [WeCordSizes].
@immutable
class WeCordTokens extends ThemeExtension<WeCordTokens> {
  const WeCordTokens({
    required this.brightness,
    required this.colors,
    required this.shadows,
    required this.glass,
  });

  static const light = WeCordTokens(
    brightness: Brightness.light,
    colors: WeCordPalette.light,
    shadows: WeCordShadows.light,
    glass: WeCordGlassStyle.light,
  );

  static const dark = WeCordTokens(
    brightness: Brightness.dark,
    colors: WeCordPalette.dark,
    shadows: WeCordShadows.dark,
    glass: WeCordGlassStyle.dark,
  );

  final Brightness brightness;
  final WeCordPalette colors;
  final WeCordShadows shadows;
  final WeCordGlassStyle glass;

  bool get isDark => brightness == Brightness.dark;

  /// The tokens on [context]'s theme, or the stock light/dark set when the
  /// theme was built without them (plain `ThemeData()` in tests).
  static WeCordTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WeCordTokens>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  WeCordTokens copyWith({
    Brightness? brightness,
    WeCordPalette? colors,
    WeCordShadows? shadows,
    WeCordGlassStyle? glass,
  }) {
    return WeCordTokens(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      shadows: shadows ?? this.shadows,
      glass: glass ?? this.glass,
    );
  }

  @override
  WeCordTokens lerp(covariant WeCordTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return WeCordTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      colors: WeCordPalette.lerp(colors, other.colors, t),
      shadows: WeCordShadows.lerp(shadows, other.shadows, t),
      glass: WeCordGlassStyle.lerp(glass, other.glass, t),
    );
  }
}

extension WeCordTokensContext on BuildContext {
  /// The current [WeCordTokens].
  WeCordTokens get tokens => WeCordTokens.of(this);
}

/// Every color the design uses, by role. Light values are warm paper and
/// ink; dark values are graphite. Prefer these over raw hex in widgets.
@immutable
class WeCordPalette {
  const WeCordPalette({
    required this.paper,
    required this.rail,
    required this.railItem,
    required this.sidebar,
    required this.panel,
    required this.raised,
    required this.raisedStrong,
    required this.well,
    required this.ink,
    required this.onInk,
    required this.muted,
    required this.subtle,
    required this.faint,
    required this.line,
    required this.lineSoft,
    required this.track,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.success,
    required this.successSoft,
    required this.successText,
    required this.warning,
    required this.warningSoft,
    required this.warningText,
    required this.danger,
    required this.onDanger,
    required this.dangerSoft,
    required this.dangerText,
    required this.scrim,
  });

  static const light = WeCordPalette(
    paper: Color(0xFFF5F4F1),
    rail: Color(0xFFECEAE5),
    railItem: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFAF9F7),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF2F1EE),
    raisedStrong: Color(0xFFECEAE5),
    well: Color(0xFFF7F6F3),
    ink: Color(0xFF17171A),
    onInk: Color(0xFFFFFFFF),
    muted: Color(0xFF6B6A72),
    subtle: Color(0xFF8A8891),
    faint: Color(0xFFB3B1B8),
    line: Color(0xFFE4E2DD),
    lineSoft: Color(0xFFEFEDE8),
    track: Color(0xFFD6D3CC),
    accent: Color(0xFF2F6BF6),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE9F0FF),
    accentText: Color(0xFF1F5FE0),
    success: Color(0xFF30A46C),
    successSoft: Color(0xFFE3F3EA),
    successText: Color(0xFF1F7A47),
    warning: Color(0xFFE7A53B),
    warningSoft: Color(0xFFFFF6E6),
    warningText: Color(0xFF8A5A00),
    danger: Color(0xFFE5484D),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFFFDECEC),
    dangerText: Color(0xFFD92D20),
    scrim: Color(0x5217171A),
  );

  static const dark = WeCordPalette(
    paper: Color(0xFF111113),
    rail: Color(0xFF111113),
    railItem: Color(0xFF1F1F23),
    sidebar: Color(0xFF18181B),
    panel: Color(0xFF1B1B1E),
    raised: Color(0xFF26262A),
    raisedStrong: Color(0xFF2C2C31),
    well: Color(0xFF222226),
    ink: Color(0xFFF3F2EF),
    onInk: Color(0xFF111113),
    muted: Color(0xFFA3A1AA),
    subtle: Color(0xFF85838C),
    faint: Color(0xFF5C5B63),
    line: Color(0xFF2C2C31),
    lineSoft: Color(0xFF242428),
    track: Color(0xFF3A3A40),
    accent: Color(0xFF6E95FF),
    onAccent: Color(0xFF111113),
    accentSoft: Color(0xFF23283A),
    accentText: Color(0xFF9DB8FF),
    success: Color(0xFF30A46C),
    successSoft: Color(0xFF1A2E23),
    successText: Color(0xFF7EE0A8),
    warning: Color(0xFFE7A53B),
    warningSoft: Color(0xFF33291A),
    warningText: Color(0xFFF5C46B),
    danger: Color(0xFFE5484D),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFF3B1E20),
    dangerText: Color(0xFFFF8A80),
    scrim: Color(0x80000000),
  );

  /// The app background behind panels (phone settings, inbox, login).
  final Color paper;

  /// The circle rail's background.
  final Color rail;

  /// Rail items that are neither selected nor hovered.
  final Color railItem;

  /// Desktop sidebars and side panels (channel list, profile panel).
  final Color sidebar;

  /// Content panels, chat backgrounds, setting groups.
  final Color panel;

  /// Fills on top of a panel: round icon buttons, inputs, incoming bubbles,
  /// icon tiles, chips, selected rows.
  final Color raised;

  /// Fills on top of [paper] (secondary buttons on the sign-in page).
  final Color raisedStrong;

  /// Quiet blocks inside a panel: profile sections, quoted text, cards.
  final Color well;

  /// Main text, and the primary button / outgoing bubble fill.
  final Color ink;

  /// Text and icons on [ink].
  final Color onInk;

  /// Secondary text: previews, subtitles, timestamps.
  final Color muted;

  /// Section headers and placeholders.
  final Color subtle;

  /// Chevrons, disabled content, offline presence.
  final Color faint;

  /// Borders (inputs on paper, theme cards).
  final Color line;

  /// Separators inside groups and lists.
  final Color lineSoft;

  /// Off switch and slider tracks, the rail's divider.
  final Color track;

  /// Interactive accent: links, the compose button, switches, unread.
  final Color accent;
  final Color onAccent;

  /// Accent tint: the unread row, mentions, selected reaction.
  final Color accentSoft;

  /// Accent for text on [panel] (links, "just now").
  final Color accentText;

  /// Online, connected, "on" states.
  final Color success;
  final Color successSoft;
  final Color successText;

  /// Idle presence, raised hand, events today.
  final Color warning;
  final Color warningSoft;
  final Color warningText;

  /// Destructive actions, mention badges, do not disturb.
  final Color danger;
  final Color onDanger;
  final Color dangerSoft;
  final Color dangerText;

  /// Dims the page behind sheets and dialogs.
  final Color scrim;

  static WeCordPalette lerp(WeCordPalette a, WeCordPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return WeCordPalette(
      paper: c(a.paper, b.paper),
      rail: c(a.rail, b.rail),
      railItem: c(a.railItem, b.railItem),
      sidebar: c(a.sidebar, b.sidebar),
      panel: c(a.panel, b.panel),
      raised: c(a.raised, b.raised),
      raisedStrong: c(a.raisedStrong, b.raisedStrong),
      well: c(a.well, b.well),
      ink: c(a.ink, b.ink),
      onInk: c(a.onInk, b.onInk),
      muted: c(a.muted, b.muted),
      subtle: c(a.subtle, b.subtle),
      faint: c(a.faint, b.faint),
      line: c(a.line, b.line),
      lineSoft: c(a.lineSoft, b.lineSoft),
      track: c(a.track, b.track),
      accent: c(a.accent, b.accent),
      onAccent: c(a.onAccent, b.onAccent),
      accentSoft: c(a.accentSoft, b.accentSoft),
      accentText: c(a.accentText, b.accentText),
      success: c(a.success, b.success),
      successSoft: c(a.successSoft, b.successSoft),
      successText: c(a.successText, b.successText),
      warning: c(a.warning, b.warning),
      warningSoft: c(a.warningSoft, b.warningSoft),
      warningText: c(a.warningText, b.warningText),
      danger: c(a.danger, b.danger),
      onDanger: c(a.onDanger, b.onDanger),
      dangerSoft: c(a.dangerSoft, b.dangerSoft),
      dangerText: c(a.dangerText, b.dangerText),
      scrim: c(a.scrim, b.scrim),
    );
  }
}

/// Elevation is drawn with soft, warm shadows only (no Material tints).
@immutable
class WeCordShadows {
  const WeCordShadows({
    required this.hairline,
    required this.float,
    required this.menu,
    required this.dialog,
  });

  static const light = WeCordShadows(
    hairline: [
      BoxShadow(color: Color(0x0F17171A), blurRadius: 3, offset: Offset(0, 1)),
    ],
    float: [
      BoxShadow(
        color: Color(0x2417171A),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
    menu: [
      BoxShadow(
        color: Color(0x2E17171A),
        blurRadius: 44,
        offset: Offset(0, 18),
      ),
    ],
    dialog: [
      BoxShadow(
        color: Color(0x4D17171A),
        blurRadius: 80,
        offset: Offset(0, 30),
      ),
    ],
  );

  static const dark = WeCordShadows(
    hairline: [
      BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
    float: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
    menu: [
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 44,
        offset: Offset(0, 18),
      ),
    ],
    dialog: [
      BoxShadow(
        color: Color(0x99000000),
        blurRadius: 80,
        offset: Offset(0, 30),
      ),
    ],
  );

  /// Selected rows on a sidebar, small raised buttons.
  final List<BoxShadow> hairline;

  /// Floating bars: user panel, composer, toolbars over content.
  final List<BoxShadow> float;

  /// Long-press menus, popovers.
  final List<BoxShadow> menu;

  /// Dialogs and the desktop settings window.
  final List<BoxShadow> dialog;

  static WeCordShadows lerp(WeCordShadows a, WeCordShadows b, double t) {
    return WeCordShadows(
      hairline: BoxShadow.lerpList(a.hairline, b.hairline, t)!,
      float: BoxShadow.lerpList(a.float, b.float, t)!,
      menu: BoxShadow.lerpList(a.menu, b.menu, t)!,
      dialog: BoxShadow.lerpList(a.dialog, b.dialog, t)!,
    );
  }
}

/// The glass recipe for floating elements: a translucent fill over a
/// blurred, slightly saturated backdrop, a 1px light border and a soft
/// shadow. [solidFill] replaces it when glass is off.
@immutable
class WeCordGlassStyle {
  const WeCordGlassStyle({
    required this.fill,
    required this.solidFill,
    required this.border,
    required this.blur,
    required this.saturation,
  });

  static const light = WeCordGlassStyle(
    fill: Color(0xC2FFFFFF),
    solidFill: Color(0xFFFFFFFF),
    border: Color(0xE6FFFFFF),
    blur: 24,
    saturation: 1.8,
  );

  static const dark = WeCordGlassStyle(
    fill: Color(0xB82C2C32),
    solidFill: Color(0xFF2A2A2F),
    border: Color(0x14FFFFFF),
    blur: 24,
    saturation: 1.6,
  );

  final Color fill;
  final Color solidFill;
  final Color border;

  /// Backdrop blur sigma, in logical pixels.
  final double blur;

  /// Backdrop saturation boost (1 = unchanged).
  final double saturation;

  static WeCordGlassStyle lerp(
    WeCordGlassStyle a,
    WeCordGlassStyle b,
    double t,
  ) {
    return WeCordGlassStyle(
      fill: Color.lerp(a.fill, b.fill, t)!,
      solidFill: Color.lerp(a.solidFill, b.solidFill, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      blur: lerpDouble(a.blur, b.blur, t)!,
      saturation: lerpDouble(a.saturation, b.saturation, t)!,
    );
  }
}

/// Corner radii. Circles are for people; everything else is a squircle
/// (see ThingAvatar) or a rounded rectangle with these radii.
abstract final class WeCordRadii {
  /// Badges inside text, keyboard hints.
  static const xs = 6.0;

  /// Small tiles, media thumbnails, desktop nav rows.
  static const sm = 10.0;

  /// Icon tiles, desktop rail items, inputs on desktop.
  static const md = 14.0;

  /// Inputs, list rows, theme cards, media in bubbles.
  static const lg = 16.0;

  /// Setting groups, cards, glass menus.
  static const xl = 22.0;

  /// The panel's top-left corner, sheets, the composer.
  static const xxl = 28.0;

  /// Pill buttons, chips, switches, floating bars.
  static const pill = 999.0;

  /// Message bubbles: [bubble] outside, [bubbleTail] where messages of a
  /// run meet.
  static const bubble = 20.0;
  static const bubbleTail = 6.0;
}

/// The 4/8 spacing grid.
abstract final class WeCordSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;

  /// Side gutter of phone pages.
  static const gutter = 16.0;
}

/// Fixed sizes from the layout rules.
abstract final class WeCordSizes {
  /// Smallest touch target.
  static const touchTarget = 44.0;

  /// Primary pill buttons on phones.
  static const buttonLarge = 54.0;
  static const buttonMedium = 44.0;
  static const buttonSmall = 32.0;

  /// The circle rail: 68 on phones, 72 on desktop.
  static const railPhone = 68.0;
  static const railDesktop = 72.0;

  /// Desktop sidebar (channels, direct messages).
  static const sidebarMin = 272.0;
  static const sidebarMax = 292.0;

  /// Desktop right panel (profile, members).
  static const rightPanelMin = 248.0;
  static const rightPanelMax = 300.0;

  /// Room for the traffic lights above the rail on macOS.
  static const macosTitleBar = 28.0;
}
