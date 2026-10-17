import 'package:flutter/material.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A round check mark: filled accent when [checked], an empty ring when not.
class CheckCircle extends StatelessWidget {
  const CheckCircle({required this.checked, this.size = 24, super.key});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AnimatedContainer(
      duration: WeCordMotion.quick,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? c.accent : Colors.transparent,
        border: Border.all(color: checked ? c.accent : c.faint, width: 1.6),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: size * 0.66, color: c.onAccent)
          : null,
    );
  }
}

/// A searchable list of friends, each with a [CheckCircle]. The selection
/// lives with the caller ([selected], [onToggle]).
class FriendCheckList extends StatefulWidget {
  const FriendCheckList({
    required this.friends,
    required this.selected,
    required this.onToggle,
    this.showSearch = true,
    this.emptyText,
    this.keyPrefix = 'friend-check',
    super.key,
  });

  final List<Profile> friends;
  final Set<String> selected;
  final ValueChanged<Profile> onToggle;
  final bool showSearch;

  /// Shown instead of the list when there are no friends at all.
  final String? emptyText;
  final String keyPrefix;

  @override
  State<FriendCheckList> createState() => _FriendCheckListState();
}

class _FriendCheckListState extends State<FriendCheckList> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final query = _query.trim().toLowerCase();
    final matching = query.isEmpty
        ? widget.friends
        : [
            for (final friend in widget.friends)
              if (friend.displayLabel.toLowerCase().contains(query) ||
                  friend.username.toLowerCase().contains(query))
                friend,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSearch && widget.friends.length > 6) ...[
          WeCordTextField(
            fieldKey: ValueKey('${widget.keyPrefix}-search'),
            hint: tr('Search friends'),
            prefixIcon: Icons.search_rounded,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            child: Text(
              widget.emptyText ?? tr('No friends yet.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          )
        else if (matching.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            child: Text(
              tr('No matching friends.'),
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.xl),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, friend) in matching.indexed) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 62,
                      color: c.lineSoft,
                    ),
                  _FriendCheckRow(
                    key: ValueKey('${widget.keyPrefix}-${friend.id}'),
                    friend: friend,
                    checked: widget.selected.contains(friend.id),
                    onPressed: () => widget.onToggle(friend),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FriendCheckRow extends StatelessWidget {
  const _FriendCheckRow({
    required this.friend,
    required this.checked,
    required this.onPressed,
    super.key,
  });

  final Profile friend;
  final bool checked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: () {
        WeCordHaptics.selection();
        onPressed();
      },
      selected: checked,
      semanticLabel: friend.displayLabel,
      excludeSemantics: true,
      pressedScale: 1,
      shape: const RoundedRectangleBorder(),
      builder: (context, states) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return Container(
          constraints: const BoxConstraints(minHeight: 56),
          color: c.ink.withValues(alpha: highlighted ? 0.04 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              ProfileAvatar(
                name: friend.displayLabel,
                avatarUrl: friend.avatarUrl,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  friend.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CheckCircle(checked: checked),
            ],
          ),
        );
      },
    );
  }
}
