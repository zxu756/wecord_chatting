import 'package:flutter/material.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// Home: direct messages and friends. Wide layouts show the Friends page
/// beside the shell's Home sidebar; phones show the rail and the sidebar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const path = '/home';

  @override
  Widget build(BuildContext context) {
    if (isWideLayout(MediaQuery.sizeOf(context).width)) {
      return const ContactsScreen();
    }
    return const Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleRail(homeSelected: true),
            Expanded(child: HomeSidebar(width: null)),
          ],
        ),
      ),
    );
  }
}
