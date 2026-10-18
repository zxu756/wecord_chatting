import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  test('English shows the message without the exception wrapper', () {
    expect(errorText(StateError('Profile not found.')), 'Profile not found.');
    expect(errorText(Exception('No luck')), 'No luck');
    expect(
      errorText(const PostgrestException(message: 'Banned from this circle')),
      'Banned from this circle',
    );
  });

  test('Chinese translates what the server says', () {
    AppStrings.isChinese = true;
    expect(
      errorText(const PostgrestException(message: 'Banned from this circle')),
      '你已被这个圈子封禁',
    );
    expect(
      errorText(const AuthException('Invalid login credentials')),
      isNot('Invalid login credentials'),
    );
  });

  test('Chinese never shows an unknown database message in English', () {
    AppStrings.isChinese = true;
    expect(
      errorText(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint "x"',
          code: '23505',
        ),
      ),
      '出了点问题，请重试。',
    );
  });

  test('a slow or lost connection reads as one thing', () {
    AppStrings.isChinese = true;
    expect(errorText(TimeoutException('slow')), '请检查网络连接后重试。');
  });
}
