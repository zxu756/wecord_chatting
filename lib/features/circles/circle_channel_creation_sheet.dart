import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
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
                'Create channel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Type', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              // Voice channels arrive with voice support.
              SegmentedButton<CircleChannelKind>(
                key: const ValueKey('channel-kind-selector'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CircleChannelKind.text,
                    icon: Icon(Icons.tag),
                    label: Text('Text'),
                  ),
                  ButtonSegment(
                    value: CircleChannelKind.forum,
                    icon: Icon(Icons.forum_outlined),
                    label: Text('Forum'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _isSaving
                    ? null
                    : (selection) => setState(() => _kind = selection.single),
              ),
              const SizedBox(height: 4),
              Text(
                _kind == CircleChannelKind.forum
                    ? 'Members start posts, each with its own replies.'
                    : 'Members chat in one stream of messages.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Channel name',
                ),
              ),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _categoryId,
                  // Long category names ellipsize instead of overflowing.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Category',
                  ),
                  items: [
                    const DropdownMenuItem(child: Text('No category')),
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
                  child: const Text('Create'),
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
      setState(() => _errorText = 'Channel name is required.');
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
        _errorText = 'Could not create channel. Try again. $error';
      });
    }
  }
}
