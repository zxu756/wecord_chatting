import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What an AutoMod rule looks for.
enum AutoModRuleKind {
  /// Keywords (whole words, or with `*` wildcards) and regex patterns.
  keyword('keyword'),

  /// More unique mentions in one message than [AutoModRule.mentionLimit].
  mentionSpam('mention_spam'),

  /// More messages than [AutoModRule.messageLimit] in
  /// [AutoModRule.windowSeconds].
  spam('spam');

  const AutoModRuleKind(this.key);

  final String key;

  /// How many rules of this kind a circle can have.
  int get maxPerCircle => this == keyword ? 6 : 1;

  static AutoModRuleKind fromKey(String? key) {
    return values.firstWhere(
      (kind) => kind.key == key,
      orElse: () => AutoModRuleKind.keyword,
    );
  }
}

/// Limits the server enforces (see `202610160020_automod.sql`).
abstract final class AutoModLimits {
  static const nameLength = 100;
  static const keywords = 1000;
  static const keywordLength = 60;
  static const patterns = 10;
  static const patternLength = 260;
  static const blockReasonLength = 150;
}

/// One AutoMod rule of a circle.
class AutoModRule {
  const AutoModRule({
    required this.name,
    required this.kind,
    this.id,
    this.enabled = true,
    this.keywords = const [],
    this.regexPatterns = const [],
    this.mentionLimit,
    this.messageLimit,
    this.windowSeconds,
    this.blockMessage = true,
    this.blockReason,
    this.alertChannelId,
    this.timeoutSeconds,
    this.exemptRoleIds = const [],
    this.exemptChannelIds = const [],
  });

  /// A new rule of [kind] with the usual starting values.
  factory AutoModRule.draft(AutoModRuleKind kind) {
    return switch (kind) {
      AutoModRuleKind.keyword => AutoModRule(
        name: tr('Custom keywords'),
        kind: AutoModRuleKind.keyword,
      ),
      AutoModRuleKind.mentionSpam => AutoModRule(
        name: tr('Mention spam'),
        kind: AutoModRuleKind.mentionSpam,
        mentionLimit: 20,
      ),
      AutoModRuleKind.spam => AutoModRule(
        name: tr('Spam'),
        kind: AutoModRuleKind.spam,
        messageLimit: 5,
        windowSeconds: 5,
      ),
    };
  }

  factory AutoModRule.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) =>
        value is List ? [for (final item in value) '$item'] : const <String>[];
    return AutoModRule(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      kind: AutoModRuleKind.fromKey(json['kind'] as String?),
      enabled: json['enabled'] as bool? ?? true,
      keywords: strings(json['keywords']),
      regexPatterns: strings(json['regex_patterns']),
      mentionLimit: (json['mention_limit'] as num?)?.toInt(),
      messageLimit: (json['message_limit'] as num?)?.toInt(),
      windowSeconds: (json['window_seconds'] as num?)?.toInt(),
      blockMessage: json['block_message'] as bool? ?? false,
      blockReason: json['block_reason'] as String?,
      alertChannelId: json['alert_channel_id'] as String?,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt(),
      exemptRoleIds: strings(json['exempt_role_ids']),
      exemptChannelIds: strings(json['exempt_channel_ids']),
    );
  }

  /// Null until saved.
  final String? id;
  final String name;
  final AutoModRuleKind kind;
  final bool enabled;
  final List<String> keywords;
  final List<String> regexPatterns;
  final int? mentionLimit;
  final int? messageLimit;
  final int? windowSeconds;

  /// Keep the message from being sent.
  final bool blockMessage;

  /// Shown to the sender when their message is blocked.
  final String? blockReason;

  /// The channel alerts are posted in, if any.
  final String? alertChannelId;

  /// How long to time the member out for, if at all.
  final int? timeoutSeconds;
  final List<String> exemptRoleIds;
  final List<String> exemptChannelIds;

  bool get hasAction =>
      blockMessage || alertChannelId != null || timeoutSeconds != null;

  Map<String, dynamic> toJson() {
    return {
      'id': ?id,
      'name': name.trim(),
      'kind': kind.key,
      'enabled': enabled,
      'keywords': keywords,
      'regex_patterns': regexPatterns,
      'mention_limit': mentionLimit,
      'message_limit': messageLimit,
      'window_seconds': windowSeconds,
      'block_message': blockMessage,
      'block_reason': blockMessage ? blockReason : null,
      'alert_channel_id': alertChannelId,
      'timeout_seconds': timeoutSeconds,
      'exempt_role_ids': exemptRoleIds,
      'exempt_channel_ids': exemptChannelIds,
    };
  }

  AutoModRule copyWith({bool? enabled}) {
    return AutoModRule(
      id: id,
      name: name,
      kind: kind,
      enabled: enabled ?? this.enabled,
      keywords: keywords,
      regexPatterns: regexPatterns,
      mentionLimit: mentionLimit,
      messageLimit: messageLimit,
      windowSeconds: windowSeconds,
      blockMessage: blockMessage,
      blockReason: blockReason,
      alertChannelId: alertChannelId,
      timeoutSeconds: timeoutSeconds,
      exemptRoleIds: exemptRoleIds,
      exemptChannelIds: exemptChannelIds,
    );
  }
}

/// Splits what was typed into the keyword box (commas or new lines) into
/// keywords: trimmed, lower case, without blanks or repeats.
List<String> parseAutoModKeywords(String text) {
  final seen = <String>{};
  return [
    for (final part in text.split(RegExp(r'[,\n]')))
      if (part.trim().isNotEmpty && seen.add(part.trim().toLowerCase()))
        part.trim().toLowerCase(),
  ];
}

/// One pattern per line, without blank lines.
List<String> parseAutoModPatterns(String text) {
  return [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

final circleAutoModRepositoryProvider = Provider<CircleAutoModRepository>((
  ref,
) {
  try {
    return CircleAutoModRepository(
      SupabaseRpcDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const CircleAutoModRepository(UninitializedRpcDataSource());
  }
});

/// The AutoMod rules of a circle.
final circleAutoModRulesProvider = FutureProvider.autoDispose
    .family<List<AutoModRule>, String>((ref, circleId) {
      return ref.watch(circleAutoModRepositoryProvider).listRules(circleId);
    });

/// Calls database functions; tests swap in a fake.
abstract interface class RpcDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);
}

class SupabaseRpcDataSource implements RpcDataSource {
  const SupabaseRpcDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc<Object?>(functionName, params: params);
  }
}

class UninitializedRpcDataSource implements RpcDataSource {
  const UninitializedRpcDataSource();

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    throw StateError(
      'Supabase must be initialized before calling $functionName.',
    );
  }
}

class CircleAutoModRepository {
  const CircleAutoModRepository(this._dataSource);

  final RpcDataSource _dataSource;

  Future<List<AutoModRule>> listRules(String circleId) async {
    final rows = await _dataSource.rpc('list_circle_automod_rules', {
      'target_circle_id': circleId,
    });
    if (rows is! List) {
      return const [];
    }
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) AutoModRule.fromJson(row),
    ];
  }

  /// Creates [rule] (without an id) or updates it; returns its id.
  Future<String> saveRule({
    required String circleId,
    required AutoModRule rule,
  }) async {
    final id = await _dataSource.rpc('save_circle_automod_rule', {
      'target_circle_id': circleId,
      'rule': rule.toJson(),
    });
    return id as String;
  }

  Future<void> deleteRule(String ruleId) async {
    await _dataSource.rpc('delete_circle_automod_rule', {
      'target_rule_id': ruleId,
    });
  }
}
