import 'package:flutter/material.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  static const path = '/chats';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: const Center(child: Text('No conversations yet')),
    );
  }
}
