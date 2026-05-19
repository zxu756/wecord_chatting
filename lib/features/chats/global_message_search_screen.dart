import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/shared/models/discovery.dart';

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
  List<DiscoveryResult>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search WeCord',
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
      return const Center(child: Text('Search messages, groups, and Circles'));
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
    final results = _results ?? const <DiscoveryResult>[];
    if (results.isEmpty) {
      return const Center(child: Text('No matching results'));
    }
    final grouped = _groupResults(results);
    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final result in entry.value)
            _DiscoveryResultTile(result: result),
        ],
      ],
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
          .searchDiscovery(query);
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

class _DiscoveryResultTile extends StatelessWidget {
  const _DiscoveryResultTile({required this.result});

  final DiscoveryResult result;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(result.type)),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: result.subtitle == null
          ? null
          : Text(
              result.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () => _openResult(context, result),
    );
  }
}

Map<String, List<DiscoveryResult>> _groupResults(
  List<DiscoveryResult> results,
) {
  final grouped = <String, List<DiscoveryResult>>{};
  for (final result in results) {
    final title = _sectionTitle(result.type);
    grouped.putIfAbsent(title, () => <DiscoveryResult>[]).add(result);
  }
  return grouped;
}

String _sectionTitle(DiscoveryResultType type) {
  return switch (type) {
    DiscoveryResultType.contact => 'Contacts',
    DiscoveryResultType.group => 'Groups',
    DiscoveryResultType.circle => 'Circles',
    DiscoveryResultType.circleChannel => 'Channels',
    DiscoveryResultType.message => 'Messages',
  };
}

IconData _iconFor(DiscoveryResultType type) {
  return switch (type) {
    DiscoveryResultType.contact => Icons.person_outline,
    DiscoveryResultType.group => Icons.group_outlined,
    DiscoveryResultType.circle => Icons.bubble_chart_outlined,
    DiscoveryResultType.circleChannel => Icons.tag,
    DiscoveryResultType.message => Icons.chat_bubble_outline,
  };
}

void _openResult(BuildContext context, DiscoveryResult result) {
  switch (result.type) {
    case DiscoveryResultType.circle:
      final circleId = result.circleId ?? result.id;
      context.go('${CirclesScreen.path}/$circleId');
    case DiscoveryResultType.circleChannel:
    case DiscoveryResultType.group:
    case DiscoveryResultType.contact:
    case DiscoveryResultType.message:
      final conversationId = result.conversationId;
      if (conversationId != null) {
        context.go('${ChatsScreen.path}/$conversationId');
      } else if (result.circleId != null) {
        context.go('${CirclesScreen.path}/${result.circleId}');
      }
  }
}
