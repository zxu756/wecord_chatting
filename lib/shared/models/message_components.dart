/// The buttons, links and lists a bot puts on a message (messages.components,
/// see migration 202610280610). The server cleans them before storing; this
/// reads them again defensively - anything that does not fit the rules is
/// left out rather than drawn - so a row from an older or hostile server can
/// not show a link to a script or an endless list. Every text is plain text
/// to the app: nothing here is ever parsed as markdown or HTML.
library;

import 'package:flutter/foundation.dart';

/// The limits of the components. They are the server's (migration
/// 202610280610): the app only ever draws up to them.
abstract final class ComponentLimits {
  static const maxRows = 5;
  static const maxPerRow = 5;
  static const maxLabel = 40;
  static const maxOptionLabel = 100;
  static const maxPlaceholder = 100;
  static const maxOptions = 25;
  static const maxModalFields = 5;
  static const maxModalTitle = 45;
  static const maxFieldLabel = 45;
  static const maxAnswer = 1000;
  static const defaultAnswer = 200;
}

enum ComponentButtonStyle {
  primary,
  secondary,
  danger;

  static ComponentButtonStyle fromJson(Object? value) {
    for (final style in values) {
      if (style.name == value) {
        return style;
      }
    }
    return ComponentButtonStyle.secondary;
  }
}

final _hiddenCharacters = RegExp(
  '[\\u0000-\\u001f\\u007f\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u2064'
  '\\u2066-\\u2069\\ufeff]',
);

/// [value] trimmed, without control or direction-changing characters, or
/// null when it is not a string or is empty or too long once cleaned.
String? cleanComponentText(
  Object? value, {
  required int max,
  bool allowEmpty = false,
}) {
  if (value is! String) {
    return null;
  }
  final cleaned = value.replaceAll(_hiddenCharacters, '').trim();
  if (cleaned.isEmpty && !allowEmpty) {
    return null;
  }
  // Count characters, not UTF-16 units.
  if (cleaned.runes.length > max) {
    return null;
  }
  return cleaned;
}

final _httpsHost = RegExp(
  r'^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$',
);
final _forbiddenInUrl = RegExp('[\\s\\u0000-\\u001f\\u007f"<>`\\\\]');
const _innerSuffixes = [
  'local',
  'localhost',
  'localdomain',
  'internal',
  'lan',
  'home',
  'corp',
  'intranet',
  'private',
  'arpa',
];

/// The link of a link button, when it is one the app may open: https only, a
/// real host name (no IP address, no inner name), the usual port, no user name
/// or password, at most 500 characters.
Uri? safeComponentUri(Object? value) {
  if (value is! String ||
      value.length > 500 ||
      _forbiddenInUrl.hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      !(uri.port == 0 || uri.port == 443) ||
      uri.host.isEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!_httpsHost.hasMatch(host)) {
    return null;
  }
  for (final suffix in _innerSuffixes) {
    if (host.endsWith('.$suffix')) {
      return null;
    }
  }
  return uri;
}

/// One thing in a form that a button opens.
@immutable
class ComponentModalField {
  const ComponentModalField({
    required this.id,
    required this.label,
    this.paragraph = false,
    this.required = true,
    this.placeholder,
    this.maxLength = ComponentLimits.defaultAnswer,
  });

  static ComponentModalField? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final label = cleanComponentText(
      json['label'],
      max: ComponentLimits.maxFieldLabel,
    );
    if (id is! String || !componentIdPattern.hasMatch(id) || label == null) {
      return null;
    }
    final maxLength = json['max_length'];
    return ComponentModalField(
      id: id,
      label: label,
      paragraph: json['style'] == 'paragraph',
      required: json['required'] != false,
      placeholder: cleanComponentText(
        json['placeholder'],
        max: ComponentLimits.maxPlaceholder,
      ),
      maxLength: maxLength is num && maxLength >= 1
          ? maxLength.toInt().clamp(1, ComponentLimits.maxAnswer)
          : ComponentLimits.defaultAnswer,
    );
  }

  final String id;
  final String label;
  final bool paragraph;
  final bool required;
  final String? placeholder;
  final int maxLength;
}

/// The form a button opens before the press is sent.
@immutable
class ComponentModal {
  const ComponentModal({required this.title, required this.fields});

  static ComponentModal? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final title = cleanComponentText(
      json['title'],
      max: ComponentLimits.maxModalTitle,
    );
    final rawFields = json['fields'];
    if (title == null || rawFields is! List) {
      return null;
    }
    final fields = <ComponentModalField>[];
    final seen = <String>{};
    for (final raw in rawFields) {
      final field = ComponentModalField.maybeFromJson(raw);
      if (field != null &&
          fields.length < ComponentLimits.maxModalFields &&
          seen.add(field.id)) {
        fields.add(field);
      }
    }
    return fields.isEmpty ? null : ComponentModal(title: title, fields: fields);
  }

  final String title;
  final List<ComponentModalField> fields;
}

/// What the server accepts as a component id.
final componentIdPattern = RegExp(r'^[A-Za-z0-9_.:-]{1,64}$');

