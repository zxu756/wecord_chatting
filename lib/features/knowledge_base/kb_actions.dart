import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/offline/outbox.dart' show newClientId;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/features/knowledge_base/kb_repository.dart';
import 'package:wecord/features/knowledge_base/kb_sheets.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What went wrong, in words for a person.
String kbErrorMessage(Object error, {String? fallback}) {
  if (error is PostgrestException) {
    if (error.message.contains('higher role')) {
      return tr('A higher role limited this page, so you cannot change it.');
    }
    if (error.code == '42501') {
      return tr('You are not allowed to do that here.');
    }
    if (error.code == '22023') {
      final message = error.message;
      if (message.contains('too many pages')) {
        return tr('There are too many pages here.');
      }
      if (message.contains('5 levels')) {
        return tr('Pages can be nested 5 levels deep.');
      }
    }
  }
  return fallback ?? tr('That did not work. Try again.');
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

void _refresh(WidgetRef ref, String circleId) {
  ref.invalidate(kbPagesProvider(circleId));
}

/// Asks for a title and starts a page below [parent] (null: top level).
/// Returns the new page's id, or null when cancelled or it did not work.
Future<String?> addKbPage(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  KbPage? parent,
}) async {
  final title = await showNewKbPageDialog(context, parentTitle: parent?.title);
  if (title == null || !context.mounted) {
    return null;
  }
  try {
    final id = newClientId();
    final page = await ref
        .read(knowledgeBaseRepositoryProvider)
        .createPage(circleId, parentId: parent?.id, title: title, id: id);
    _refresh(ref, circleId);
    return page.id;
  } on Object catch (error) {
    if (context.mounted) {
      _toast(
        context,
        kbErrorMessage(error, fallback: tr('Could not create the page.')),
      );
    }
    return null;
  }
}

/// Asks where [page] should go and moves it there (last in the new place).
Future<bool> moveKbPageTo(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required KbTree tree,
  required KbPage page,
}) async {
  final choice = await showKbMoveSheet(context, tree: tree, page: page);
  if (choice == null || choice.parentId == page.parentId) {
    return false;
  }
  try {
    await ref
        .read(knowledgeBaseRepositoryProvider)
        .movePage(page.id, parentId: choice.parentId);
    _refresh(ref, circleId);
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      _toast(
        context,
        kbErrorMessage(error, fallback: tr('Could not move the page.')),
      );
    }
    return false;
  }
}

/// Moves [page] one place up ([delta] -1) or down (1) among its siblings.
Future<bool> shiftKbPage(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required KbTree tree,
  required KbPage page,
  required int delta,
}) async {
  final siblings = page.parentId == null
      ? tree.roots
      : tree.childrenOf(page.parentId!);
  final index = siblings.indexWhere((s) => s.id == page.id);
  final target = index + delta;
  if (index < 0 || target < 0 || target >= siblings.length) {
    return false;
  }
  // "Before": the page that takes the place, or the one after it going down.
  final String? before = delta < 0
      ? siblings[target].id
      : (target + 1 < siblings.length ? siblings[target + 1].id : null);
  try {
    await ref
        .read(knowledgeBaseRepositoryProvider)
        .movePage(page.id, parentId: page.parentId, beforeId: before);
    _refresh(ref, circleId);
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      _toast(
        context,
        kbErrorMessage(error, fallback: tr('Could not move the page.')),
      );
    }
    return false;
  }
}

/// Asks, then deletes [page]; the pages inside it move up a level.
Future<bool> deleteKbPage(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required KbTree tree,
  required KbPage page,
}) async {
  final inside = tree.childrenOf(page.id).length;
  final confirmed = await confirmCircleAction(
    context,
    title: tr('Delete this page?'),
    message: inside > 0
        ? tr(
            'It disappears for everyone in the circle, with its history and '
            'pictures. The {count} pages inside it move up one level.',
            {'count': inside},
          )
        : tr(
            'It disappears for everyone in the circle, with its history and '
            'pictures.',
          ),
    confirmLabel: tr('Delete'),
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  try {
    await ref.read(knowledgeBaseRepositoryProvider).deletePage(page.id);
    _refresh(ref, circleId);
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      _toast(
        context,
        kbErrorMessage(error, fallback: tr('Could not delete the page.')),
      );
    }
    return false;
  }
}

/// Shows who may read and edit [page] and saves a change.
Future<bool> editKbAccess(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required KbPage page,
}) async {
  final repository = ref.read(knowledgeBaseRepositoryProvider);
  final KbPageAccess access;
  try {
    access = await repository.getAccess(page.id);
  } on Object catch (error) {
    if (context.mounted) {
      _toast(context, kbErrorMessage(error));
    }
    return false;
  }
  if (!context.mounted) {
    return false;
  }
  final choice = await showKbAccessSheet(
    context,
    pageTitle: page.title,
    access: access,
  );
  if (choice == null) {
    return false;
  }
  try {
    await repository.setAccess(
      page.id,
      viewRoleIds: choice.viewRoleIds,
      editRoleIds: choice.editRoleIds,
    );
    _refresh(ref, circleId);
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      _toast(
        context,
        kbErrorMessage(error, fallback: tr('Could not save the settings.')),
      );
    }
    return false;
  }
}
