import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/saved_cards.dart';
import 'package:wecord/features/later/saved_filters.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/saved_organizer.dart';
import 'package:wecord/features/later/saved_sheets.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

export 'package:wecord/features/later/saved_filters.dart' show SavedFilter;

/// The user's saved entries ("Favorites"): messages, Moments, circle posts,
/// links and their own notes, in folders and with tags. Jump to one, mark it
/// done (and undo that), file it, search, or remove it. Entries whose source
/// was deleted or can no longer be seen say so.
class SavedMessagesScreen extends ConsumerStatefulWidget {
  const SavedMessagesScreen({super.key});

  static const path = '/saved';

  @override
  ConsumerState<SavedMessagesScreen> createState() =>
      _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends ConsumerState<SavedMessagesScreen> {
  var _view = const SavedView();
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  var _searching = false;
  var _searchRun = 0;
  Timer? _debounce;
  String? _busyId;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(savedMessagesProvider)
      ..invalidate(savedFoldersProvider);
    await ref.read(savedMessagesProvider.future);
    if (_query.text.trim().isNotEmpty) {
      unawaited(_search(_query.text));
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(savedMessagesProvider);
      await ref.read(savedMessagesProvider.future);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Something went wrong. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query.clear();
        _debounce?.cancel();
        _searchRun++;
        _view = _view.copyWith(matchIds: null);
      }
    });
    if (_searching) {
      _queryFocus.requestFocus();
    }
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _searchRun++;
      setState(() => _view = _view.copyWith(matchIds: null));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_search(text));
    });
  }

  Future<void> _search(String text) async {
    final run = ++_searchRun;
    try {
      final ids = await ref.read(savedMessagesRepositoryProvider).search(text);
      if (mounted && run == _searchRun) {
        setState(() {
          _error = null;
          _view = _view.copyWith(matchIds: ids);
        });
      }
    } catch (_) {
      if (mounted && run == _searchRun) {
        setState(() => _error = tr('Could not search. Try again.'));
      }
    }
  }

  Future<void> _open(
    SavedMessage item,
    Map<String, ConversationSummary> conversations,
  ) async {
    switch (item.kind) {
      case SavedKind.message:
        final conversationId = item.conversationId;
        if (conversationId == null) {
          return;
        }
        openMessage(
          context,
          ref,
          conversationId: conversationId,
          messageId: item.messageId,
          conversation: conversations[conversationId],
        );
      case SavedKind.moment:
        context.push('${MomentsScreen.path}/${item.messageId}');
      case SavedKind.circlePost:
        context.push('${CircleRoutes.path}/${item.circleId}');
      case SavedKind.link:
        final uri = Uri.tryParse(item.url ?? '');
        if (uri != null) {
          try {
            await ref.read(linkLauncherProvider)(context, uri);
          } catch (_) {
            if (mounted) {
              setState(() => _error = tr('Could not open the link.'));
            }
          }
        }
      case SavedKind.note:
      case SavedKind.text:
        await showSavedItemEditor(context, item);
    }
  }

  Future<void> _remove(SavedMessage item) {
    return _run(
      item.id,
      () => ref
          .read(savedMessagesRepositoryProvider)
          .remove(item.id, images: item.images),
    );
  }

  Future<void> _newFolder() async {
    final name = await promptFolderName(context);
    if (name == null || !mounted) {
      return;
    }
    try {
      final id = await ref
          .read(savedMessagesRepositoryProvider)
          .createFolder(name);
      ref.invalidate(savedFoldersProvider);
      if (mounted) {
        setState(() {
          _error = null;
          _view = _view.copyWith(folderId: id);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
      }
    }
  }

  Future<void> _folderMenu(SavedFolder folder) async {
    final action = await showWeCordSheet<String>(
      context,
      title: folder.name,
      builder: (sheetContext, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              SettingsRow(
                key: const ValueKey('saved-folder-rename'),
                icon: Icons.drive_file_rename_outline_rounded,
                title: tr('Rename'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
              SettingsRow(
                key: const ValueKey('saved-folder-delete'),
                icon: Icons.delete_outline_rounded,
                title: tr('Delete folder'),
                subtitle: tr('What is in it stays in Saved.'),
                destructive: true,
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    final repository = ref.read(savedMessagesRepositoryProvider);
    try {
      if (action == 'rename') {
        final name = await promptFolderName(context, initial: folder.name);
        if (name == null || !mounted || name == folder.name) {
          return;
        }
        await repository.renameFolder(folder.id, name);
      } else {
        await repository.deleteFolder(folder.id);
        if (_view.folderId == folder.id) {
          setState(() => _view = _view.copyWith(folderId: null));
        }
      }
      ref
        ..invalidate(savedFoldersProvider)
        ..invalidate(savedMessagesProvider);
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
      }
    }
  }

  Future<void> _tagMenu(String tag) async {
    final action = await showWeCordSheet<String>(
      context,
      title: '#$tag',
      builder: (sheetContext, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              SettingsRow(
                key: const ValueKey('saved-tag-rename'),
                icon: Icons.drive_file_rename_outline_rounded,
                title: tr('Rename tag'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
              SettingsRow(
                key: const ValueKey('saved-tag-delete'),
                icon: Icons.delete_outline_rounded,
                title: tr('Delete tag'),
                subtitle: tr('It is taken off every entry.'),
                destructive: true,
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    final repository = ref.read(savedMessagesRepositoryProvider);
    try {
      var to = '';
      if (action == 'rename') {
        final name = await promptTagName(context, initial: tag);
        if (name == null || !mounted || name == tag) {
          return;
        }
        to = name;
      }
      await repository.renameTag(tag, to);
      if (_view.tag?.toLowerCase() == tag.toLowerCase()) {
        setState(() => _view = _view.copyWith(tag: to.isEmpty ? null : to));
      }
      ref.invalidate(savedMessagesProvider);
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
      }
    }
  }

  Future<void> _addMenu() async {
    final action = await showWeCordSheet<String>(
      context,
      builder: (sheetContext, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              SettingsRow(
                key: const ValueKey('saved-add-note'),
                icon: Icons.sticky_note_2_outlined,
                title: tr('New note'),
                subtitle: tr('Words or pictures only you can see.'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('note'),
              ),
              SettingsRow(
                key: const ValueKey('saved-add-link'),
                icon: Icons.link_rounded,
                title: tr('Save a link'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('link'),
              ),
              SettingsRow(
                key: const ValueKey('saved-add-folder'),
                icon: Icons.create_new_folder_outlined,
                title: tr('New folder'),
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop('folder'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case 'note':
        await showNewNoteSheet(context);
      case 'link':
        await showSaveLinkSheet(context);
      case 'folder':
        await _newFolder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final saved = ref.watch(savedMessagesProvider);
    final folders = ref.watch(savedFoldersProvider).value ?? const [];
    final folderNames = {for (final folder in folders) folder.id: folder.name};
    final conversations = {
      for (final conversation
          in ref.watch(conversationsProvider).value ??
              const <ConversationSummary>[])
        conversation.id: conversation,
    };
    final circles = {
      for (final circle
          in ref.watch(circleSummariesProvider).value ??
              const <CircleSummary>[])
        circle.id: circle,
    };
    final all = saved.value ?? const <SavedMessage>[];
    final active = all.where((message) => !message.isDone).length;
    final done = all.length - active;
    final shown = filterSaved(all, _view);
    final counts = folderCounts(all);
    final tags = tagCounts(all);
    final searchingNow = _view.matchIds != null;

    Widget statusChip(SavedFilter filter, String label, int count) {
      return WeCordChip(
        key: ValueKey('saved-filter-${filter.name}'),
        label: label,
        count: count == 0 ? null : count,
        onPaper: true,
        selected: _view.status == filter,
        onPressed: () => setState(() => _view = _view.copyWith(status: filter)),
      );
    }

    final Widget body = saved.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Could not load saved messages.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
          ),
        ],
      ),
      data: (_) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('saved-error'),
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ),
            ),
          if (shown.isEmpty)
            _EmptySaved(view: _view, anyEntries: all.isNotEmpty)
          else
            for (final (index, item) in shown.indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              SavedCard(
                item: item,
                place: conversationPlaceLabel(
                  conversations[item.conversationId],
                  circles,
                ),
                folderName: folderNames[item.folderId],
                busy: _busyId == item.id,
                onOpen: () => unawaited(_open(item, conversations)),
                onToggleDone: () => unawaited(
                  _run(
                    item.id,
                    () => ref
                        .read(savedMessagesRepositoryProvider)
                        .setDone(item.id, done: !item.isDone),
                  ),
                ),
                onRemove: () => unawaited(_remove(item)),
                onEdit: () => unawaited(showSavedItemEditor(context, item)),
                onFolder: () => setState(
                  () => _view = _view.copyWith(folderId: item.folderId),
                ),
                onTag: (tag) =>
                    setState(() => _view = _view.copyWith(tag: tag)),
              ),
            ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Saved'),
                  actions: [
                    WeCordIconButton(
                      key: const ValueKey('saved-search-toggle'),
                      icon: _searching
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      tooltip: _searching ? tr('Close search') : tr('Search'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _toggleSearch,
                    ),
                    WeCordIconButton(
                      key: const ValueKey('saved-add'),
                      icon: Icons.add_rounded,
                      tooltip: tr('Add'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: () => unawaited(_addMenu()),
                    ),
                    WeCordIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: tr('Refresh'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _refresh,
                    ),
                  ],
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: WeCordTextField(
                      fieldKey: const ValueKey('saved-search-field'),
                      controller: _query,
                      focusNode: _queryFocus,
                      onPaper: true,
                      hint: tr('Search titles, notes, tags and text'),
                      prefixIcon: Icons.search_rounded,
                      textInputAction: TextInputAction.search,
                      inputFormatters: [LengthLimitingTextInputFormatter(200)],
                      onChanged: _onQueryChanged,
                      onSubmitted: (text) {
                        _debounce?.cancel();
                        if (text.trim().isNotEmpty) {
                          unawaited(_search(text));
                        }
                      },
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      if (!searchingNow) ...[
                        statusChip(SavedFilter.active, tr('Active'), active),
                        const SizedBox(width: 6),
                        statusChip(SavedFilter.done, tr('Done'), done),
                        const SizedBox(width: 14),
                      ],
                      WeCordChip(
                        key: const ValueKey('saved-folder-all'),
                        label: tr('All'),
                        onPaper: true,
                        selected: _view.folderId == null,
                        onPressed: () => setState(
                          () => _view = _view.copyWith(folderId: null),
                        ),
                      ),
                      for (final folder in folders) ...[
                        const SizedBox(width: 6),
                        WeCordChip(
                          key: ValueKey('saved-folder-${folder.id}'),
                          label: folder.name,
                          icon: Icons.folder_outlined,
                          count: counts[folder.id],
                          onPaper: true,
                          selected: _view.folderId == folder.id,
                          hint: tr('Hold for more'),
                          onPressed: () => setState(
                            () => _view = _view.copyWith(
                              folderId: _view.folderId == folder.id
                                  ? null
                                  : folder.id,
                            ),
                          ),
                          onLongPress: () => unawaited(_folderMenu(folder)),
                        ),
                      ],
                      const SizedBox(width: 6),
                      WeCordChip(
                        key: const ValueKey('saved-new-folder'),
                        label: tr('New folder'),
                        icon: Icons.add_rounded,
                        onPaper: true,
                        onPressed: () => unawaited(_newFolder()),
                      ),
                    ],
                  ),
                ),
                if (tags.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        for (final (index, entry) in tags.indexed) ...[
                          if (index > 0) const SizedBox(width: 6),
                          WeCordChip(
                            key: ValueKey('saved-tag-${entry.tag}'),
                            label: '#${entry.tag}',
                            count: entry.count,
                            height: 30,
                            onPaper: true,
                            selected:
                                _view.tag?.toLowerCase() ==
                                entry.tag.toLowerCase(),
                            hint: tr('Hold for more'),
                            onPressed: () => setState(
                              () => _view = _view.copyWith(
                                tag:
                                    _view.tag?.toLowerCase() ==
                                        entry.tag.toLowerCase()
                                    ? null
                                    : entry.tag,
                              ),
                            ),
                            onLongPress: () => unawaited(_tagMenu(entry.tag)),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 8),
                Expanded(
                  child: RefreshIndicator(onRefresh: _refresh, child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySaved extends StatelessWidget {
  const _EmptySaved({required this.view, required this.anyEntries});

  final SavedView view;
  final bool anyEntries;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final active = view.status == SavedFilter.active;
    final narrowed =
        view.folderId != null || view.tag != null || view.matchIds != null;
    final (IconData icon, String title, String message) = view.matchIds != null
        ? (
            Icons.search_off_rounded,
            tr('Nothing found'),
            tr('Try other words, or look in a folder.'),
          )
        : narrowed
        ? (
            Icons.folder_open_rounded,
            tr('Nothing here'),
            active
                ? tr('Nothing in this folder or tag is still to do.')
                : tr('Nothing in this folder or tag is done.'),
          )
        : active
        ? (
            Icons.bookmark_border_rounded,
            tr('Nothing saved yet'),
            tr(
              "Choose Save for later in a message's menu to keep it here. You can keep Moments, posts, links and notes too.",
            ),
          )
        : (
            Icons.check_circle_outline_rounded,
            tr('Nothing done yet'),
            tr('Messages you mark done show up here.'),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          SettingsIconTile(icon: icon, size: 56),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
