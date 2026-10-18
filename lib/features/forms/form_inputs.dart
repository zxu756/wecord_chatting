import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart'
    show chatImageProviderFactoryProvider;
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/forms/form_widgets.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A question's title, its help, the input and what is wrong with the answer.
class FormFieldBlock extends StatelessWidget {
  const FormFieldBlock({
    required this.field,
    required this.child,
    this.number,
    this.error,
    super.key,
  });

  final FormFieldDef field;
  final Widget child;
  final int? number;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: ValueKey('form-field-${field.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: error == null ? c.lineSoft : c.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                children: [
                  if (number != null)
                    TextSpan(
                      text: '$number. ',
                      style: TextStyle(color: c.muted),
                    ),
                  TextSpan(text: field.label),
                  if (field.required)
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: c.dangerText),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
          if (field.help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                field.help,
                style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
              ),
            ),
          const SizedBox(height: 10),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  key: ValueKey('form-error-${field.id}'),
                  style: TextStyle(fontSize: 13, color: c.dangerText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One choice: a radio or a check box and its label.
class FormChoiceRow extends StatelessWidget {
  const FormChoiceRow({
    required this.fieldId,
    required this.option,
    required this.selected,
    required this.multiple,
    required this.onChanged,
    super.key,
  });

  final String fieldId;
  final FormOption option;
  final bool selected;
  final bool multiple;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final icon = multiple
        ? (selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded)
        : (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded);
    return WeCordPressable(
      key: ValueKey('form-option-$fieldId-${option.id}'),
      onPressed: onChanged,
      selected: selected,
      semanticLabel: option.label,
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: selected ? c.accent : c.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? c.accentText : c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens a picker (a date, a member) and shows the choice.
class FormPickRow extends StatelessWidget {
  const FormPickRow({
    required this.keyName,
    required this.icon,
    required this.text,
    required this.placeholder,
    required this.onPressed,
    this.onClear,
    this.leading,
    super.key,
  });

  final String keyName;
  final IconData icon;
  final String? text;
  final String placeholder;
  final VoidCallback? onPressed;
  final VoidCallback? onClear;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      children: [
        Expanded(
          child: WeCordPressable(
            key: ValueKey(keyName),
            onPressed: onPressed,
            semanticLabel: text ?? placeholder,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            builder: (context, states) => Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  if (leading == null) ...[
                    Icon(icon, size: 20, color: c.muted),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      text ?? placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: text == null
                            ? FontWeight.w500
                            : FontWeight.w700,
                        color: text == null ? c.muted : c.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
                ],
              ),
            ),
          ),
        ),
        if (onClear != null && text != null)
          WeCordIconButton(
            tooltip: tr('Clear'),
            icon: Icons.close_rounded,
            size: 36,
            iconSize: 18,
            variant: WeCordButtonVariant.ghost,
            onPressed: onClear,
          ),
      ],
    );
  }
}

/// A member's name: their circle nickname in channels, else the display
/// name.
String formMemberName(GroupMember member) {
  final nickname = member.nickname?.trim();
  return nickname == null || nickname.isEmpty
      ? member.profile.displayName
      : nickname;
}

/// Picks one member of [conversationId]. Resolves to the member's user id.
Future<String?> showFormMemberPicker(
  BuildContext context, {
  required String conversationId,
  String? selectedId,
}) {
  return showWeCordSheet<String>(
    context,
    title: tr('Pick a member'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => _MemberPickerSheet(
      conversationId: conversationId,
      selectedId: selectedId,
      scrollController: scrollController,
    ),
  );
}

class _MemberPickerSheet extends ConsumerStatefulWidget {
  const _MemberPickerSheet({
    required this.conversationId,
    required this.selectedId,
    required this.scrollController,
  });

  final String conversationId;
  final String? selectedId;
  final ScrollController? scrollController;

  @override
  ConsumerState<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends ConsumerState<_MemberPickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final async = ref.watch(conversationMembersProvider(widget.conversationId));
    final members = async.value ?? const <GroupMember>[];
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final member in members)
        if (query.isEmpty ||
            formMemberName(member).toLowerCase().contains(query) ||
            member.profile.username.toLowerCase().contains(query))
          member,
    ];
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: WeCordTextField(
              fieldKey: const ValueKey('form-member-search'),
              hint: tr('Search members'),
              prefixIcon: Icons.search_rounded,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: async.isLoading && members.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : shown.isEmpty
                ? FormNote(
                    icon: Icons.person_search_outlined,
                    text: tr('No one found.'),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final member = shown[index];
                      final selected = member.profile.id == widget.selectedId;
                      final url = member.profile.avatarUrl;
                      return WeCordPressable(
                        key: ValueKey('form-member-${member.profile.id}'),
                        onPressed: () =>
                            Navigator.of(context).pop(member.profile.id),
                        selected: selected,
                        semanticLabel: formMemberName(member),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(WeCordRadii.md),
                        ),
                        builder: (context, states) => Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? c.accentSoft
                                : states.contains(WidgetState.hovered)
                                ? c.raised
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(WeCordRadii.md),
                          ),
                          child: Row(
                            children: [
                              PersonAvatar(
                                name: formMemberName(member),
                                size: 36,
                                image: url == null ? null : NetworkImage(url),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  formMemberName(member),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: c.accent,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A picture answer as a thumbnail: from [bytes] when just picked, else read
/// through a signed link.
class FormImageThumb extends ConsumerWidget {
  const FormImageThumb({
    required this.image,
    this.bytes,
    this.size = 96,
    this.onTap,
    super.key,
  });

  final FormImageAnswer image;
  final Uint8List? bytes;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    Widget picture;
    if (bytes != null) {
      picture = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        width: size,
        height: size,
      );
    } else {
      final url = ref.watch(formImageUrlProvider(image));
      picture = url.when(
        data: (link) => Image(
          image: ref.read(chatImageProviderFactoryProvider)(link),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => _placeholder(c, broken: true),
        ),
        loading: () => _placeholder(c),
        error: (_, _) => _placeholder(c, broken: true),
      );
    }
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(WeCordRadii.md),
      child: SizedBox(width: size, height: size, child: picture),
    );
    return Semantics(
      image: true,
      label: tr('Picture'),
      button: onTap != null,
      child: onTap == null
          ? thumb
          : WeCordPressable(
              onPressed: onTap,
              semanticLabel: tr('Open picture'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              builder: (context, states) => thumb,
            ),
    );
  }

  Widget _placeholder(WeCordPalette c, {bool broken = false}) {
    return Container(
      width: size,
      height: size,
      color: c.raised,
      alignment: Alignment.center,
      child: Icon(
        broken ? Icons.broken_image_outlined : Icons.image_outlined,
        color: c.faint,
        size: 24,
      ),
    );
  }
}

/// A short-lived link to a picture answer.
final formImageUrlProvider = FutureProvider.autoDispose
    .family<String, FormImageAnswer>((ref, image) {
      return ref.watch(formRepositoryProvider).imageUrl(image);
    });

/// Opens a picture answer full size.
Future<void> showFormImage(BuildContext context, FormImageAnswer image) {
  return showDialog<void>(
    context: context,
    barrierColor: context.tokens.colors.scrim,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final url = ref.watch(formImageUrlProvider(image));
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                child: url.when(
                  data: (link) => InteractiveViewer(
                    child: Image(
                      image: ref.read(chatImageProviderFactoryProvider)(link),
                      fit: BoxFit.contain,
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox(
                    height: 200,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: WeCordIconButton(
                  tooltip: tr('Close'),
                  icon: Icons.close_rounded,
                  size: 36,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
