import 'package:flutter/material.dart';

class CirclesScreen extends StatelessWidget {
  const CirclesScreen({super.key});

  static const path = '/circles';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circles')),
      body: const Center(child: Text('No circles yet')),
    );
  }
}
