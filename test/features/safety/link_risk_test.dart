import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/safety/link_risk.dart';

void main() {
  // The same cases run against the server's copy of the rules
  // (supabase/functions/link-preview/link_risk_test.ts).
  final cases =
      jsonDecode(File('test/fixtures/link_risk_cases.json').readAsStringSync())
          as List;

  group('the rules agree with the server on every shared case', () {
    for (final entry in cases) {
      final testCase = entry as Map<String, dynamic>;
      test('risk of ${testCase['url']}', () {
        final risk = assessLink(testCase['url'] as String);
        expect(risk.level.name, testCase['level'], reason: '${risk.reasons}');
        expect(
          [for (final reason in risk.reasons) reason.code]..sort(),
          [...(testCase['reasons'] as List).cast<String>()]..sort(),
        );
      });
    }
  });

  test('registrable domains', () {
    expect(registrableDomain('example.com'), 'example.com');
    expect(registrableDomain('a.b.example.com'), 'example.com');
    expect(registrableDomain('evil.example.co.uk'), 'example.co.uk');
  });

  test('the server\'s risk object is read, unknown reasons are dropped', () {
    final risk = LinkRisk.fromJson({
      'level': 'high',
      'reasons': ['short_link', 'redirects_risky', 'something_new'],
    });
    expect(risk.level, LinkRiskLevel.high);
    expect(risk.reasons, [
      LinkRiskReason.shortLink,
      LinkRiskReason.redirectsRisky,
    ]);
    expect(LinkRisk.fromJson(null).level, LinkRiskLevel.none);
    expect(LinkRisk.fromJson({'level': 'bogus'}).level, LinkRiskLevel.none);
  });

  test('worst keeps the higher level', () {
    const caution = LinkRisk(level: LinkRiskLevel.caution);
    const high = LinkRisk(level: LinkRiskLevel.high);
    expect(caution.worst(high), high);
    expect(high.worst(caution), high);
    expect(LinkRisk.none.worst(caution), caution);
  });

  test('a unicode host counts as an unusual one', () {
    expect(
      assessLink('https://аpple.com/').reasons,
      contains(LinkRiskReason.punycode),
    );
  });

  test('www is not shown', () {
    expect(displayHost(Uri.parse('https://www.Example.com/a')), 'example.com');
  });
}
