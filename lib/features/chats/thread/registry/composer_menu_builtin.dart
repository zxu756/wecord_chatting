// The "+" menu's own entries, in the order the menu has always had them:
// 100 Photos and videos, 200 Files, 300 Create poll, 400 Chain, 500 Contact
// card, 600 Location, 700 Share live location, 800 Schedule message,
// 900 Insert time, 1000 Events, 1100 Wallpaper, 1200 Send sticker, 1300 Send
// GIF.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The built-in contributions, in menu order.
final List<ComposerMenuContribution> builtInComposerMenu = [
  ComposerMenuContribution(
    id: 'photos-and-videos',
    order: 100,
    build: (ctx) => GlassMenuEntry(
      icon: Icons.image_outlined,
      label: tr('Photos and videos'),
      onSelected: () => unawaited(ctx.actions.pickPhotosAndVideos()),
    ),
  ),
  ComposerMenuContribution(
    id: 'files',
    order: 200,
    build: (ctx) => GlassMenuEntry(
      icon: Icons.attach_file_rounded,
      label: tr('Files'),
      onSelected: () => unawaited(ctx.actions.pickFiles()),
    ),
  ),
  ComposerMenuContribution(
    id: 'poll',
    order: 300,
    build: (ctx) => GlassMenuEntry(
      icon: Icons.poll_outlined,
      label: tr('Create poll'),
      onSelected: () => unawaited(ctx.actions.createPoll()),
    ),
  ),
  ComposerMenuContribution(
    id: 'chain',
    order: 400,
    // Group chains (接龙) are not for direct chats.
    build: (ctx) => ctx.isDirect
        ? null
        : GlassMenuEntry(
            key: const ValueKey('composer-chain-entry'),
            icon: Icons.format_list_numbered_rounded,
            label: tr('Chain'),
            onSelected: () => unawaited(ctx.actions.createChain()),
          ),
  ),
  ComposerMenuContribution(
    id: 'contact-card',
    order: 500,
    build: (ctx) => GlassMenuEntry(
      key: const ValueKey('composer-contact-card-entry'),
      icon: Icons.contact_page_outlined,
      label: tr('Contact card'),
      onSelected: () => unawaited(ctx.actions.sendContactCard()),
    ),
  ),
  ComposerMenuContribution(
    id: 'location',
    order: 600,
    build: (ctx) => GlassMenuEntry(
      key: const ValueKey('composer-location-entry'),
      icon: Icons.location_on_outlined,
      label: tr('Location'),
      onSelected: () => unawaited(ctx.actions.sendLocation()),
    ),
  ),
  ComposerMenuContribution(
    id: 'live-location',
    order: 700,
    // Live location only where the chat can share it.
    build: (ctx) => ctx.isDirect || ctx.isGroup
        ? GlassMenuEntry(
            key: const ValueKey('composer-live-location-entry'),
            icon: Icons.near_me_outlined,
            label: tr('Share live location'),
            onSelected: () => unawaited(ctx.actions.shareLiveLocation()),
          )
        : null,
  ),
  ComposerMenuContribution(
    id: 'schedule',
    order: 800,
    build: (ctx) => GlassMenuEntry(
      key: const ValueKey('composer-schedule-entry'),
      icon: Icons.schedule_send_outlined,
      label: tr('Schedule message'),
      onSelected: () => unawaited(ctx.actions.scheduleMessage()),
    ),
  ),
  ComposerMenuContribution(
    id: 'insert-time',
    order: 900,
    build: (ctx) => GlassMenuEntry(
      icon: Icons.schedule_rounded,
      label: tr('Insert time'),
      onSelected: () => unawaited(ctx.actions.insertTime()),
    ),
  ),
  ComposerMenuContribution(
    id: 'events',
    order: 1000,
    build: (ctx) => ctx.isDirect || ctx.isGroup
        ? GlassMenuEntry(
            icon: Icons.event_outlined,
            label: tr('Events'),
            onSelected: () => unawaited(ctx.actions.showEvents()),
          )
        : null,
  ),
  ComposerMenuContribution(
    id: 'wallpaper',
    order: 1100,
    // Wider screens have the wallpaper in the header's More menu.
    build: (ctx) => ctx.compact
        ? null
        : GlassMenuEntry(
            key: const ValueKey('composer-wallpaper-entry'),
            icon: Icons.wallpaper_outlined,
            label: tr('Wallpaper'),
            onSelected: ctx.actions.changeWallpaper,
          ),
  ),
  ComposerMenuContribution(
    id: 'sticker',
    order: 1200,
    build: (ctx) => GlassMenuEntry(
      icon: Icons.sticky_note_2_outlined,
      label: tr('Send sticker'),
      onSelected: () => unawaited(ctx.actions.pickSticker()),
    ),
  ),
  ComposerMenuContribution(
    id: 'gif',
    order: 1300,
    // Wider screens have a GIF button of their own.
    build: (ctx) => ctx.compact
        ? GlassMenuEntry(
            icon: Icons.gif_box_outlined,
            label: tr('Send GIF'),
            onSelected: ctx.gifAvailable
                ? () => unawaited(ctx.actions.pickGif())
                : null,
          )
        : null,
  ),
];
