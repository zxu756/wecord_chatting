// What a restricted chat (advanced chat privacy, roadmap G6) takes out of the
// chat page's menus. The same rule as Care mode's registry filters
// (care_registry_filters.dart): each registry drops the entries by id, and
// they come back when the chat is open again. The database refuses the real
// thing whatever the app shows; this keeps the app from offering what would
// fail, and from looking as if it kept a secret it cannot keep.
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chats/selection/selection_registry.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';

/// Message menu entries that take a message's words or picture out of the
/// chat, or give them to AI: Copy, Forward, Save for later, Copy text from
/// picture, Add to stickers, Add to album, Save to group files, Translate,
/// Transcribe, Ask WeCord AI and "Make tasks" (AI).
const restrictedHiddenMessageActionIds = <String>{
  'copy',
  'forward',
  'translate',
  'transcribe',
  'save',
  'copy-image-text',
  'add-to-stickers',
  'ask-wecord-ai',
  'ai-make-tasks',
  'add-to-album',
  'save-to-group-files',
};

/// Header actions that hand the chat to AI.
const restrictedHiddenHeaderActionIds = <String>{'summarize', 'auto-translate'};

/// "+" menu entries that hand the chat to AI.
const restrictedHiddenComposerMenuIds = <String>{'ask-wecord-ai'};

/// [contribution], or one that shows nothing while its chat is restricted.
MessageActionContribution hideWhenRestricted(
  MessageActionContribution contribution,
) {
  if (!restrictedHiddenMessageActionIds.contains(contribution.id)) {
    return contribution;
  }
  return MessageActionContribution(
    id: contribution.id,
    order: contribution.order,
    build: (ctx) =>
        ctx.container.read(restrictSharingProvider(ctx.message.conversationId))
        ? const []
        : contribution.build(ctx),
  );
}

/// [contribution], or one that shows nothing while its chat is restricted.
HeaderActionContribution hideHeaderActionWhenRestricted(
  HeaderActionContribution contribution,
) {
  if (!restrictedHiddenHeaderActionIds.contains(contribution.id)) {
    return contribution;
  }
  return HeaderActionContribution(
    id: contribution.id,
    order: contribution.order,
    build: (ctx) => ctx.ref.watch(restrictSharingProvider(ctx.conversationId))
        ? null
        : contribution.build(ctx),
  );
}

/// [contribution], or one that shows nothing while its chat is restricted.
ComposerMenuContribution hideComposerEntryWhenRestricted(
  ComposerMenuContribution contribution,
) {
  if (!restrictedHiddenComposerMenuIds.contains(contribution.id)) {
    return contribution;
  }
  return ComposerMenuContribution(
    id: contribution.id,
    order: contribution.order,
    build: (ctx) =>
        ctx.container.read(restrictSharingProvider(ctx.conversationId))
        ? null
        : contribution.build(ctx),
  );
}

/// The buttons features add to the selection bar read, copy or send the
/// selected messages (to AI), so none of them shows in a restricted chat.
SelectionBarContribution hideSelectionButtonWhenRestricted(
  SelectionBarContribution contribution,
) {
  return SelectionBarContribution(
    id: contribution.id,
    order: contribution.order,
    build: (ctx) =>
        ctx.container.read(
          restrictSharingProvider(ctx.environment.conversationId),
        )
        ? null
        : contribution.build(ctx),
  );
}
