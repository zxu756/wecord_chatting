import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circles_repository.dart';

class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  static const path = '/circles';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circles')),
      body: FutureBuilder<List<CircleSummary>>(
        future: ref.watch(circlesRepositoryProvider).listCircles(),
        builder: (context, snapshot) {
          final circles = snapshot.data ?? const <CircleSummary>[];
          if (circles.isEmpty) {
            return _EmptyCircles(
              onCreate: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Circle creation is coming next'),
                  content: const Text(
                    'Text channels, announcements, and invited members will live here.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final circle in circles)
                ListTile(
                  title: Text(circle.name),
                  subtitle: Text('${circle.memberCount} members'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyCircles extends StatelessWidget {
  const _EmptyCircles({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_2_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Private spaces for familiar groups',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Start with invite-only circles, then add channels and announcements.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onCreate,
                child: const Text('Create Circle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
