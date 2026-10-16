import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr('Edit alias'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              WeCordTextField(
                controller: _aliasController,
                enabled: !_isSaving,
                hint: tr('Alias'),
                errorText: _errorText,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isSaving) {
                    _save();
                  }
                },
              ),
              const SizedBox(height: 16),
              WeCordButton(
                key: const ValueKey('contact-alias-save'),
                label: tr('Save'),
                size: WeCordButtonSize.large,
                expand: true,
                loading: _isSaving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final alias = _aliasController.text.trim();
    if (alias.length > _maxAliasLength) {
      setState(() {
        _errorText = tr('Alias must be 48 characters or fewer.');
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
        _errorText = tr('Unable to save alias: {error}', {'error': error});
        _isSaving = false;
      });
    }
  }
}
