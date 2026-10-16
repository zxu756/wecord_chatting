import 'package:flutter/material.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/phone_home.dart';
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// Home: direct messages and friends. Wide layouts show the Friends page
/// beside the shell's Home sidebar; phones show the rail and the messages
/// panel edge to edge, with the floating user panel.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const path = '/home';

  @override
  Widget build(BuildContext context) {
    if (isWideLayout(MediaQuery.sizeOf(context).width)) {
      return const ContactsScreen();
    }
    return Scaffold(
      // The frame makes room for the keyboard itself.
      resizeToAvoidBottomInset: false,
      body: PhoneHomeFrame(
        homeSelected: true,
        panelBuilder: (context, bottomInset) =>
            PhoneMessagesPanel(bottomInset: bottomInset),
      ),
    );
  }
}
