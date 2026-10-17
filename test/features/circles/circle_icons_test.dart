import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_ui.dart';

void main() {
  test('Roles, AutoMod and AI guard each have an icon of their own, and none '
      'is a plain shield', () {
    final icons = {CircleIcons.roles, CircleIcons.autoMod, CircleIcons.aiGuard};
    expect(icons, hasLength(3));
    expect(icons, isNot(contains(Icons.shield_outlined)));
    expect(icons, isNot(contains(Icons.gpp_maybe_outlined)));
  });
}
