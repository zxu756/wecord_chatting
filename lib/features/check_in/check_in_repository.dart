import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chain/chain_sync.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/features/forms/form_repository.dart'
    show formImageExtension, maxFormImageBytes;
import 'package:wecord/shared/api/supabase_providers.dart';

/// The most a check-in picture may weigh.
const maxCheckInImageBytes = maxFormImageBytes;

/// Check-ins on the server: the `*_check_in*` functions of migrations
/// 202610280500 to 202610280530.
abstract interface class CheckInRepository {
  /// Posts a check-in card into [conversationId]; the id of the card message.
  Future<String> create(String conversationId, CheckInDraft draft);

  /// The card's short form.
  Future<CheckInSnapshot> get(String checkInId);

  /// The page's form: the card, today's list, the longest runs, my days.
  Future<CheckInDetail> detail(String checkInId);

  /// Another day's list.
  Future<CheckInDay> day(String checkInId, DateTime day);

  /// Checks in for today (or changes today's note and picture).
  Future<CheckInResult> submit(
    String checkInId, {
    String note = '',
    FormImageAnswer? photo,
  });

  /// Takes today's check-in back.
  Future<void> undo(String checkInId);

  Future<void> setClosed(String checkInId, {required bool closed});

  /// Uploads a picture into the chat's check-in folder.
  Future<FormImageAnswer> uploadPhoto({
    required String conversationId,
    required String checkInId,
    required ChatImageUpload image,
  });

  /// A link that shows a picture for a while.
  Future<String> imageUrl(FormImageAnswer image);

  /// Fires whenever the check-in changes (Realtime).
  Stream<void> changes(String checkInId);
}

class SupabaseCheckInRepository implements CheckInRepository {
  SupabaseCheckInRepository(this._client) {
    _reads = ChainReadBatcher<CheckInSnapshot>(_readMany);
    _hub = ChainChangeHub(_openChannel);
  }

  final SupabaseClient _client;

  /// Cards asked for in the same moment are read with one request.
  late final ChainReadBatcher<CheckInSnapshot> _reads;

  /// One Realtime channel per conversation for all its check-in cards.
  late final ChainChangeHub _hub;

  void dispose() => _hub.dispose();

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw CheckInException.fromPostgrest(error);
    }
  }

  Map<String, dynamic> _object(Object? data) {
    return Map<String, dynamic>.from(data! as Map);
  }

  @override
  Future<String> create(String conversationId, CheckInDraft draft) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'create_check_in',
        params: {
          'target_conversation_id': conversationId,
          'check_in_title': draft.title.trim(),
          'check_in_description': draft.description.trim().isEmpty
              ? null
              : draft.description.trim(),
          'check_in_time_zone': draft.timeZone,
          'check_in_remind_minute': draft.remindMinute,
          'check_in_ends_on': draft.endsOn == null
              ? null
              : checkInDateText(draft.endsOn!),
        },
      );
      final messageId = _object(data)['message_id'] as String;
      try {
        await _client.functions.invoke('push', body: {'message_id': messageId});
      } on Object {
        // Push is a courtesy; the card is already in the chat.
      }
      return messageId;
    });
  }

  @override
  Future<CheckInSnapshot> get(String checkInId) {
    return _guard(() async {
      try {
        return await _reads.read(checkInId);
      } on ChainNotAvailable {
        throw const CheckInException(CheckInFailureKind.gone);
      }
    });
  }

  Future<Map<String, CheckInSnapshot>> _readMany(List<String> ids) async {
    final data = await _client.rpc<Object?>(
      'get_check_ins',
      params: {'target_check_in_ids': ids},
    );
    final snapshots = <String, CheckInSnapshot>{
      for (final item in data! as List)
        if (item is Map)
          (item['id'] as String): CheckInSnapshot.fromJson(
            Map<String, dynamic>.from(item),
          ),
    };
    snapshots.forEach(
      (id, snapshot) => _hub.learn(id, snapshot.conversationId),
    );
    return snapshots;
  }

  @override
  Future<CheckInDetail> detail(String checkInId) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'get_check_in',
        params: {'target_check_in_id': checkInId},
      );
      final detail = CheckInDetail.fromJson(_object(data));
      _hub.learn(checkInId, detail.snapshot.conversationId);
      return detail;
    });
  }

  @override
  Future<CheckInDay> day(String checkInId, DateTime day) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'get_check_in_day',
        params: {
          'target_check_in_id': checkInId,
          'target_day': checkInDateText(day),
        },
      );
      return CheckInDay.fromJson(_object(data));
    });
  }

  @override
  Future<CheckInResult> submit(
    String checkInId, {
    String note = '',
    FormImageAnswer? photo,
  }) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'submit_check_in',
        params: {
          'target_check_in_id': checkInId,
          'entry_note': note.trim(),
          'entry_photo': photo?.toJson(),
        },
      );
      return CheckInResult.fromJson(_object(data));
    });
  }

  @override
  Future<void> undo(String checkInId) {
    return _guard(
      () => _client.rpc<Object?>(
        'undo_check_in',
        params: {'target_check_in_id': checkInId},
      ),
    );
  }

  @override
  Future<void> setClosed(String checkInId, {required bool closed}) {
    return _guard(
      () => _client.rpc<Object?>(
        'set_check_in_closed',
        params: {'target_check_in_id': checkInId, 'closed': closed},
      ),
    );
  }

  static final _random = math.Random.secure();

  @override
  Future<FormImageAnswer> uploadPhoto({
    required String conversationId,
    required String checkInId,
    required ChatImageUpload image,
  }) async {
    const bucket = 'chat-images';
    final seed =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    final path =
        '$conversationId/check-ins/$checkInId/$seed.${formImageExtension(image.mimeType)}';
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(contentType: image.mimeType),
          )
          .timeout(const Duration(seconds: 60));
    } on Object {
      throw const CheckInException(CheckInFailureKind.imageUpload);
    }
    return FormImageAnswer(
      bucket: bucket,
      path: path,
      mimeType: image.mimeType,
    );
  }

  @override
  Future<String> imageUrl(FormImageAnswer image) {
    return _client.storage.from(image.bucket).createSignedUrl(image.path, 3600);
  }

  @override
  Stream<void> changes(String checkInId) => _hub.changes(checkInId);

  /// The conversation's channel (`check-ins:<conversation id>`), with the
  /// changes of its check-ins.
  FutureOr<void> Function() _openChannel(
    String conversationId,
    void Function(String? checkInId) onChange,
  ) {
    final channel = _client
        .channel('check-ins:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'check_in_boards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            onChange(record['id'] as String?);
          },
        )
        .subscribe();
    return () => _client.removeChannel(channel);
  }
}

