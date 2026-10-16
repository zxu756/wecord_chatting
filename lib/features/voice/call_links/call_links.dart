import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/site_url.dart';

/// Where call links open in the app (and on the web, after the site's
/// origin): `/call/<code>`.
const callLinkRoutePrefix = '/call';

String callLinkPath(String code) => '$callLinkRoutePrefix/$code';

/// The shareable link for [code]: `https://wecord.jokebear.fyi/call/<code>`
/// (the site the build points at, see [authRedirectUrl]).
String callLinkUrl(String code, {String? site}) {
  return '${site ?? authRedirectUrl()}${callLinkPath(code)}';
}

final _bareCodePattern = RegExp(r'^[a-z0-9]{12}$');
final _linkCodePattern = RegExp(r'/call/([A-Za-z0-9]{12})(?![A-Za-z0-9])');

/// Extracts a call link's code from a pasted code, path or link.
String? parseCallLinkCode(String input) {
  final trimmed = input.trim();
  if (_bareCodePattern.hasMatch(trimmed.toLowerCase())) {
    return trimmed.toLowerCase();
  }
  return _linkCodePattern.firstMatch(trimmed)?.group(1)!.toLowerCase();
}

/// The route a browser's address (`https://site/call/<code>`) stands for, or
/// null for any other. The web app keeps its own routes after a `#`, so a
/// link without one (as people share it) needs this to find its page.
String? callLinkLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 && '/${segments.first}' == callLinkRoutePrefix) {
    final code = parseCallLinkCode(base.path);
    return code == null ? null : callLinkPath(code);
  }
  return null;
}

/// How long a new call link works.
enum CallLinkExpiry {
  day('day'),
  week('week'),
  never('never');

  const CallLinkExpiry(this.wire);

  /// What `create_call_link` takes.
  final String wire;
}

/// Where a call link leads.
@immutable
class CallLinkTarget {
  const CallLinkTarget.conversation(String this.conversationId)
    : channelId = null;
  const CallLinkTarget.channel(String this.channelId) : conversationId = null;

  /// The direct or group chat whose call it joins.
  final String? conversationId;

  /// The voice channel it joins.
  final String? channelId;

  @override
  bool operator ==(Object other) =>
      other is CallLinkTarget &&
      other.conversationId == conversationId &&
      other.channelId == channelId;

  @override
  int get hashCode => Object.hash(conversationId, channelId);
}

/// A link the current user made.
@immutable
class CallLink {
  const CallLink({required this.code, required this.createdAt, this.expiresAt});

  factory CallLink.fromJson(Map<String, dynamic> json) {
    return CallLink(
      code: json['code'] as String,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(
        json['expires_at'] as String? ?? '',
      )?.toUtc(),
    );
  }

  final String code;
  final DateTime createdAt;

  /// When it stops working; null for never.
  final DateTime? expiresAt;
}

/// Why a link can't be used.
enum CallLinkProblem {
  /// No such link.
  notFound,
  revoked,
  expired,

  /// The link works, but the current user may not join what it leads to.
  noAccess,
}

/// What opening a link means for the current user.
@immutable
class CallLinkResolution {
  const CallLinkResolution.problem(CallLinkProblem this.problem)
    : name = '',
      circleId = null,
      channelId = null,
      conversationId = null,
      stage = false;

  const CallLinkResolution.call({
    required String this.conversationId,
    required this.name,
  }) : problem = null,
       circleId = null,
       channelId = null,
       stage = false;

  const CallLinkResolution.channel({
    required String this.circleId,
    required String this.channelId,
    required String this.conversationId,
    required this.name,
    this.stage = false,
  }) : problem = null;

  factory CallLinkResolution.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status == 'ok') {
      final name = json['name'] as String? ?? '';
      if (json['kind'] == 'channel') {
        return CallLinkResolution.channel(
          circleId: json['circle_id'] as String,
          channelId: json['channel_id'] as String,
          conversationId: json['conversation_id'] as String,
          name: name,
          stage: json['stage'] == true,
        );
      }
      return CallLinkResolution.call(
        conversationId: json['conversation_id'] as String,
        name: name,
      );
    }
    return CallLinkResolution.problem(switch (status) {
      'revoked' => CallLinkProblem.revoked,
      'expired' => CallLinkProblem.expired,
      'no_access' => CallLinkProblem.noAccess,
      _ => CallLinkProblem.notFound,
    });
  }

  /// Set when the link can't be used.
  final CallLinkProblem? problem;

  /// The chat's or channel's name.
  final String name;

  /// For a voice channel: its circle and id.
  final String? circleId;
  final String? channelId;

  /// The chat of a call, or the channel's own conversation.
  final String? conversationId;
  final bool stage;

  bool get isOk => problem == null;
  bool get isChannel => channelId != null;
}

abstract interface class CallLinksRepository {
  /// Makes a link to [target]; throws when the user may not call there.
  Future<CallLink> create(CallLinkTarget target, CallLinkExpiry expiry);

  /// The current user's links to [target] that still work.
  Future<List<CallLink>> list(CallLinkTarget target);

  Future<void> revoke(String code);

  Future<CallLinkResolution> resolve(String code);
}

final callLinksRepositoryProvider = Provider<CallLinksRepository>((ref) {
  try {
    return SupabaseCallLinksRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedCallLinksRepository();
  }
});

class SupabaseCallLinksRepository implements CallLinksRepository {
  const SupabaseCallLinksRepository(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _target(CallLinkTarget target) => {
    'target_conversation_id': target.conversationId,
    'target_channel_id': target.channelId,
  };

  @override
  Future<CallLink> create(CallLinkTarget target, CallLinkExpiry expiry) async {
    final data = await _client.rpc(
      'create_call_link',
      params: {..._target(target), 'expires_in': expiry.wire},
    );
    return CallLink.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<CallLink>> list(CallLinkTarget target) async {
    final data = await _client.rpc('list_call_links', params: _target(target));
    return [
      for (final row in data as List)
        CallLink.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> revoke(String code) async {
    await _client.rpc('revoke_call_link', params: {'target_code': code});
  }

  @override
  Future<CallLinkResolution> resolve(String code) async {
    final data = await _client.rpc(
      'resolve_call_link',
      params: {'target_code': code},
    );
    return CallLinkResolution.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

/// Used before Supabase is set up.
class UninitializedCallLinksRepository implements CallLinksRepository {
  const UninitializedCallLinksRepository();

  @override
  Future<CallLink> create(CallLinkTarget target, CallLinkExpiry expiry) {
    throw StateError('Supabase is not initialized.');
  }

  @override
  Future<List<CallLink>> list(CallLinkTarget target) async => const [];

  @override
  Future<void> revoke(String code) async {}

  @override
  Future<CallLinkResolution> resolve(String code) {
    throw StateError('Supabase is not initialized.');
  }
}
