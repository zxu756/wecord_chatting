import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How much bigger Care mode makes text, on top of the device's own size.
const careTextScale = 1.3;

/// The most Care mode takes the text to. The layouts are checked up to 2.0x;
/// someone who already has a big system size gets that, not more.
const careTextScaleCeiling = 2.0;

/// A text scaler that makes what [base] (the system's) gives [factor] times
/// bigger, but never past [ceiling] times the font size, and never smaller
/// than [base] itself.
@immutable
class CareTextScaler extends TextScaler {
  const CareTextScaler(
    this.base, {
    this.factor = careTextScale,
    this.ceiling = careTextScaleCeiling,
  });

  final TextScaler base;
  final double factor;
  final double ceiling;

  @override
  double scale(double fontSize) {
    final system = base.scale(fontSize);
    return math.max(system, math.min(system * factor, fontSize * ceiling));
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is CareTextScaler &&
      other.base == base &&
      other.factor == factor &&
      other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(base, factor, ceiling);
}

/// Care mode's choices for everything below it.
class CareModeScope extends InheritedWidget {
  const CareModeScope({
    required this.settings,
    required super.child,
    super.key,
  });

  final CareModeSettings settings;

  @override
  bool updateShouldNotify(CareModeScope oldWidget) =>
      settings != oldWidget.settings;

  /// The choices at [context]; all off without a scope.
  static CareModeSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CareModeScope>()?.settings ??
      const CareModeSettings();
}

extension CareModeContext on BuildContext {
  /// Whether Care mode is on here.
  bool get careMode => CareModeScope.of(this).enabled;

  /// Care mode's choices here.
  CareModeSettings get careSettings => CareModeScope.of(this);
}

/// Puts Care mode on the app: text 1.3x (up to 2.0x), bigger tap areas and
/// buttons, and the scope the pages read their options from.
///
/// The app builder wraps everything in this, always. The same widgets stay
/// in the tree whether Care mode is on or off, so turning it on or off only
/// changes sizes: the page, its drafts and its scroll position stay.
class CareModeHost extends ConsumerWidget {
  const CareModeHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(careModeProvider);
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return CareModeScope(
      settings: settings,
      child: Theme(
        data: settings.enabled ? careTheme(theme) : theme,
        child: MediaQuery(
          data: settings.enabled
              ? media.copyWith(textScaler: CareTextScaler(media.textScaler))
              : media,
          child: child,
        ),
      ),
    );
  }
}

/// [theme] with Care mode's sizes: the care extension (tap areas, round
/// buttons, pill buttons) and taller Material buttons.
ThemeData careTheme(ThemeData theme) {
  final care = WeCordCareTheme.forPlatform(theme.platform);
  final minimum = WidgetStatePropertyAll(Size(64, care.buttonHeight));
  return theme.copyWith(
    extensions: [
      for (final extension in theme.extensions.values)
        if (extension is! WeCordCareTheme) extension,
      care,
    ],
    filledButtonTheme: FilledButtonThemeData(
      style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: minimum,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: minimum,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: minimum,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: WidgetStatePropertyAll(Size(64, care.buttonHeight - 8)),
      ),
    ),
  );
}
