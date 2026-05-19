import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';

final chatMediaProvider = FutureProvider.autoDispose
    .family<List<ConversationMediaItem>, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .listConversationMedia(conversationId);
    });

class ChatMediaScreen extends ConsumerWidget {
  const ChatMediaScreen({required this.conversationId, super.key});

  static String pathFor(String conversationId) =>
      '/chats/$conversationId/media';

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(chatMediaProvider(conversationId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Images'),
              Tab(text: 'Voice'),
              Tab(text: 'Files'),
            ],
          ),
        ),
        body: media.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (items) => TabBarView(
            children: [
              _MediaList(
                items: _filter(items, MessageType.image),
                emptyText: 'No images yet',
              ),
              _MediaList(
                items: _filter(items, MessageType.voice),
                emptyText: 'No voice messages yet',
              ),
              _MediaList(
                items: _filter(items, MessageType.file),
                emptyText: 'No files yet',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaList extends StatelessWidget {
  const _MediaList({required this.items, required this.emptyText});

  final List<ConversationMediaItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _MediaTile(item: items[index]),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.item});

  final ConversationMediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: _MediaLeading(item: item),
      title: Text(_titleFor(item)),
      subtitle: Text(
        '${item.senderName} · ${_formatMediaTime(item.createdAt)}',
      ),
    );
  }
}

class _MediaLeading extends ConsumerWidget {
  const _MediaLeading({required this.item});

  final ConversationMediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = item.imageAttachment;
    if (image != null) {
      return SizedBox.square(
        dimension: 44,
        child: FutureBuilder<String>(
          future: ref.watch(chatsRepositoryProvider).createImageUrl(image),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                snapshot.data!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.image_outlined);
                },
              ),
            );
          },
        ),
      );
    }
    return Icon(switch (item.type) {
      MessageType.voice => Icons.mic_none_outlined,
      MessageType.file => Icons.insert_drive_file_outlined,
      MessageType.image => Icons.image_outlined,
      MessageType.text => Icons.chat_bubble_outline,
    });
  }
}

List<ConversationMediaItem> _filter(
  List<ConversationMediaItem> items,
  MessageType type,
) {
  return items.where((item) => item.type == type).toList(growable: false);
}

String _titleFor(ConversationMediaItem item) {
  final body = item.body.trim();
  if (body.isNotEmpty) {
    return body;
  }
  return switch (item.type) {
    MessageType.image => '[Image]',
    MessageType.voice => '[Voice]',
    MessageType.file => '[File]',
    MessageType.text => item.body,
  };
}

String _formatMediaTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}
