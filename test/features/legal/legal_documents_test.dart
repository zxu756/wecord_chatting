import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/features/legal/minimum_age.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'legal_test_support.dart';

String _file(LegalDocument document, {required bool chinese}) =>
    File(document.assetName(chinese: chinese)).readAsStringSync();

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the bundled texts', () {
    test('exist for every page in Chinese and English', () {
      for (final document in LegalDocument.values) {
        for (final chinese in [false, true]) {
          expect(
            File(document.assetName(chinese: chinese)).existsSync(),
            isTrue,
            reason: document.assetName(chinese: chinese),
          );
        }
      }
      expect(LegalDocument.values.map((d) => d.path), [
        '/legal/guidelines',
        '/legal/privacy',
        '/legal/terms',
      ]);
    });

    test('start with a visible draft note, in the page\'s language', () {
      for (final document in LegalDocument.values) {
        expect(
          _file(document, chinese: false),
          startsWith('> **Draft — pending owner review.**'),
          reason: '${document.slug} en',
        );
        expect(
          _file(document, chinese: true),
          startsWith('> **草稿——待所有者确认。**'),
          reason: '${document.slug} zh',
        );
      }
    });

    test('are bundled with the app', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- assets/legal/'),
      );
    });

    test('take the minimum age from the one constant, never a literal', () {
      expect(minimumAge, 13);
      for (final chinese in [false, true]) {
        for (final document in LegalDocument.values) {
          final text = _file(document, chinese: chinese);
          expect(
            RegExp(
              r'(\d+\s*(\*\*)?\s*years? old|\d+\s*周岁|年满\s*\*{0,2}\d+|at least \*{0,2}\d+)',
            ).hasMatch(text),
            isFalse,
            reason: '${document.slug} has an age written out',
          );
        }
        expect(
          _file(LegalDocument.terms, chinese: chinese),
          contains('{minimumAge}'),
        );
        expect(
          _file(LegalDocument.privacy, chinese: chinese),
          contains('{minimumAge}'),
        );
      }
    });

    test('are read with the age filled in', () async {
      final terms = await LegalDocument.terms.load(
        bundle: DiskAssetBundle(),
        chinese: false,
      );
      expect(terms, contains('at least **$minimumAge years old**'));
      expect(terms, isNot(contains('{minimumAge}')));
      final privacy = await LegalDocument.privacy.load(
        bundle: DiskAssetBundle(),
        chinese: true,
      );
      expect(privacy, contains('年满 $minimumAge 周岁'));
    });

    test('the privacy policy describes every real data flow', () {
      final english = _file(LegalDocument.privacy, chinese: false);
      final chinese = _file(LegalDocument.privacy, chinese: true);
      for (final name in [
        'Supabase',
        'LiveKit',
        'OpenCode Go',
        'Gotenberg',
        'OpenStreetMap',
        'Nominatim',
        'GIPHY',
      ]) {
        expect(english, contains(name), reason: 'en $name');
        expect(chinese, contains(name), reason: 'zh $name');
      }
      for (final topic in [
        'Only when you use an AI feature',
        'Web push',
        'Crash and error reports',
        'Export your data',
        'Delete your account',
        'View-once',
        '90 days',
      ]) {
        expect(english, contains(topic), reason: 'en $topic');
      }
      for (final topic in [
        '仅在你使用 AI 功能时',
        '网页推送',
        '崩溃和错误报告',
        '导出数据',
        '删除账号',
        '阅后即焚',
        '90 天',
      ]) {
        expect(chinese, contains(topic), reason: 'zh $topic');
      }
    });

    test('links between the pages point at real pages', () {
      for (final chinese in [false, true]) {
        for (final document in LegalDocument.values) {
          for (final match in RegExp(
            r'\(wecord:([a-z]+)\)',
          ).allMatches(_file(document, chinese: chinese))) {
            expect(
              LegalDocument.fromSlug(match.group(1)),
              isNotNull,
              reason: match.group(0),
            );
          }
        }
      }
    });

    test('the guidelines tell how to report and what happens', () {
      final english = _file(LegalDocument.guidelines, chinese: false);
      expect(english, contains('Reporting'));
      expect(english, contains("circle's moderators"));
      expect(english, contains('WeCord team'));
      expect(english, contains('not told who reported them'));
    });
  });

  testWidgets('a page shows its title, the draft note and the text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: DefaultAssetBundle(
          bundle: DiskAssetBundle(),
          child: const LegalDocumentScreen(document: LegalDocument.terms),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terms of Service'), findsWidgets);
    expect(
      find.textContaining('Draft — pending owner review.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('at least 13 years old', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a page reads in Chinese when the app does', (tester) async {
    AppStrings.isChinese = true;
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: DefaultAssetBundle(
          bundle: DiskAssetBundle(),
          child: const LegalDocumentScreen(document: LegalDocument.privacy),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsWidgets);
    expect(
      find.textContaining('草稿——待所有者确认。', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('LiveKit Cloud', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a link to another policy opens that page', (tester) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: DefaultAssetBundle(
          bundle: DiskAssetBundle(),
          child: const LegalDocumentScreen(document: LegalDocument.terms),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "[Community Guidelines](wecord:guidelines)" in the first paragraph.
    tester
        .widget<MarkdownBody>(find.byKey(const ValueKey('legal-body')))
        .onTapLink!('Community Guidelines', 'wecord:guidelines', '');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('legal-guidelines')), findsOneWidget);
  });

  testWidgets('a page that cannot be loaded says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: DefaultAssetBundle(
          bundle: _EmptyBundle(),
          child: const LegalDocumentScreen(document: LegalDocument.terms),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load this page.'), findsOneWidget);
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('no asset');
}
