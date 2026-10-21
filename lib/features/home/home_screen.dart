import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// Home: direct messages and friends. Wide layouts show the Friends page
/// beside the shell's Home sidebar; phones show the rail and the messages
/// panel edge to edge, with the floating user panel.
///
/// With Care mode's simple home the rail is not there: only Messages,
/// Friends and Moments.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const path = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isWideLayout(MediaQuery.sizeOf(context).width)) {
      return const ContactsScreen();
    }
    return Scaffold(
      // The frame makes room for the keyboard itself.
      resizeToAvoidBottomInset: false,
      body: PhoneHomeFrame(
        homeSelected: true,
        showRail: !ref.watch(careModeProvider.select((s) => s.simplifies)),
        panelBuilder: (context, bottomInset) =>
            PhoneMessagesPanel(bottomInset: bottomInset),
      ),
    );
  }
}
