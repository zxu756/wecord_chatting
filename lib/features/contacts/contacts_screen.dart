import 'package:flutter/material.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  static const path = '/contacts';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: const Center(child: Text('No contacts yet')),
    );
  }
}
