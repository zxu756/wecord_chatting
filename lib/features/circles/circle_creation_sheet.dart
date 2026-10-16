import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_template_widgets.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

class CircleCreationSheet extends ConsumerStatefulWidget {
  const CircleCreationSheet({super.key});

  @override
  ConsumerState<CircleCreationSheet> createState() =>
      _CircleCreationSheetState();
}

class _CircleCreationSheetState extends ConsumerState<CircleCreationSheet> {
  final _nameController = TextEditingController();
  final _selectedFriendIds = <String>{};
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
    final friendsFuture = ref.watch(contactsRepositoryProvider).listFriends();
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: FutureBuilder<List<Profile>>(
            future: friendsFuture,
            builder: (context, snapshot) {
              final friends = snapshot.data ?? const <Profile>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      tr('Create Circle'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('A home for your people: channels, voice and events.'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                  const SizedBox(height: 16),
                  WeCordTextField(
                    controller: _nameController,
                    autofocus: true,
                    label: tr('Circle name'),
                    errorText: _errorText,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isSaving ? null : _createCircle(),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: WeCordButton(
                      key: const ValueKey('use-template-button'),
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      icon: Icons.dashboard_customize_outlined,
                      label: tr('Use a template code'),
                      onPressed: _isSaving ? null : _useTemplate,
                    ),
                  ),
                  if (friends.isNotEmpty) ...[
                    SettingsSectionHeader(tr('Invite friends')),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 248),
                      child: SettingsGroup(
                        color: c.well,
                        children: [
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: [
                                for (final friend in friends)
                                  CircleFriendPickRow(
                                    friend: friend,
                                    selected: _selectedFriendIds.contains(
                                      friend.id,
                                    ),
                                    onChanged: _isSaving
                                        ? null
                                        : (selected) => setState(() {
                                            if (selected) {
                                              _selectedFriendIds.add(friend.id);
                                            } else {
                                              _selectedFriendIds.remove(
                                                friend.id,
                                              );
                                            }
                                          }),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  WeCordButton(
                    label: tr('Create'),
                    expand: true,
                    size: WeCordButtonSize.large,
                    loading: _isSaving,
                    onPressed: _isSaving ? null : _createCircle,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Creates the circle from a template instead, then opens it.
  Future<void> _useTemplate() async {
    final circleId = await showUseCircleTemplateSheet(context);
    if (circleId == null || !mounted) {
      return;
    }
    ref.invalidate(circleSummariesProvider);
    context.pop();
    context.go('/circles/$circleId');
  }

  Future<void> _createCircle() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = tr('Circle name is required.');
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final circleId = await ref
          .read(circlesRepositoryProvider)
          .createCircle(
            name: name,
            memberIds: _selectedFriendIds.toList(growable: false),
          );
      if (!mounted) return;
      ref.invalidate(circleSummariesProvider);
      context.pop();
      context.go('/circles/$circleId');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = tr('Could not create Circle. Try again. {error}', {
          'error': error,
        });
      });
    }
  }
}
