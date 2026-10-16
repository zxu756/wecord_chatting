import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/theme/wecord_field_border.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The app's themes in design language "C" (docs/design/wecord-design-language.md):
/// warm paper and ink, one blue accent, big friendly type, pill buttons,
/// filled borderless inputs and no Material ripples or elevation tints.
///
/// The color scheme maps the [WeCordPalette] onto Material roles so stock
/// widgets pick it up; new UI should read `context.tokens` instead.
class WeCordTheme {
  const WeCordTheme._();

  /// The Latin font, bundled under assets/fonts.
  static const fontFamily = 'Plus Jakarta Sans';

  /// Fonts tried for characters Plus Jakarta Sans lacks: the platform's
  /// color emoji, then its Chinese font (PingFang SC on Apple platforms,
  /// Microsoft YaHei on Windows, Noto Sans SC elsewhere). The system's own
  /// fallback still applies after these.
  static List<String> get fontFamilyFallback {
    if (kIsWeb) {
      return const [
        'Apple Color Emoji',
        'Noto Color Emoji',
        'PingFang SC',
        'Noto Sans SC',
        'Microsoft YaHei',
      ];
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'Apple Color Emoji',
        'PingFang SC',
        'Hiragino Sans GB',
      ],
      TargetPlatform.windows => const [
        'Segoe UI Emoji',
        'Microsoft YaHei',
        'Noto Sans SC',
      ],
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux => const [
        'Noto Color Emoji',
        'Noto Sans SC',
        'Noto Sans CJK SC',
      ],
    };
  }

  /// Transparent system bars with icons that contrast with a page of
  /// [brightness], for pages drawn under the status bar and the home
  /// indicator (app bars pick their own).
  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return base.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData light() => _build(WeCordTokens.light);

  static ThemeData dark() => _build(WeCordTokens.dark);

  static ColorScheme _colorScheme(WeCordTokens tokens) {
    final c = tokens.colors;
    final dark = tokens.isDark;
    return ColorScheme(
      brightness: tokens.brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: dark ? const Color(0xFFC6D6FF) : c.accentText,
      secondary: c.ink,
      onSecondary: c.onInk,
      secondaryContainer: dark ? c.raisedStrong : c.lineSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.success,
      onTertiary: Colors.white,
      tertiaryContainer: c.successSoft,
      onTertiaryContainer: c.successText,
      error: c.danger,
      onError: c.onDanger,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.dangerText,
      surface: c.panel,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      // Light: white cards on warm paper, the rail a shade darker. Dark:
      // graphite steps from the page up to raised fills.
      surfaceContainerLowest: dark ? c.paper : c.panel,
      surfaceContainerLow: dark ? c.panel : c.sidebar,
      surfaceContainer: dark ? const Color(0xFF1F1F23) : c.paper,
      surfaceContainerHigh: dark ? const Color(0xFF222226) : c.rail,
      surfaceContainerHighest: c.raised,
      surfaceDim: dark ? c.paper : c.rail,
      surfaceBright: dark ? c.raised : c.panel,
      surfaceTint: Colors.transparent,
      outline: c.faint,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.ink,
      onInverseSurface: c.onInk,
      inversePrimary: dark
          ? WeCordPalette.light.accent
          : WeCordPalette.dark.accent,
    );
  }

  static TextTheme _textTheme(WeCordPalette c) {
    TextStyle style(
      double size,
      FontWeight weight, {
      double letterSpacing = 0,
      double? height,
    }) {
      return TextStyle(
        // Spelled out on every style so component themes built from them
        // (badges, buttons, chips) keep the font too.
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        color: c.ink,
      );
    }

    return TextTheme(
      // Large titles: the sign-in hero, page titles, sheet titles.
      displayLarge: style(34, FontWeight.w800, letterSpacing: -0.9),
      displayMedium: style(32, FontWeight.w800, letterSpacing: -0.8),
      displaySmall: style(28, FontWeight.w800, letterSpacing: -0.6),
      headlineLarge: style(26, FontWeight.w800, letterSpacing: -0.6),
      headlineMedium: style(24, FontWeight.w800, letterSpacing: -0.4),
      headlineSmall: style(20, FontWeight.w800, letterSpacing: -0.4),
      titleLarge: style(20, FontWeight.w700, letterSpacing: -0.3),
      titleMedium: style(16, FontWeight.w700),
      titleSmall: style(14, FontWeight.w700),
      bodyLarge: style(16, FontWeight.w400),
      bodyMedium: style(14, FontWeight.w400),
      bodySmall: style(12, FontWeight.w500).copyWith(color: c.muted),
      labelLarge: style(14, FontWeight.w700),
      labelMedium: style(12, FontWeight.w700),
      labelSmall: style(11, FontWeight.w700),
    );
  }

  static ThemeData _build(WeCordTokens tokens) {
    final c = tokens.colors;
    final dark = tokens.isDark;
    final colorScheme = _colorScheme(tokens);
    final textTheme = _textTheme(c);
    const pill = StadiumBorder();
    final hover = c.ink.withValues(alpha: dark ? 0.08 : 0.05);
    final pressed = c.ink.withValues(alpha: dark ? 0.12 : 0.08);
    final focus = c.accent.withValues(alpha: 0.16);
    // Text and links on an ink snack bar or tooltip read in the opposite
    // theme's colors.
    final inverse = dark ? WeCordPalette.light : WeCordPalette.dark;

    WidgetStateProperty<Color?> overlay({Color? base}) {
      final tint = base ?? c.ink;
      return WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return tint.withValues(alpha: dark ? 0.14 : 0.10);
        }
        if (states.contains(WidgetState.focused)) {
          return focus;
        }
        if (states.contains(WidgetState.hovered)) {
          return tint.withValues(alpha: dark ? 0.08 : 0.06);
        }
        return null;
      });
    }

    final buttonText = textTheme.labelLarge!.copyWith(fontSize: 15);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20);
    const buttonMinimumSize = Size(64, WeCordSizes.buttonMedium);

    const inputBorder = WeCordFieldBorder(
      borderRadius: BorderRadius.all(Radius.circular(WeCordRadii.lg)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: colorScheme,
      extensions: [tokens],
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.panel,
      canvasColor: c.panel,
      cardColor: c.panel,
      dividerColor: c.lineSoft,
      disabledColor: c.faint,
      hintColor: c.subtle,
      // No ink ripples: hover, focus and press tint instead.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: pressed,
      hoverColor: hover,
      focusColor: focus,
      applyElevationOverlayColor: false,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.28),
        selectionHandleColor: c.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        iconTheme: IconThemeData(color: c.ink),
        actionsIconTheme: IconThemeData(color: c.ink),
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: overlayStyleFor(tokens.brightness),
      ),
      iconTheme: IconThemeData(color: c.ink, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.12)
                : c.ink,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.38)
                : c.onInk,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.38)
                : c.onInk,
          ),
          overlayColor: overlay(base: c.onInk),
          textStyle: WidgetStatePropertyAll(buttonText),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          shape: WidgetStatePropertyAll(pill),
          elevation: const WidgetStatePropertyAll(0),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      // Outlined buttons are the design's secondary buttons: a quiet fill,
      // no outline.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.raised.withValues(alpha: 0.5)
                : c.raised,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.38)
                : c.ink,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.38)
                : c.ink,
          ),
          overlayColor: overlay(),
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: WidgetStatePropertyAll(buttonText),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          shape: WidgetStatePropertyAll(pill),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.ink.withValues(alpha: 0.38)
                : c.accentText,
          ),
          overlayColor: overlay(base: c.accent),
          textStyle: WidgetStatePropertyAll(buttonText),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          shape: WidgetStatePropertyAll(pill),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(c.panel),
          foregroundColor: WidgetStatePropertyAll(c.ink),
          overlayColor: overlay(),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(buttonText),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          shape: WidgetStatePropertyAll(pill),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: overlay(),
          shape: WidgetStatePropertyAll(pill),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: pill,
        extendedTextStyle: buttonText,
        splashColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.raised,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        labelStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
        floatingLabelStyle: TextStyle(
          color: c.muted,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: c.subtle),
        helperStyle: TextStyle(color: c.muted),
        errorStyle: TextStyle(color: c.dangerText),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
      ),
      cardTheme: CardThemeData(
        color: c.well,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        iconColor: c.muted,
        textColor: c.ink,
        titleTextStyle: textTheme.bodyLarge!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodyMedium!.copyWith(color: c.muted),
        leadingAndTrailingTextStyle: textTheme.bodySmall,
        selectedColor: c.ink,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      dividerTheme: DividerThemeData(color: c.lineSoft, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.3),
        elevation: 16,
        barrierColor: c.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium!.copyWith(color: c.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.panel,
        modalBackgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: c.scrim,
        clipBehavior: Clip.antiAlias,
        dragHandleColor: c.faint,
        dragHandleSize: const Size(40, 5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WeCordRadii.xxl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: c.onInk,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: inverse.accentText,
        closeIconColor: c.onInk,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.labelMedium!.copyWith(
          color: c.onInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.raised,
        selectedColor: c.ink,
        disabledColor: c.raised.withValues(alpha: 0.5),
        secondarySelectedColor: c.ink,
        checkmarkColor: c.onInk,
        deleteIconColor: c.muted,
        iconTheme: IconThemeData(color: c.ink, size: 18),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => textTheme.labelLarge!.copyWith(
            fontSize: 13,
            color: states.contains(WidgetState.selected) ? c.onInk : c.ink,
          ),
        ),
        secondaryLabelStyle: textTheme.labelLarge!.copyWith(
          fontSize: 13,
          color: c.onInk,
        ),
        side: BorderSide.none,
        shape: pill,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) && !dark
              ? const Color(0xFFF7F6F3)
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          final color = on ? c.accent : c.track;
          return states.contains(WidgetState.disabled)
              ? color.withValues(alpha: 0.5)
              : color;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        // A thumb icon (even an empty one) keeps the thumb full size in
        // both positions, like an iOS switch.
        thumbIcon: const WidgetStatePropertyAll(Icon(null)),
        overlayColor: overlay(base: c.accent),
        splashRadius: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : null,
        ),
        checkColor: WidgetStatePropertyAll(c.onAccent),
        side: BorderSide(color: c.faint, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        overlayColor: overlay(base: c.accent),
        splashRadius: 0,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.accent : c.faint,
        ),
        overlayColor: overlay(base: c.accent),
        splashRadius: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? (dark ? c.raisedStrong : c.panel)
                : c.raised,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? c.faint
                : states.contains(WidgetState.selected)
                ? c.ink
                : c.muted,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
          overlayColor: overlay(),
          side: WidgetStatePropertyAll(BorderSide(color: c.raised, width: 3)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge!.copyWith(fontSize: 13),
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.rail,
        indicatorColor: c.railItem,
        selectedIconTheme: IconThemeData(color: c.ink),
        unselectedIconTheme: IconThemeData(color: c.muted),
        selectedLabelTextStyle: textTheme.labelMedium,
        unselectedLabelTextStyle: textTheme.labelMedium!.copyWith(
          color: c.muted,
        ),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.muted,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        indicatorColor: c.ink,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.lineSoft,
        overlayColor: overlay(),
        splashFactory: NoSplash.splashFactory,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        textStyle: textTheme.bodyLarge,
        labelTextStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.panel),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: dark ? 0.6 : 0.25),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.raised,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.track,
        thumbColor: Colors.white,
        overlayColor: c.accent.withValues(alpha: 0.12),
        trackHeight: 6,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.danger,
        textColor: c.onDanger,
        textStyle: textTheme.labelSmall!.copyWith(fontSize: 10),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(WeCordRadii.pill),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => c.ink.withValues(
            alpha: states.contains(WidgetState.dragged)
                ? 0.40
                : states.contains(WidgetState.hovered)
                ? 0.30
                : 0.20,
          ),
        ),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: c.warningSoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
