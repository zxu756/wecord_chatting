import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/group.dart';

final groupDetailProvider = FutureProvider.autoDispose
    .family<GroupDetail, String>((ref, conversationId) {
      return ref.watch(chatsRepositoryProvider).getGroupDetail(conversationId);
    });

class GroupDetailSheet extends ConsumerWidget {
  const GroupDetailSheet({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(groupDetailProvider(conversationId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: detail.when(
          loading: () => const _LoadingDetail(),
          error: (error, stackTrace) => _DetailBody(
            title: title.trim().isEmpty ? conversationId : title.trim(),
            members: const [],
            errorText: error.toString(),
          ),
          data: (detail) {
            final displayTitle = detail.title.trim().isNotEmpty
                ? detail.title.trim()
                : title.trim().isNotEmpty
                ? title.trim()
                : conversationId;
            return _DetailBody(title: displayTitle, members: detail.members);
          },
        ),
      ),
    );
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.title,
    required this.members,
    this.errorText,
  });

  final String title;
  final List<GroupMember> members;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group members', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rename'),
            ),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add members'),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (members.isEmpty)
          const Text('No member details available.')
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final member in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.profile.displayName),
                    subtitle: Text('@${member.profile.username}'),
                    trailing: Text(member.role),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
