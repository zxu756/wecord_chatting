// The header's own actions, in the order the More menu has always had them:
// 100 Search, 200 voice call, 300 video call, 400 Pinned messages, 500 Notes,
// 600 Lists (phones), 700 Disappearing messages, 800 Wallpaper, 900 Media,
// 1000 Group details, 1100 Archive, 1200 Summarize; the parent's own extra
// actions come at 1500; 2000 Events.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The built-in contributions, in header order.
final List<HeaderActionContribution> builtInHeaderActions = [
  // Search comes first: phones keep it next to the primary action.
  HeaderActionContribution(
    id: 'search',
    order: 100,
    build: (ctx) => ChatThreadAction(
      id: 'search',
      tooltip: tr('Search messages'),
      icon: Icons.search,
      onPressed: ctx.host.toggleMessageSearch,
    ),
  ),
  HeaderActionContribution(
    id: 'call',
    order: 200,
    build: (ctx) => ctx.canCall
        ? ChatThreadAction(
            id: 'call',
            tooltip: tr('Start voice call'),
            icon: Icons.call_outlined,
            primary: true,
            onPressed: () => startDirectCall(
              ctx.context,
              ctx.ref,
              conversationId: ctx.conversationId,
              name: ctx.title,
            ),
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'video-call',
    order: 300,
    build: (ctx) => ctx.canCall
        ? ChatThreadAction(
            id: 'video-call',
            tooltip: tr('Start video call'),
            icon: Icons.videocam_outlined,
            primary: true,
            onPressed: () => startDirectCall(
              ctx.context,
              ctx.ref,
              conversationId: ctx.conversationId,
              name: ctx.title,
              video: true,
            ),
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'pinned',
    order: 400,
    build: (ctx) => ChatThreadAction(
      id: 'pinned',
      tooltip: tr('Pinned messages'),
      icon: Icons.push_pin_outlined,
      // Pins are what a channel's header is for; elsewhere they are in More.
      primary: ctx.isChannel,
      onPressed: () => ctx.host.showPinnedMessages(ctx.canPinMessages),
    ),
  ),
  HeaderActionContribution(
    id: 'notes',
    order: 500,
    build: (ctx) => ChatThreadAction(
      id: 'notes',
      tooltip: ctx.desktopChrome ? tr('Notes and lists') : tr('Notes'),
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
      isSelected: ctx.workspaceOpen,
      onPressed: () => openWorkspace(
        ctx.context,
        conversationId: ctx.conversationId,
        tab: ctx.workspaceRequest?.tab ?? WorkspaceTab.notes,
        title: ctx.title,
      ),
    ),
  ),
  HeaderActionContribution(
    id: 'lists',
    order: 600,
    // The desktop panel has both tabs, so it needs only the one button.
    build: (ctx) => ctx.desktopChrome
        ? null
        : ChatThreadAction(
            id: 'lists',
            tooltip: tr('Lists'),
            icon: Icons.checklist_rounded,
            isSelected:
                ctx.workspaceOpen &&
                ctx.workspaceRequest?.tab == WorkspaceTab.lists,
            onPressed: () => openWorkspace(
              ctx.context,
              conversationId: ctx.conversationId,
              tab: WorkspaceTab.lists,
              title: ctx.title,
            ),
          ),
  ),
  HeaderActionContribution(
    id: 'disappearing',
    order: 700,
    build: (ctx) => ctx.isDirectOrGroup
        ? ChatThreadAction(
            id: 'disappearing',
            tooltip: tr('Disappearing messages'),
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer_rounded,
            isSelected: ctx.disappearingSeconds != null,
            menuOnly: true,
            onPressed: ctx.host.openDisappearing,
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'wallpaper',
    order: 800,
    // Wallpapers are personal: this one is only for this chat, only for you.
    build: (ctx) => ChatThreadAction(
      id: 'wallpaper',
      tooltip: tr('Wallpaper'),
      icon: Icons.wallpaper_outlined,
      selectedIcon: Icons.wallpaper_rounded,
      isSelected: ctx.ref.watch(
        wallpapersProvider.select(
          (state) => state.settings.hasOwn(ctx.conversationId),
        ),
      ),
      menuOnly: true,
      onPressed: ctx.host.openWallpaper,
    ),
  ),
  HeaderActionContribution(
    id: 'media',
    order: 900,
    build: (ctx) => ChatThreadAction(
      id: 'media',
      tooltip: tr('Media'),
      icon: Icons.photo_library_outlined,
      onPressed: () {
        ctx.context.push(ChatMediaScreen.pathFor(ctx.conversationId));
      },
    ),
  ),
  HeaderActionContribution(
    id: 'group-details',
    order: 1000,
    build: (ctx) => ctx.isGroup
        ? ChatThreadAction(
            id: 'group-details',
            tooltip: tr('Group details'),
            icon: Icons.group_outlined,
            primary: true,
            onPressed: () => ctx.host.showGroupDetails(ctx.title),
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'archive',
    order: 1100,
    build: (ctx) => ctx.canManageThread
        ? ChatThreadAction(
            id: 'archive',
            tooltip: switch ((ctx.threadArchived, ctx.forumPost)) {
              (true, true) => tr('Unarchive post'),
              (true, false) => tr('Unarchive thread'),
              (false, true) => tr('Archive post'),
              (false, false) => tr('Archive thread'),
            },
            icon: ctx.threadArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            onPressed: () =>
                ctx.host.setThreadArchived(ctx.threadId!, !ctx.threadArchived),
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'summarize',
    order: 1200,
    build: (ctx) => ctx.ref.watch(aiAvailableProvider(ctx.circleId))
        ? ChatThreadAction(
            id: 'summarize',
            tooltip: tr('Summarize'),
            icon: Icons.auto_awesome_outlined,
            onPressed: ctx.host.requestSummary,
          )
        : null,
  ),
  HeaderActionContribution(
    id: 'events',
    order: 2000,
    // Group chats and direct messages can plan events (circles have their
    // own).
    build: (ctx) => ctx.canCall
        ? ChatThreadAction(
            id: 'events',
            tooltip: tr('Events'),
            icon: Icons.event_outlined,
            onPressed: () => showChatEventsList(
              ctx.context,
              conversationId: ctx.conversationId,
              canCreate: ctx.canSend,
            ),
          )
        : null,
  ),
];
