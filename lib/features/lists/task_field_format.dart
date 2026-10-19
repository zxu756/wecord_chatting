import 'package:flutter/material.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/group.dart';

IconData taskFieldIcon(TaskFieldType type) => switch (type) {
  TaskFieldType.number => Icons.tag_rounded,
  TaskFieldType.select => Icons.arrow_drop_down_circle_outlined,
  TaskFieldType.link => Icons.link_rounded,
  TaskFieldType.person => Icons.person_outline_rounded,
};

/// A number as people write it: no ".0".
String formatTaskNumber(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// The words for the value of a field, or null when there is none (or it no
/// longer fits the field).
String? formatTaskFieldValue(
  TaskFieldDef def,
  Object? value,
  List<GroupMember> members,
) {
  if (value == null) {
    return null;
  }
  switch (def.type) {
    case TaskFieldType.number:
      return value is num ? formatTaskNumber(value) : null;
    case TaskFieldType.select:
      return def.optionById(value)?.name;
    case TaskFieldType.link:
      if (value is! String) {
        return null;
      }
      final host = Uri.tryParse(value)?.host ?? '';
      return host.isEmpty ? value : host.replaceFirst('www.', '');
    case TaskFieldType.person:
      for (final member in members) {
        if (member.profile.id == value) {
          return member.profile.displayName;
        }
      }
      return tr('Someone');
  }
}

/// An address the way it is stored: with a scheme, http or https only.
/// Returns null when it is not an address.
String? normalizeTaskLink(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) {
    return null;
  }
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text)) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty ||
      text.length > 500) {
    return null;
  }
  return text;
}
