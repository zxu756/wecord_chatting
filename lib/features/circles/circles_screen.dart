import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/circle.dart';

class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  static const path = '/circles';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circles'),
        actions: [
          IconButton(
            tooltip: 'Join with invite',
            icon: const Icon(Icons.add_link),
            onPressed: () => _joinWithInvite(context),
          ),
        ],
      ),
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

Future<void> _joinWithInvite(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    builder: (context) => const _JoinWithInviteDialog(),
  );
  if (code != null && context.mounted) {
    await context.push(circleInvitePath(code));
  }
}

class _JoinWithInviteDialog extends StatefulWidget {
  const _JoinWithInviteDialog();

  @override
  State<_JoinWithInviteDialog> createState() => _JoinWithInviteDialogState();
}

class _JoinWithInviteDialogState extends State<_JoinWithInviteDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = parseCircleInviteCode(_controller.text);
    if (code == null) {
      setState(() => _errorText = 'Enter an invite code or link');
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join with invite'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Invite code or link',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Join')),
      ],
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
