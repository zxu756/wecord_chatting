import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_picker.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings -> Appearance -> Chat wallpaper: the default behind the
/// messages of every chat that has no wallpaper of its own. Shows what is
/// chosen and opens the picker.
class ChatWallpaperRow extends ConsumerWidget {
  const ChatWallpaperRow({this.showIcon = true, super.key});

  final bool showIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(
      wallpapersProvider.select(
        (state) =>
            state.settings.defaultWallpaper ?? const ChatWallpaper.none(),
      ),
    );
    return SettingsRow(
      key: const ValueKey('chat-wallpaper-row'),
      icon: showIcon ? Icons.wallpaper_rounded : null,
      title: tr('Chat wallpaper'),
      subtitle: tr('The picture behind the messages. Only you see it.'),
      value: wallpaperLabel(wallpaper),
      onTap: () => showWallpaperPicker(context),
    );
  }
}
