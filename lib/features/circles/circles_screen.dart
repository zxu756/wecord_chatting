import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';

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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final circles = snapshot.data ?? const <CircleSummary>[];
          if (circles.isEmpty) {
            return _EmptyCircles(
              onCreate: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => const CircleCreationSheet(),
              ),
            );
          }
          return ListView.separated(
            itemCount: circles.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final circle = circles[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: circle.avatarUrl == null
                      ? null
                      : NetworkImage(circle.avatarUrl!),
                  child: circle.avatarUrl == null
                      ? Text(_initials(circle.name))
                      : null,
                ),
                title: Text(circle.name),
                subtitle: Text(
                  '${circle.memberCount} members · ${circle.channelCount} channels',
                ),
                onTap: () => context.go('${CirclesScreen.path}/${circle.id}'),
              );
            },
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

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}
