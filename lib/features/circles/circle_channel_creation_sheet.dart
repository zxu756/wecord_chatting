import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

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
  var _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Create channel'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(tr('Type'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<CircleChannelKind>(
                key: const ValueKey('channel-kind-selector'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: CircleChannelKind.text,
                    icon: const Icon(Icons.tag),
                    label: Text(tr('Text')),
                  ),
                  ButtonSegment(
                    value: CircleChannelKind.voice,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(tr('Voice')),
                  ),
                  ButtonSegment(
                    value: CircleChannelKind.forum,
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(tr('Forum')),
                  ),
                  ButtonSegment(
                    value: CircleChannelKind.stage,
                    icon: const Icon(Icons.podcasts),
                    label: Text(tr('Stage')),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _isSaving
                    ? null
                    : (selection) => setState(() => _kind = selection.single),
              ),
              const SizedBox(height: 4),
              Text(switch (_kind) {
                CircleChannelKind.forum => tr(
                  'Members start posts, each with its own replies.',
                ),
                CircleChannelKind.voice => tr(
                  'Members talk, turn on video and share screens.',
                ),
                CircleChannelKind.stage => tr(
                  'A few speakers talk while everyone else listens and can '
                  'raise a hand to speak.',
                ),
                CircleChannelKind.text => tr(
                  'Members chat in one stream of messages.',
                ),
              }, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Channel name'),
                ),
              ),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _categoryId,
                  // Long category names ellipsize instead of overflowing.
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Category'),
                  ),
                  items: [
                    DropdownMenuItem(child: Text(tr('No category'))),
                    for (final category in widget.categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _categoryId = value),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _isSaving ? null : _createChannel,
                  child: Text(tr('Create')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createChannel() async {
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
      await ref
          .read(circlesRepositoryProvider)
          .createChannel(
            circleId: widget.circleId,
            name: name,
            categoryId: _categoryId,
            kind: _kind,
          );
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
