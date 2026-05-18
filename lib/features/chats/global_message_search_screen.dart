import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/message.dart';

class GlobalMessageSearchScreen extends ConsumerStatefulWidget {
  const GlobalMessageSearchScreen({super.key});

  static const path = '/search/messages';

  @override
  ConsumerState<GlobalMessageSearchScreen> createState() =>
      _GlobalMessageSearchScreenState();
}

class _GlobalMessageSearchScreenState
    extends ConsumerState<GlobalMessageSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _query = '';
  var _generation = 0;
  var _isLoading = false;
  Object? _error;
  List<MessageSearchResult>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search messages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search messages',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _scheduleSearch,
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final normalizedQuery = _query.trim();
    if (normalizedQuery.isEmpty) {
      return const Center(child: Text('Search across all conversations'));
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final results = _results ?? const <MessageSearchResult>[];
    if (results.isEmpty) {
      return const Center(child: Text('No matching messages'));
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return _MessageSearchResultTile(result: results[index]);
      },
    );
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    final normalizedQuery = value.trim();
    setState(() {
      _query = value;
      _error = null;
      if (normalizedQuery.isEmpty) {
        _isLoading = false;
        _results = null;
      } else {
        _isLoading = true;
      }
    });
    if (normalizedQuery.isEmpty) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runSearch(normalizedQuery, generation));
    });
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final results = await ref
          .read(chatsRepositoryProvider)
          .searchMessages(query);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _isLoading = false;
        _results = results;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = error;
        _results = null;
      });
    }
  }
}

class _MessageSearchResultTile extends StatelessWidget {
  const _MessageSearchResultTile({required this.result});

  final MessageSearchResult result;

  @override
  Widget build(BuildContext context) {
    final body = result.body.trim().isEmpty ? _typeLabel(result) : result.body;
    return ListTile(
      title: Text(
        result.conversationTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.senderName} · $body',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(_formatSearchTime(result.createdAt)),
        ],
      ),
      onTap: () {
        context.go('${ChatsScreen.path}/${result.conversationId}');
      },
    );
  }

  String _typeLabel(MessageSearchResult result) {
    return switch (result.type) {
      MessageType.image => '[Image]',
      MessageType.voice => '[Voice]',
      MessageType.file => '[File]',
      MessageType.text => '',
    };
  }
}

String _formatSearchTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
