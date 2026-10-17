import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Whose QR code it is, as scanning it shows.
@immutable
class QrProfile {
  const QrProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory QrProfile.fromJson(Map<String, dynamic> json) {
    return QrProfile(
      id: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
}

/// A group's QR code and when it stops working.
@immutable
class GroupQrCode {
  const GroupQrCode({
    required this.code,
    required this.createdAt,
    required this.expiresAt,
  });

  factory GroupQrCode.fromJson(Map<String, dynamic> json) {
    return GroupQrCode(
      code: json['code'] as String,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// What a group QR code can do right now.
enum GroupQrState {
  ok,
  expired,
  notFound;

  static GroupQrState fromWire(Object? value) => switch (value) {
    'ok' => ok,
    'expired' => expired,
    _ => notFound,
  };
}

/// The join page: the group a code leads to.
@immutable
class GroupQrPreview {
  const GroupQrPreview({
    required this.state,
    this.conversationId,
    this.title,
    this.avatarUrl,
    this.memberCount = 0,
    this.expiresAt,
    this.isMember = false,
  });

  factory GroupQrPreview.fromJson(Map<String, dynamic> json) {
    return GroupQrPreview(
      state: GroupQrState.fromWire(json['state']),
      conversationId: json['conversation_id'] as String?,
      title: json['title'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(
        json['expires_at'] as String? ?? '',
      )?.toUtc(),
      isMember: json['is_member'] == true,
    );
  }

  final GroupQrState state;
  final String? conversationId;
  final String? title;
  final String? avatarUrl;
  final int memberCount;
  final DateTime? expiresAt;

  /// The current user is already in the group.
  final bool isMember;

  /// The page can show the group (the code works, or they are in it).
  bool get canShow => state == GroupQrState.ok || isMember;
}

/// How joining a group by its code went.
@immutable
class GroupQrJoin {
  const GroupQrJoin({required this.state, this.conversationId});

  factory GroupQrJoin.fromJson(Map<String, dynamic> json) {
    return GroupQrJoin(
      state: switch (json['state']) {
        'joined' => GroupQrJoinState.joined,
        'already_member' => GroupQrJoinState.alreadyMember,
        'expired' => GroupQrJoinState.expired,
        _ => GroupQrJoinState.notFound,
      },
      conversationId: json['conversation_id'] as String?,
    );
  }

  final GroupQrJoinState state;
  final String? conversationId;

  bool get inGroup =>
      state == GroupQrJoinState.joined ||
      state == GroupQrJoinState.alreadyMember;
}

enum GroupQrJoinState { joined, alreadyMember, expired, notFound }

/// The server side of QR codes (migrations 202610180030 and 202610180031).
abstract interface class QrRepository {
  /// The current user's code, made on first use.
  Future<String> myCode();

  /// Replaces the current user's code; the old one stops working.
  Future<String> resetMyCode();

  /// Who [code] belongs to; null when it leads nowhere (unknown, reset,
  /// blocked or a deleted account).
  Future<QrProfile?> resolveUser(String code);

  /// The group's QR code (made again once it ran out, or when [refresh]);
  /// only owners and admins may.
  Future<GroupQrCode> groupCode(String conversationId, {bool refresh = false});

  Future<GroupQrPreview> previewGroup(String code);

  Future<GroupQrJoin> joinGroup(String code);
}

final qrRepositoryProvider = Provider<QrRepository>((ref) {
  try {
    return SupabaseQrRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedQrRepository();
  }
});

class SupabaseQrRepository implements QrRepository {
  const SupabaseQrRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> myCode() async {
    return await _client.rpc('get_my_qr_code') as String;
  }

  @override
  Future<String> resetMyCode() async {
    return await _client.rpc('reset_my_qr_code') as String;
  }

  @override
  Future<QrProfile?> resolveUser(String code) async {
    final data = await _client.rpc(
      'resolve_user_qr_code',
      params: {'qr_code': code},
    );
    final rows = data as List;
    if (rows.isEmpty) {
      return null;
    }
    return QrProfile.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<GroupQrCode> groupCode(
    String conversationId, {
    bool refresh = false,
  }) async {
    final data = await _client.rpc(
      'get_group_qr',
      params: {'target_conversation_id': conversationId, 'refresh': refresh},
    );
    return GroupQrCode.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<GroupQrPreview> previewGroup(String code) async {
    final data = await _client.rpc(
      'preview_group_qr',
      params: {'qr_code': code},
    );
    return GroupQrPreview.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<GroupQrJoin> joinGroup(String code) async {
    final data = await _client.rpc(
      'join_group_by_qr',
      params: {'qr_code': code},
    );
    return GroupQrJoin.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

/// Used before Supabase is set up.
class UninitializedQrRepository implements QrRepository {
  const UninitializedQrRepository();

  Never _fail() => throw StateError('Supabase is not initialized.');

  @override
  Future<String> myCode() async => _fail();

  @override
  Future<String> resetMyCode() async => _fail();

  @override
  Future<QrProfile?> resolveUser(String code) async => _fail();

  @override
  Future<GroupQrCode> groupCode(
    String conversationId, {
    bool refresh = false,
  }) async => _fail();

  @override
  Future<GroupQrPreview> previewGroup(String code) async => _fail();

  @override
  Future<GroupQrJoin> joinGroup(String code) async => _fail();
}

/// The current user's QR code. Read again after a reset.
final myQrCodeProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(qrRepositoryProvider).myCode();
});