class _UninitializedCheckInRepository implements CheckInRepository {
  const _UninitializedCheckInRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized before using check-ins.');

  @override
  Future<String> create(String conversationId, CheckInDraft draft) => _fail();

  @override
  Future<CheckInSnapshot> get(String checkInId) => _fail();

  @override
  Future<CheckInDetail> detail(String checkInId) => _fail();

  @override
  Future<CheckInDay> day(String checkInId, DateTime day) => _fail();

  @override
  Future<CheckInResult> submit(
    String checkInId, {
    String note = '',
    FormImageAnswer? photo,
  }) => _fail();

  @override
  Future<void> undo(String checkInId) => _fail();

  @override
  Future<void> setClosed(String checkInId, {required bool closed}) => _fail();

  @override
  Future<FormImageAnswer> uploadPhoto({
    required String conversationId,
    required String checkInId,
    required ChatImageUpload image,
  }) => _fail();

  @override
  Future<String> imageUrl(FormImageAnswer image) => _fail();

  @override
  Stream<void> changes(String checkInId) => const Stream.empty();
}

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  try {
    final repository = SupabaseCheckInRepository(
      ref.watch(supabaseClientProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  } on ProviderException {
    return const _UninitializedCheckInRepository();
  }
});

/// A check-in's card, live: reads again (at most every 400 ms) when anyone
/// checks in, and when the board's own day turns over.
final checkInProvider = FutureProvider.autoDispose
    .family<CheckInSnapshot, String>((ref, checkInId) async {
      final repository = ref.watch(checkInRepositoryProvider);
      Timer? pending;
      final subscription = repository.changes(checkInId).listen((_) {
        pending ??= Timer(const Duration(milliseconds: 400), () {
          pending = null;
          ref.invalidateSelf();
        });
      }, onError: (Object _) {});
      ref.onDispose(() {
        pending?.cancel();
        unawaited(subscription.cancel());
      });
      return repository.get(checkInId);
    });

/// The check-in page's data. Not a batch: opened from the card, read again
/// when the check-in changes.
final checkInDetailProvider = FutureProvider.autoDispose
    .family<CheckInDetail, String>((ref, checkInId) {
      final repository = ref.watch(checkInRepositoryProvider);
      Timer? pending;
      final subscription = repository.changes(checkInId).listen((_) {
        pending ??= Timer(const Duration(milliseconds: 600), () {
          pending = null;
          ref.invalidateSelf();
        });
      }, onError: (Object _) {});
      ref.onDispose(() {
        pending?.cancel();
        unawaited(subscription.cancel());
      });
      return repository.detail(checkInId);
    });

/// A link that shows a check-in picture for a while.
final checkInImageUrlProvider = FutureProvider.autoDispose
    .family<String, FormImageAnswer>((ref, image) {
      return ref.watch(checkInRepositoryProvider).imageUrl(image);
    });