@immutable
sealed class MessageComponent {
  const MessageComponent();

  static MessageComponent? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    switch (json['type']) {
      case 'button':
        final id = json['id'];
        final label = cleanComponentText(
          json['label'],
          max: ComponentLimits.maxLabel,
        );
        if (id is! String ||
            !componentIdPattern.hasMatch(id) ||
            label == null) {
          return null;
        }
        return ButtonComponent(
          id: id,
          label: label,
          style: ComponentButtonStyle.fromJson(json['style']),
          disabled: json['disabled'] == true,
          modal: json['modal'] == null
              ? null
              : ComponentModal.maybeFromJson(json['modal']),
        );
      case 'link':
        final uri = safeComponentUri(json['url']);
        final label = cleanComponentText(
          json['label'],
          max: ComponentLimits.maxLabel,
        );
        if (uri == null || label == null) {
          return null;
        }
        return LinkComponent(label: label, uri: uri);
      case 'select':
        return SelectComponent.maybeFromJson(json);
    }
    return null;
  }
}

class ButtonComponent extends MessageComponent {
  const ButtonComponent({
    required this.id,
    required this.label,
    this.style = ComponentButtonStyle.secondary,
    this.disabled = false,
    this.modal,
  });

  final String id;
  final String label;
  final ComponentButtonStyle style;
  final bool disabled;

  /// A form to fill before the press is sent.
  final ComponentModal? modal;
}

class LinkComponent extends MessageComponent {
  const LinkComponent({required this.label, required this.uri});

  final String label;

  /// An https address, already checked by [safeComponentUri].
  final Uri uri;
}

@immutable
class SelectOption {
  const SelectOption({
    required this.label,
    required this.value,
    this.description,
    this.isDefault = false,
  });

  final String label;
  final String value;
  final String? description;
  final bool isDefault;
}

class SelectComponent extends MessageComponent {
  const SelectComponent({
    required this.id,
    required this.options,
    this.placeholder,
    this.minValues = 1,
    this.maxValues = 1,
    this.disabled = false,
  });

  static SelectComponent? maybeFromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final rawOptions = json['options'];
    if (id is! String ||
        !componentIdPattern.hasMatch(id) ||
        rawOptions is! List) {
      return null;
    }
    final options = <SelectOption>[];
    final seen = <String>{};
    for (final raw in rawOptions) {
      if (raw is! Map || options.length >= ComponentLimits.maxOptions) {
        continue;
      }
      final label = cleanComponentText(
        raw['label'],
        max: ComponentLimits.maxOptionLabel,
      );
      final value = cleanComponentText(raw['value'], max: 100);
      if (label == null || value == null || !seen.add(value)) {
        continue;
      }
      final description = cleanComponentText(
        raw['description'],
        max: 100,
        allowEmpty: true,
      );
      options.add(
        SelectOption(
          label: label,
          value: value,
          description: description == null || description.isEmpty
              ? null
              : description,
          isDefault: raw['default'] == true,
        ),
      );
    }
    if (options.isEmpty) {
      return null;
    }
    final maxValues =
        (json['max_values'] is num ? (json['max_values'] as num).toInt() : 1)
            .clamp(1, options.length);
    final minValues =
        (json['min_values'] is num ? (json['min_values'] as num).toInt() : 1)
            .clamp(0, maxValues);
    return SelectComponent(
      id: id,
      options: options,
      placeholder: cleanComponentText(
        json['placeholder'],
        max: ComponentLimits.maxPlaceholder,
      ),
      minValues: minValues,
      maxValues: maxValues,
      disabled: json['disabled'] == true,
    );
  }

  final String id;
  final String? placeholder;
  final List<SelectOption> options;
  final int minValues;
  final int maxValues;
  final bool disabled;

  bool get multiple => maxValues > 1;

  /// The options chosen when the message was written.
  List<String> get defaults => [
    for (final option in options)
      if (option.isDefault) option.value,
  ];
}

/// All the rows of components of a message.
@immutable
class MessageComponents {
  const MessageComponents(this.rows);

  /// Null when [json] holds nothing the app may draw.
  static MessageComponents? maybeFromJson(Object? json) {
    if (json is! List) {
      return null;
    }
    final rows = <List<MessageComponent>>[];
    for (final rawRow in json) {
      if (rawRow is! List || rows.length >= ComponentLimits.maxRows) {
        continue;
      }
      final row = <MessageComponent>[];
      for (final raw in rawRow) {
        final component = MessageComponent.maybeFromJson(raw);
        if (component != null && row.length < ComponentLimits.maxPerRow) {
          row.add(component);
        }
      }
      // A list takes a whole row.
      if (row.any((c) => c is SelectComponent) && row.length > 1) {
        row.removeWhere((c) => c is! SelectComponent);
        if (row.length > 1) {
          row.removeRange(1, row.length);
        }
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    return rows.isEmpty ? null : MessageComponents(rows);
  }

  final List<List<MessageComponent>> rows;

  Iterable<MessageComponent> get all => rows.expand((row) => row);
}
