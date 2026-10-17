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
    this.highContrast = false,
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

  /// The light set for the platform's "Increase contrast" setting: darker
  /// secondary text, visible lines and switch tracks, solid glass.
  static const lightHighContrast = WeCordTokens(
    brightness: Brightness.light,
    colors: WeCordPalette.lightHighContrast,
    shadows: WeCordShadows.light,
    glass: WeCordGlassStyle.lightHighContrast,
    highContrast: true,
  );

  /// The dark set for "Increase contrast".
  static const darkHighContrast = WeCordTokens(
    brightness: Brightness.dark,
    colors: WeCordPalette.darkHighContrast,
    shadows: WeCordShadows.dark,
    glass: WeCordGlassStyle.darkHighContrast,
    highContrast: true,
  );

  final Brightness brightness;

  /// Whether this is a high contrast set (see [lightHighContrast]).
  final bool highContrast;
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
    bool? highContrast,
  }) {
    return WeCordTokens(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      shadows: shadows ?? this.shadows,
      glass: glass ?? this.glass,
      highContrast: highContrast ?? this.highContrast,
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
      highContrast: t < 0.5 ? highContrast : other.highContrast,
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
    required this.badgeMention,
    required this.onBadgeMention,
    required this.badgeUnread,
    required this.onBadgeUnread,
    required this.live,
    required this.onLive,
    required this.liveSoft,
    required this.liveText,
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
    muted: Color(0xFF5F5E66),
    subtle: Color(0xFF6F6D76),
    faint: Color(0xFF8D8994),
    line: Color(0xFFE4E2DD),
    lineSoft: Color(0xFFEFEDE8),
    track: Color(0xFFD6D3CC),
    accent: Color(0xFF2F6BF6),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE9F0FF),
    accentText: Color(0xFF1F5FE0),
    success: Color(0xFF2E9D67),
    successSoft: Color(0xFFE3F3EA),
    successText: Color(0xFF1F7846),
    warning: Color(0xFFCA8619),
    warningSoft: Color(0xFFFFF6E6),
    warningText: Color(0xFF8A5A00),
    danger: Color(0xFFE12F35),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFFFDECEC),
    dangerText: Color(0xFFD12B1F),
    badgeMention: Color(0xFFE12F35),
    onBadgeMention: Color(0xFFFFFFFF),
    badgeUnread: Color(0xFF6F6D76),
    onBadgeUnread: Color(0xFFFFFFFF),
    live: Color(0xFF1F7A47),
    onLive: Color(0xFFFFFFFF),
    liveSoft: Color(0xFFE3F3EA),
    liveText: Color(0xFF1F7846),
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
    subtle: Color(0xFF94929A),
    faint: Color(0xFF706F78),
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
    danger: Color(0xFFE12F35),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFF3B1E20),
    dangerText: Color(0xFFFF8A80),
    badgeMention: Color(0xFFE12F35),
    onBadgeMention: Color(0xFFFFFFFF),
    badgeUnread: Color(0xFF73717C),
    onBadgeUnread: Color(0xFFFFFFFF),
    live: Color(0xFF30A46C),
    onLive: Color(0xFF07140D),
    liveSoft: Color(0xFF1A2E23),
    liveText: Color(0xFF7EE0A8),
    scrim: Color(0x80000000),
  );

  /// [light] for "Increase contrast": ink is black, secondary text clears
  /// 7:1, borders and switch tracks clear 3:1 against what they sit on.
  static const lightHighContrast = WeCordPalette(
    paper: Color(0xFFF5F4F1),
    rail: Color(0xFFECEAE5),
    railItem: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFAF9F7),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF2F1EE),
    raisedStrong: Color(0xFFECEAE5),
    well: Color(0xFFF7F6F3),
    ink: Color(0xFF000000),
    onInk: Color(0xFFFFFFFF),
    muted: Color(0xFF3F3E45),
    subtle: Color(0xFF4A4950),
    faint: Color(0xFF6B6A72),
    line: Color(0xFF76747D),
    lineSoft: Color(0xFF8A8892),
    track: Color(0xFF8A867B),
    accent: Color(0xFF1B49C9),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE9F0FF),
    accentText: Color(0xFF173FA8),
    success: Color(0xFF1F7A47),
    successSoft: Color(0xFFE3F3EA),
    successText: Color(0xFF14602F),
    warning: Color(0xFF946400),
    warningSoft: Color(0xFFFFF6E6),
    warningText: Color(0xFF6B4400),
    danger: Color(0xFFC4161C),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFFFDECEC),
    dangerText: Color(0xFFA8130F),
    badgeMention: Color(0xFFC4161C),
    onBadgeMention: Color(0xFFFFFFFF),
    badgeUnread: Color(0xFF4A4950),
    onBadgeUnread: Color(0xFFFFFFFF),
    live: Color(0xFF14602F),
    onLive: Color(0xFFFFFFFF),
    liveSoft: Color(0xFFE3F3EA),
    liveText: Color(0xFF14602F),
    scrim: Color(0x8017171A),
  );

  /// [dark] for "Increase contrast".
  static const darkHighContrast = WeCordPalette(
    paper: Color(0xFF111113),
    rail: Color(0xFF111113),
    railItem: Color(0xFF1F1F23),
    sidebar: Color(0xFF18181B),
    panel: Color(0xFF1B1B1E),
    raised: Color(0xFF26262A),
    raisedStrong: Color(0xFF2C2C31),
    well: Color(0xFF222226),
    ink: Color(0xFFFFFFFF),
    onInk: Color(0xFF000000),
    muted: Color(0xFFD0CED6),
    subtle: Color(0xFFC0BEC6),
    faint: Color(0xFF9694A0),
    line: Color(0xFF8A8893),
    lineSoft: Color(0xFF6E6D78),
    track: Color(0xFF7C7B86),
    accent: Color(0xFF9DB8FF),
    onAccent: Color(0xFF000000),
    accentSoft: Color(0xFF23283A),
    accentText: Color(0xFFB8CBFF),
    success: Color(0xFF4CC38A),
    successSoft: Color(0xFF1A2E23),
    successText: Color(0xFF8FEBB8),
    warning: Color(0xFFF2B94F),
    warningSoft: Color(0xFF33291A),
    warningText: Color(0xFFFFD58A),
    danger: Color(0xFFFF6B70),
    onDanger: Color(0xFF000000),
    dangerSoft: Color(0xFF3B1E20),
    dangerText: Color(0xFFFFA39B),
    badgeMention: Color(0xFFFF6B70),
    onBadgeMention: Color(0xFF000000),
    badgeUnread: Color(0xFF8A8893),
    onBadgeUnread: Color(0xFF000000),
    live: Color(0xFF4CC38A),
    onLive: Color(0xFF000000),
    liveSoft: Color(0xFF1A2E23),
    liveText: Color(0xFF8FEBB8),
    scrim: Color(0xB3000000),
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

  /// Badges that mean "this needs you": @mentions, the Review queue, friend
  /// requests, the notification inbox, missed calls. The only red badge.
  final Color badgeMention;
  final Color onBadgeMention;

  /// Plain unread counts and dots (messages in a chat, a channel): a calm
  /// gray, so red stays rare.
  final Color badgeUnread;
  final Color onBadgeUnread;

  /// "Live now": an event or a call in progress. A fill with its text color,
  /// a soft tint for cards and text on that tint (or on a panel).
  final Color live;
  final Color onLive;
  final Color liveSoft;
  final Color liveText;

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
      badgeMention: c(a.badgeMention, b.badgeMention),
      onBadgeMention: c(a.onBadgeMention, b.onBadgeMention),
      badgeUnread: c(a.badgeUnread, b.badgeUnread),
      onBadgeUnread: c(a.onBadgeUnread, b.onBadgeUnread),
      live: c(a.live, b.live),
      onLive: c(a.onLive, b.onLive),
      liveSoft: c(a.liveSoft, b.liveSoft),
      liveText: c(a.liveText, b.liveText),
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

  // The fills are strong enough that secondary text keeps 4.5:1 even over
  // dark content (an ink bubble scrolling under the header).
  static const light = WeCordGlassStyle(
    fill: Color(0xE0FFFFFF),
    solidFill: Color(0xFFFFFFFF),
    border: Color(0xE6FFFFFF),
    blur: 24,
    saturation: 1.8,
  );

  static const dark = WeCordGlassStyle(
    fill: Color(0xE62C2C32),
    solidFill: Color(0xFF2A2A2F),
    border: Color(0x14FFFFFF),
    blur: 24,
    saturation: 1.6,
  );

  /// Solid glass with a visible edge, for "Increase contrast".
  static const lightHighContrast = WeCordGlassStyle(
    fill: Color(0xFFFFFFFF),
    solidFill: Color(0xFFFFFFFF),
    border: Color(0xFF76747D),
    blur: 0,
    saturation: 1,
  );

  static const darkHighContrast = WeCordGlassStyle(
    fill: Color(0xFF2A2A2F),
    solidFill: Color(0xFF2A2A2F),
    border: Color(0xFF8A8893),
    blur: 0,
    saturation: 1,
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

  /// Desktop sidebar (direct messages and a circle's channels share one
  /// width): 292 until the user drags it, between 220 and 420.
  static const sidebarDefault = 292.0;
  static const sidebarMin = 220.0;
  static const sidebarMax = 420.0;

  /// A circle's member list on the right: 248, resizable 200–360.
  static const memberListDefault = 248.0;
  static const memberListMin = 200.0;
  static const memberListMax = 360.0;

  /// The profile panel beside a direct chat: 300, resizable 240–420.
  static const profilePanelDefault = 300.0;
  static const profilePanelMin = 240.0;
  static const profilePanelMax = 420.0;

  /// The notes and lists panel beside a chat: 440, resizable 340–760.
  static const docsPanelDefault = 440.0;
  static const docsPanelMin = 340.0;
  static const docsPanelMax = 760.0;

  /// The narrowest the centre content (the chat) gets before right panels
  /// close and then the sidebar shrinks.
  static const contentMin = 420.0;

  /// Room for the traffic lights above the rail on macOS.
  static const macosTitleBar = 28.0;
}

/// How tightly lists and messages sit (Settings → Appearance → Density).
/// It scales row heights and padding (direct messages, channels, members),
/// the gaps between messages and the avatars on message cards. Read it,
/// resolved for the input, with `context.density`.
enum WeCordDensity {
  comfortable(spacing: 1.3, avatar: 1.1, rowDelta: 4),
  standard(spacing: 1, avatar: 1, rowDelta: 0),
  compact(spacing: 0.6, avatar: 0.8, rowDelta: -6);

  const WeCordDensity({
    required this.spacing,
    required this.avatar,
    required this.rowDelta,
  });

  /// Multiplies vertical padding and gaps.
  final double spacing;

  /// Multiplies avatar sizes in rows and message cards.
  final double avatar;

  /// Added to fixed row heights.
  final double rowDelta;

  /// The density chosen above [context]; [standard] without a
  /// [WeCordDensityScope].
  static WeCordDensity of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WeCordDensityScope>()
          ?.density ??
      standard;
}

/// Puts the Density setting above the app (the app builder adds one).
class WeCordDensityScope extends InheritedWidget {
  const WeCordDensityScope({
    required this.density,
    required super.child,
    super.key,
  });

  final WeCordDensity density;

  @override
  bool updateShouldNotify(WeCordDensityScope oldWidget) =>
      density != oldWidget.density;
}

/// [WeCordDensity] applied to sizes. On touch screens Compact only tightens
/// a little and rows never drop below [WeCordSizes.touchTarget], so taps
/// stay easy; with a mouse it goes all the way.
@immutable
class WeCordDensityScale {
  const WeCordDensityScale(this.density, {this.touch = false});

  final WeCordDensity density;

  /// Whether fingers are the main input.
  final bool touch;

  bool get _softened => touch && density == WeCordDensity.compact;

  /// A vertical padding or gap.
  double space(double value) => value * (_softened ? 0.85 : density.spacing);

  /// An avatar size, kept to whole pixels.
  double avatar(double size) =>
      _softened ? size : (size * density.avatar).roundToDouble();

  /// A fixed row height; at least a touch target on touch screens.
  double rowHeight(double base) {
    final height = base + (_softened ? 0 : density.rowDelta);
    return touch && height < WeCordSizes.touchTarget
        ? WeCordSizes.touchTarget
        : height;
  }

  /// The smallest height of a row whose height comes from its content.
  double get minRowHeight => touch ? WeCordSizes.touchTarget : 0;

  @override
  bool operator ==(Object other) =>
      other is WeCordDensityScale &&
      other.density == density &&
      other.touch == touch;

  @override
  int get hashCode => Object.hash(density, touch);
}

extension WeCordDensityContext on BuildContext {
  /// The Density setting here, resolved for the platform's input.
  WeCordDensityScale get density => WeCordDensityScale(
    WeCordDensity.of(this),
    touch: switch (Theme.of(this).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    },
  );
}
