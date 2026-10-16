import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/announcement_repository.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Creates a channel: its name, kind (text, voice, forum or stage), an
/// announcement switch for text channels, and a category. Shown with
/// [showCircleChannelPanel]: a sheet on phones, a panel on wide screens.
class CircleChannelCreationSheet extends ConsumerStatefulWidget {
  const CircleChannelCreationSheet({
    required this.circleId,
    this.categories = const [],
    this.initialCategoryId,
    super.key,
  });

  final String circleId;

  /// Offered in a category picker when not empty.
  final List<CircleChannelCategory> categories;
  final String? initialCategoryId;

  @override
  ConsumerState<CircleChannelCreationSheet> createState() =>
      _CircleChannelCreationSheetState();
}

class _CircleChannelCreationSheetState
    extends ConsumerState<CircleChannelCreationSheet> {
  final _nameController = TextEditingController();
  late String? _categoryId =
      widget.categories.any(
        (category) => category.id == widget.initialCategoryId,
      )
      ? widget.initialCategoryId
      : null;
  var _kind = CircleChannelKind.text;

  /// A text channel created as an announcement channel.
  var _announcement = false;
  var _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = circleWideLayout(context);
    final kinds = [
      (
        CircleChannelKind.text,
        Icons.tag,
        tr('Text'),
        tr('Members chat in one stream of messages.'),
      ),
      (
        CircleChannelKind.voice,
        Icons.volume_up_outlined,
        tr('Voice'),
        tr('Members talk, turn on video and share screens.'),
      ),
      (
        CircleChannelKind.forum,
        Icons.forum_outlined,
        tr('Forum'),
        tr('Members start posts, each with its own replies.'),
      ),
      (
        CircleChannelKind.stage,
        Icons.podcasts,
        tr('Stage'),
        tr(
          'A few speakers talk while everyone else listens and can '
          'raise a hand to speak.',
        ),
      ),
    ];

    final form = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 24 : 16,
        wide ? 8 : 0,
        wide ? 24 : 16,
        4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            controller: _nameController,
            autofocus: true,
            enabled: !_isSaving,
            maxLength: CircleChannel.maxNameLength,
            label: tr('Channel name'),
            hint: switch (_kind) {
              CircleChannelKind.voice ||
              CircleChannelKind.stage => tr('Lounge'),
              _ => tr('new-channel'),
            },
            prefixIcon: _kindIcon(_kind),
            onSubmitted: (_) => _createChannel(),
          ),
          SettingsSectionHeader(tr('Type')),
          SettingsGroup(
            key: const ValueKey('channel-kind-selector'),
            color: c.well,
            children: [
              for (final (kind, icon, label, description) in kinds)
                _KindRow(
                  icon: icon,
                  label: label,
                  description: description,
                  selected: _kind == kind,
                  onTap: _isSaving ? null : () => setState(() => _kind = kind),
                ),
            ],
          ),
          if (_kind == CircleChannelKind.text) ...[
            const SizedBox(height: 12),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow.toggle(
                  key: const ValueKey('channel-announcement-switch'),
                  icon: Icons.campaign_outlined,
                  tone: SettingsTone.warning,
                  title: tr('Announcement channel'),
                  subtitle: tr(
                    'Posts here can be published to channels that follow it.',
                  ),
                  value: _announcement,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _announcement = value),
                ),
              ],
            ),
          ],
          if (widget.categories.isNotEmpty) ...[
            SettingsSectionHeader(tr('Category')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WeCordChip(
                  label: tr('No category'),
                  selected: _categoryId == null,
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _categoryId = null),
                ),
                for (final category in widget.categories)
                  WeCordChip(
                    key: ValueKey('channel-category-${category.id}'),
                    label: _short(category.name),
                    selected: _categoryId == category.id,
                    onPressed: _isSaving
                        ? null
                        : () => setState(() => _categoryId = category.id),
                  ),
              ],
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
          ],
        ],
      ),
    );

    // The button stays in reach below the scrolling choices.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: form),
        Padding(
          padding: EdgeInsets.fromLTRB(
            wide ? 24 : 16,
            12,
            wide ? 24 : 16,
            circleChannelPanelBottom(context),
          ),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: WeCordButton(
              label: tr('Create'),
              icon: Icons.add_rounded,
              expand: !wide,
              size: wide ? WeCordButtonSize.medium : WeCordButtonSize.large,
              loading: _isSaving,
              onPressed: _createChannel,
            ),
          ),
        ),
      ],
    );
  }

  /// Long category names are shortened to fit a chip.
  static String _short(String name) {
    final characters = name.characters;
    return characters.length <= 18
        ? name
        : '${characters.take(17).toString().trimRight()}…';
  }

  static IconData _kindIcon(CircleChannelKind kind) => switch (kind) {
    CircleChannelKind.forum => Icons.forum_outlined,
    CircleChannelKind.voice => Icons.volume_up_outlined,
    CircleChannelKind.stage => Icons.podcasts,
    CircleChannelKind.text => Icons.tag,
    CircleChannelKind.announcement => Icons.campaign_outlined,
  };

  Future<void> _createChannel() async {
    if (_isSaving) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = tr('Channel name is required.'));
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final channelId = await ref
          .read(circlesRepositoryProvider)
          .createChannel(
            circleId: widget.circleId,
            name: name,
            categoryId: _categoryId,
            kind: _kind,
          );
      if (_kind == CircleChannelKind.text && _announcement) {
        await ref
            .read(announcementRepositoryProvider)
            .setAnnouncementChannel(channelId: channelId, enabled: true);
      }
      ref.invalidate(circleDetailProvider(widget.circleId));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not create channel. Try again. {error}', {
          'error': error,
        });
      });
    }
  }
}

/// One channel kind to pick: icon tile, name, what it is for, and a round
/// check when chosen.
class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      selected: selected,
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: c.ink.withValues(alpha: hovered ? 0.04 : 0),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              SettingsIconTile(
                icon: icon,
                tone: selected ? SettingsTone.accent : SettingsTone.neutral,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.accent : c.accent.withValues(alpha: 0),
                  border: selected
                      ? null
                      : Border.all(color: c.track, width: 2),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 15, color: c.onAccent)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
