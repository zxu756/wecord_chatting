import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Lists [items] in a sheet and answers the one the person taps, as a pick.
/// [emptyText] says what to do when there is nothing yet.
Future<GroupTabPick?> pickGroupTabCandidate(
  BuildContext context, {
  required String title,
  required ProviderListenable<AsyncValue<List<GroupTabCandidate>>> items,
  required String emptyText,
}) {
  return showWeCordSheet<GroupTabPick>(
    context,
    title: title,
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => _CandidateList(
      items: items,
      emptyText: emptyText,
      scrollController: scrollController,
    ),
  );
}

class _CandidateList extends ConsumerWidget {
  const _CandidateList({
    required this.items,
    required this.emptyText,
    required this.scrollController,
  });

  final ProviderListenable<AsyncValue<List<GroupTabCandidate>>> items;
  final String emptyText;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final async = ref.watch(items);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            tr("That couldn't load. Try again."),
            style: TextStyle(fontSize: 15, color: c.muted),
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: c.muted),
              ),
            ),
          );
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            SettingsGroup(
              color: c.well,
              children: [
                for (final item in list)
                  SettingsRow(
                    key: ValueKey('group-tab-pick-${item.target}'),
                    title: item.title.isEmpty ? tr('Untitled') : item.title,
                    subtitle: item.closed ? tr('Closed') : null,
                    trailing: item.icon == null
                        ? null
                        : Text(
                            item.icon!,
                            style: const TextStyle(fontSize: 20),
                          ),
                    showChevron: false,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(GroupTabPick(target: item.target, title: item.title)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Asks for a web address and a name. Answers null when the person backs out.
Future<GroupTabPick?> pickGroupTabLink(BuildContext context) {
  return showWeCordSheet<GroupTabPick>(
    context,
    title: tr('Link'),
    builder: (context, _) => const _LinkForm(),
  );
}

/// Whether [text] is a web address a tab may point at (the server checks the
/// same).
bool isGroupTabLink(String text) {
  final value = text.trim();
  if (value.length > 500 || RegExp(r'\s').hasMatch(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class _LinkForm extends StatefulWidget {
  const _LinkForm();

  @override
  State<_LinkForm> createState() => _LinkFormState();
}

class _LinkFormState extends State<_LinkForm> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  void _done() {
    var address = _address.text.trim();
    if (address.isNotEmpty && !address.contains('://')) {
      address = 'https://$address';
    }
    if (!isGroupTabLink(address)) {
      setState(
        () => _error = tr('Enter a web address that starts with https://'),
      );
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Give the tab a name of up to 40 letters.'));
      return;
    }
    Navigator.of(context).pop(GroupTabPick(target: address, title: name));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('group-tab-link-address'),
            controller: _address,
            label: tr('Web address'),
            hint: 'https://',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            maxLength: 500,
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('group-tab-link-name'),
            controller: _name,
            label: tr('Tab name'),
            hint: tr('Rules'),
            maxLength: 40,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _done(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                key: const ValueKey('group-tab-link-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('group-tab-link-done'),
            label: tr('Add'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: _done,
          ),
        ],
      ),
    );
  }
}
