// What the chat page's menus leave out while Care mode's simple home is on:
// the entries few people reach for, so the ones elders use stand out. Each
// registry of the chat page (message menu, header, "+" menu) drops these ids
// and nothing else; the entries come back when the option or Care mode is
// turned off.

/// Message menu entries that Care mode hides (`message_actions_builtin.dart`
/// and the features' own).
const careHiddenMessageActionIds = <String>{
  'create-task',
  'pin',
  'thread',
  'remind',
  'select',
  'publish',
  'remove-embed',
  'ask-wecord-ai',
  'ai-make-tasks',
  'quote-reply',
  'add-to-stickers',
  'urgent',
  'edit-history',
  'message-info',
};

/// Header actions (the More menu on phones) that Care mode hides.
const careHiddenHeaderActionIds = <String>{
  'notes',
  'lists',
  'disappearing',
  'wallpaper',
  'summarize',
  'events',
  'auto-translate',
  'group-tabs',
};

/// "+" menu entries that Care mode hides. Photos, files, contact cards,
/// location, stickers and GIFs stay.
const careHiddenComposerMenuIds = <String>{
  'poll',
  'chain',
  'live-location',
  'schedule',
  'insert-time',
  'events',
  'wallpaper',
  'form',
  'ask-wecord-ai',
  'send-silently',
  'check-in',
};
