import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/forms/form_inputs.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/forms/form_results_page.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/features/forms/form_widgets.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the fill-in page of [formId]. Resolves to true once answers went in.
Future<bool?> openFormFill(BuildContext context, {required String formId}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(builder: (context) => FormFillPage(formId: formId)),
  );
}

/// The questions of a form with the person's own answers. A closed form, or
/// one that cannot be changed, shows the answers and nothing to send.
class FormFillPage extends ConsumerStatefulWidget {
  const FormFillPage({required this.formId, super.key});

  final String formId;

  @override
  ConsumerState<FormFillPage> createState() => _FormFillPageState();
}

class _FormFillPageState extends ConsumerState<FormFillPage> {
  final FormAnswers _answers = {};
  final _texts = <String, TextEditingController>{};
  final _previews = <String, Uint8List>{};
  final _keys = <String, GlobalKey>{};
  final _errors = <String, String>{};
  final _uploading = <String>{};
  var _seeded = false;
  var _busy = false;
  String? _banner;

  @override
  void dispose() {
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seed(FormSnapshot form) {
    if (_seeded) {
      return;
    }
    _seeded = true;
    _answers.addAll(form.myResponse?.answers ?? const {});
    for (final field in form.fields) {
      if (field.type.isText || field.type == FormFieldType.number) {
        final value = _answers[field.id];
        _texts[field.id] = TextEditingController(
          text: switch (value) {
            final num n => formatNumber(n),
            final String s => s,
            _ => '',
          },
        );
      }
    }
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void _set(String id, Object? value) {
    setState(() {
      if (value == null || (value is List && value.isEmpty)) {
        _answers.remove(id);
      } else {
        _answers[id] = value;
      }
      _errors.remove(id);
      _banner = null;
    });
  }

  Future<void> _pickDate(FormFieldDef field) async {
    final now = DateTime.now();
    final current = DateTime.tryParse('${_answers[field.id]}');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (picked != null && mounted) {
      String two(int n) => n.toString().padLeft(2, '0');
      _set(
        field.id,
        '${picked.year.toString().padLeft(4, '0')}-${two(picked.month)}-${two(picked.day)}',
      );
    }
  }

  Future<void> _pickMember(FormFieldDef field, String conversationId) async {
    final picked = await showFormMemberPicker(
      context,
      conversationId: conversationId,
      selectedId: _answers[field.id] as String?,
    );
    if (picked != null && mounted) {
      _set(field.id, picked);
    }
  }

  Future<void> _pickImage(FormFieldDef field, FormSnapshot form) async {
    final picker = ref.read(imagePickerServiceProvider);
    final repository = ref.read(formRepositoryProvider);
    try {
      final image = await picker.pickImage();
      if (image == null || !mounted) {
        return;
      }
      if (image.bytes.length > maxFormImageBytes) {
        setState(() => _errors[field.id] = tr('Pictures can be up to 10 MB.'));
        return;
      }
      setState(() {
        _uploading.add(field.id);
        _errors.remove(field.id);
      });
      final uploaded = await repository.uploadImage(
        conversationId: form.conversationId,
        formId: form.id,
        image: image,
      );
      if (!mounted) {
        return;
      }
      _previews[field.id] = image.bytes;
      setState(() => _uploading.remove(field.id));
      _set(field.id, uploaded);
    } on FormException catch (error) {
      if (mounted) {
        setState(() {
          _uploading.remove(field.id);
          _errors[field.id] = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _uploading.remove(field.id);
          _errors[field.id] = tr("The picture didn't upload. Try again.");
        });
      }
    }
  }

  /// The answers as typed, or null after marking what is wrong.
  FormAnswers? _collect(FormSnapshot form) {
    final answers = <String, Object?>{..._answers};
    final problems = <String, String>{};
    for (final field in form.fields) {
      if (field.type.isText) {
        answers[field.id] = _texts[field.id]?.text ?? '';
      } else if (field.type == FormFieldType.number) {
        final text = (_texts[field.id]?.text ?? '').trim().replaceAll(',', '.');
        if (text.isEmpty) {
          answers.remove(field.id);
        } else {
          final parsed = num.tryParse(text);
          if (parsed == null) {
            problems[field.id] = tr('Enter a number.');
          } else {
            answers[field.id] = parsed;
          }
        }
      }
    }
    for (final field in form.fields) {
      if (problems.containsKey(field.id)) {
        continue;
      }
      final problem = answerProblem(field, answers[field.id]);
      if (problem != null) {
        problems[field.id] = problem;
      }
    }
    if (problems.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(problems);
        _banner = tr('Check the answers marked in red.');
      });
      final first = form.fields.firstWhere((f) => problems.containsKey(f.id));
      final target = _keys[first.id]?.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          ),
        );
      }
      return null;
    }
    return cleanAnswers(form.fields, answers);
  }

  Future<void> _submit(FormSnapshot form) async {
    if (_busy || _uploading.isNotEmpty) {
      return;
    }
    final answers = _collect(form);
    if (answers == null) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _banner = null;
    });
    try {
      final result = await ref
          .read(formRepositoryProvider)
          .submit(form.id, answers);
      ref
        ..invalidate(formProvider(form.id))
        ..invalidate(formResultsProvider(form.id));
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.textHeld
                ? tr(
                    'Your answers are in, without the text: this circle reviews what new members write.',
                  )
                : result.updated
                ? tr('Your answers are updated.')
                : tr('Thanks, your answers are in.'),
          ),
        ),
      );
      navigator.pop(true);
    } on FormException catch (error) {
      ref.invalidate(formProvider(form.id));
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        final id = error.fieldId;
        if (id != null && form.fieldById(id) != null) {
          _errors[id] = error.kind == FormFailureKind.answerRequired
              ? tr('This question needs an answer.')
              : tr('Check this answer.');
        }
        _banner = error.message;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _banner = tr("That didn't work. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final async = ref.watch(formProvider(widget.formId));
    final form = async.value;
    if (form == null) {
      return FormPageFrame(
        pageKey: const ValueKey('form-fill-page'),
        title: tr('Form'),
        child: async.hasError
            ? FormNote(
                icon: Icons.assignment_late_outlined,
                text: tr("This form isn't available any more."),
                action: WeCordButton(
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () => ref.invalidate(formProvider(widget.formId)),
                ),
              )
            : const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    _seed(form);
    final now = DateTime.now();
    final canFill = form.canFill(now);
    final readOnly = !canFill;
    final status = formStatusText(context, form, now);
    final subtitle = [
      if (form.creatorName.isNotEmpty) form.creatorName,
      status,
    ].join(' · ');

    String? notice;
    if (form.isClosed(now)) {
      notice = form.hasAnswered
          ? tr('This form is closed. Your answers are below.')
          : tr('This form is closed.');
    } else if (form.hasAnswered && !canFill) {
      notice = form.settings.onePerPerson
          ? tr('You have filled this form in. It can not be changed.')
          : tr('This form has all the answers it takes.');
    } else if (!canFill) {
      notice = tr('This form has all the answers it takes.');
    }

    return FormPageFrame(
      pageKey: const ValueKey('form-fill-page'),
      title: form.title,
      subtitle: subtitle,
      actions: [
        if (form.canViewResults)
          WeCordIconButton(
            key: const ValueKey('form-open-results'),
            tooltip: tr('Results'),
            icon: Icons.bar_chart_rounded,
            variant: WeCordButtonVariant.ghost,
            onPressed: () =>
                unawaited(openFormResults(context, formId: form.id)),
          ),
      ],
      bottom: readOnly
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_banner != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _banner!,
                        key: const ValueKey('form-fill-banner'),
                        style: TextStyle(fontSize: 13.5, color: c.dangerText),
                      ),
                    ),
                  ),
                WeCordButton(
                  key: const ValueKey('form-submit'),
                  label: form.hasAnswered
                      ? tr('Update my answers')
                      : tr('Submit'),
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.large,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy || _uploading.isNotEmpty
                      ? null
                      : () => unawaited(_submit(form)),
                ),
              ],
            ),
      child: ListView(
        key: const ValueKey('form-fill-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (form.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                form.description,
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
              ),
            ),
          if (form.settings.anonymous)
            _Notice(
              key: const ValueKey('form-anonymous-notice'),
              icon: Icons.visibility_off_outlined,
              text: tr(
                'This form is anonymous. The person who made it cannot see who gave which answers.',
              ),
            ),
          if (notice != null)
            _Notice(
              key: const ValueKey('form-fill-notice'),
              icon: Icons.lock_outline_rounded,
              text: notice,
            ),
          for (final (index, field) in form.fields.indexed)
            KeyedSubtree(
              key: _keyFor(field.id),
              child: FormFieldBlock(
                field: field,
                number: index + 1,
                error: _errors[field.id],
                child: _input(field, form, readOnly),
              ),
            ),
        ],
      ),
    );
  }

  Widget _input(FormFieldDef field, FormSnapshot form, bool readOnly) {
    switch (field.type) {
      case FormFieldType.shortText:
      case FormFieldType.longText:
        return WeCordTextField(
          fieldKey: ValueKey('form-input-${field.id}'),
          controller: _texts[field.id],
          enabled: !readOnly,
          hint: field.type == FormFieldType.longText
              ? tr('Your answer')
              : tr('Your answer'),
          maxLength: field.type == FormFieldType.longText ? 2000 : 200,
          maxLines: field.type == FormFieldType.longText ? 6 : 1,
          minLines: field.type == FormFieldType.longText ? 3 : null,
          onChanged: (_) {
            if (_errors.containsKey(field.id)) {
              setState(() => _errors.remove(field.id));
            }
          },
        );
      case FormFieldType.number:
        final allowNegative = field.min == null || field.min! < 0;
        return WeCordTextField(
          fieldKey: ValueKey('form-input-${field.id}'),
          controller: _texts[field.id],
          enabled: !readOnly,
          hint: tr('Enter a number'),
          helperText: _numberHint(field),
          keyboardType: TextInputType.numberWithOptions(
            decimal: !field.integerOnly,
            signed: allowNegative,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(
                field.integerOnly
                    ? (allowNegative ? r'[0-9-]' : r'[0-9]')
                    : (allowNegative ? r'[0-9.,-]' : r'[0-9.,]'),
              ),
            ),
          ],
          maxLength: 16,
          onChanged: (_) {
            if (_errors.containsKey(field.id)) {
              setState(() => _errors.remove(field.id));
            }
          },
        );
      case FormFieldType.singleChoice:
        final picked = _answers[field.id];
        return Column(
          children: [
            for (final option in field.options)
              FormChoiceRow(
                fieldId: field.id,
                option: option,
                selected: picked == option.id,
                multiple: false,
                onChanged: readOnly
                    ? null
                    : () => _set(
                        field.id,
                        picked == option.id && !field.required
                            ? null
                            : option.id,
                      ),
              ),
          ],
        );
      case FormFieldType.multipleChoice:
        List<String> pickedNow() => [
          if (_answers[field.id] case final List<Object?> list)
            for (final item in list) '$item',
        ];
        final picked = pickedNow();
        return Column(
          children: [
            for (final option in field.options)
              FormChoiceRow(
                fieldId: field.id,
                option: option,
                selected: picked.contains(option.id),
                multiple: true,
                onChanged: readOnly
                    ? null
                    : () {
                        // Read at the tap, and keep the order of the choices.
                        final now = pickedNow();
                        _set(field.id, [
                          for (final o in field.options)
                            if ((o.id == option.id) != now.contains(o.id)) o.id,
                        ]);
                      },
              ),
          ],
        );
      case FormFieldType.date:
        final value = DateTime.tryParse('${_answers[field.id]}');
        return FormPickRow(
          keyName: 'form-input-${field.id}',
          icon: Icons.event_outlined,
          text: value == null
              ? null
              : MaterialLocalizations.of(context).formatMediumDate(value),
          placeholder: tr('Pick a date'),
          onPressed: readOnly ? null : () => unawaited(_pickDate(field)),
          onClear: readOnly ? null : () => _set(field.id, null),
        );
      case FormFieldType.member:
        final id = _answers[field.id] as String?;
        final members = ref
            .watch(conversationMembersProvider(form.conversationId))
            .value;
        final name = id == null
            ? null
            : members
                      ?.where((m) => m.profile.id == id)
                      .map(formMemberName)
                      .firstOrNull ??
                  tr('Someone');
        return FormPickRow(
          keyName: 'form-input-${field.id}',
          icon: Icons.person_outline_rounded,
          text: name,
          placeholder: tr('Pick a member'),
          onPressed: readOnly
              ? null
              : () => unawaited(_pickMember(field, form.conversationId)),
          onClear: readOnly ? null : () => _set(field.id, null),
        );
      case FormFieldType.image:
        final image = _answers[field.id];
        if (_uploading.contains(field.id)) {
          return Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Text(
                tr('Uploading…'),
                style: TextStyle(
                  fontSize: 14,
                  color: context.tokens.colors.muted,
                ),
              ),
            ],
          );
        }
        if (image is FormImageAnswer) {
          return Row(
            children: [
              FormImageThumb(
                key: ValueKey('form-image-${field.id}'),
                image: image,
                bytes: _previews[field.id],
                onTap: () => unawaited(showFormImage(context, image)),
              ),
              const SizedBox(width: 12),
              if (!readOnly)
                Wrap(
                  spacing: 8,
                  children: [
                    WeCordButton(
                      key: ValueKey('form-image-replace-${field.id}'),
                      label: tr('Replace'),
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      onPressed: () => unawaited(_pickImage(field, form)),
                    ),
                    WeCordButton(
                      key: ValueKey('form-image-remove-${field.id}'),
                      label: tr('Remove'),
                      variant: WeCordButtonVariant.ghost,
                      size: WeCordButtonSize.small,
                      onPressed: () {
                        _previews.remove(field.id);
                        _set(field.id, null);
                      },
                    ),
                  ],
                ),
            ],
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: WeCordButton(
            key: ValueKey('form-input-${field.id}'),
            label: tr('Add a picture'),
            icon: Icons.add_photo_alternate_outlined,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.medium,
            onPressed: readOnly
                ? null
                : () => unawaited(_pickImage(field, form)),
          ),
        );
    }
  }

  String? _numberHint(FormFieldDef field) {
    final min = field.min;
    final max = field.max;
    final kind = field.integerOnly ? tr('Whole number') : null;
    final range = min != null && max != null
        ? tr('{min} to {max}', {
            'min': formatNumber(min),
            'max': formatNumber(max),
          })
        : min != null
        ? tr('At least {min}.', {'min': formatNumber(min)})
        : max != null
        ? tr('At most {max}.', {'max': formatNumber(max)})
        : null;
    return [kind, range].whereType<String>().join(' · ').nullIfEmpty;
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}
