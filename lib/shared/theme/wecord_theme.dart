import 'package:flutter/material.dart';

class WeCordTheme {
  const WeCordTheme._();

  static const _seedColor = Color(0xFF2F7CF6);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return _build(
      colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      navigationBarColor: Colors.white,
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _build(
      colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      navigationBarColor: colorScheme.surfaceContainer,
    );
  }

  static ThemeData _build(
    ColorScheme colorScheme, {
    required Color scaffoldBackgroundColor,
    required Color navigationBarColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationBarColor,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
