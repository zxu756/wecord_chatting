import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// WCAG 2.x contrast ratio of two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final sets = <String, WeCordTokens>{
    'light': WeCordTokens.light,
    'dark': WeCordTokens.dark,
    'light high contrast': WeCordTokens.lightHighContrast,
    'dark high contrast': WeCordTokens.darkHighContrast,
  };

  for (final entry in sets.entries) {
    final name = entry.key;
    final tokens = entry.value;
    final c = tokens.colors;
    final surfaces = {
      'paper': c.paper,
      'sidebar': c.sidebar,
      'panel': c.panel,
      'raised': c.raised,
      'well': c.well,
    };

    group('$name tokens', () {
      test('body text clears 4.5:1 on every surface it sits on', () {
        for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
          expect(
            contrast(c.ink, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'ink on $surface',
          );
          expect(
            contrast(c.muted, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'muted on $surface',
          );
        }
        expect(contrast(c.muted, c.raisedStrong), greaterThanOrEqualTo(4.5));
        expect(contrast(c.muted, c.accentSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(c.ink, c.accentSoft), greaterThanOrEqualTo(4.5));
      });

      test('section headers and placeholders (subtle) clear 4.5:1', () {
        for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
          expect(
            contrast(c.subtle, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'subtle on $surface',
          );
        }
      });

      test('accent and status text clear 4.5:1', () {
        for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
          expect(
            contrast(c.accentText, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'accentText on $surface',
          );
          expect(
            contrast(c.successText, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'successText on $surface',
          );
          expect(
            contrast(c.warningText, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'warningText on $surface',
          );
          expect(
            contrast(c.dangerText, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'dangerText on $surface',
          );
        }
        expect(contrast(c.accentText, c.accentSoft), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.successText, c.successSoft),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(c.warningText, c.warningSoft),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(c.dangerText, c.dangerSoft), greaterThanOrEqualTo(4.5));
      });

      test('text on filled controls clears 4.5:1', () {
        expect(contrast(c.onInk, c.ink), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onDanger, c.danger), greaterThanOrEqualTo(4.5));
      });

      test('icons, dots and the accent clear 3:1 on panels and fills', () {
        for (final MapEntry(key: surface, value: bg) in surfaces.entries) {
          expect(
            contrast(c.accent, bg),
            greaterThanOrEqualTo(3),
            reason: 'accent on $surface',
          );
          expect(
            contrast(c.faint, bg),
            greaterThanOrEqualTo(3),
            reason: 'faint on $surface',
          );
          expect(
            contrast(c.danger, bg),
            greaterThanOrEqualTo(3),
            reason: 'danger on $surface',
          );
          expect(
            contrast(c.success, bg),
            greaterThanOrEqualTo(3),
            reason: 'success on $surface',
          );
        }
        expect(contrast(c.warning, c.panel), greaterThanOrEqualTo(3));
      });

      test('the glass fill keeps text readable over difficult backdrops', () {
        final fill = tokens.glass.fill;
        // The worst content that scrolls under a header or composer: the
        // opposite extreme of the theme (an ink bubble or black in the
        // light theme, mid gray in the dark one, which has bright bubbles
        // and photos).
        final backdrops = tokens.isDark
            ? [const Color(0xFF808080), c.panel]
            : [const Color(0xFF000000), c.ink, const Color(0xFF808080)];
        for (final backdrop in backdrops) {
          final glass = Color.alphaBlend(fill, backdrop);
          expect(contrast(c.ink, glass), greaterThanOrEqualTo(4.5));
          expect(
            contrast(c.muted, glass),
            greaterThanOrEqualTo(4.5),
            reason: 'muted over $backdrop',
          );
        }
      });

      if (tokens.highContrast) {
        test('lines, tracks and the glass edge are visible (3:1)', () {
          for (final bg in [c.paper, c.panel, c.sidebar]) {
            expect(contrast(c.line, bg), greaterThanOrEqualTo(3));
            expect(contrast(c.lineSoft, bg), greaterThanOrEqualTo(3));
            expect(contrast(c.track, bg), greaterThanOrEqualTo(3));
          }
          expect(
            contrast(tokens.glass.border, c.panel),
            greaterThanOrEqualTo(3),
          );
          expect(tokens.glass.fill.a, 1);
        });
      }
    });
  }
}
