import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/profile.dart';

class ContactAliasSheet extends ConsumerStatefulWidget {
  const ContactAliasSheet({required this.profile, super.key});

  final Profile profile;

  @override
  ConsumerState<ContactAliasSheet> createState() => _ContactAliasSheetState();
}

class _ContactAliasSheetState extends ConsumerState<ContactAliasSheet> {
  static const _maxAliasLength = 48;

  late final TextEditingController _aliasController;
  var _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.profile.alias ?? '');
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit alias', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _aliasController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Alias',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isSaving) {
                  _save();
                }
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final alias = _aliasController.text.trim();
    if (alias.length > _maxAliasLength) {
      setState(() {
        _errorText = 'Alias must be 48 characters or fewer.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(contactsRepositoryProvider)
          .setContactAlias(
            friendId: widget.profile.id,
            alias: alias.isEmpty ? null : alias,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Unable to save alias: $error';
        _isSaving = false;
      });
    }
  }
}
