import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chain/chain_sync.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The most a picture answer may weigh.
const maxFormImageBytes = 10 * 1024 * 1024;

/// Forms on the server: the `*_form*` functions of migrations 202610230110
/// and 202610230120.
abstract interface class FormRepository {
  /// Posts a form card into [conversationId]; the id of the card message.
  Future<String> create(String conversationId, FormDraft draft);

  Future<FormSnapshot> get(String formId);

  /// Sends (or changes) the caller's answers.
  Future<FormSubmitResult> submit(String formId, FormAnswers answers);

  /// The answers, for whoever the form lets read them.
  Future<FormResults> results(String formId);

  Future<void> setClosed(String formId, {required bool closed});

  /// Nudges the members who have not answered; how many were reminded.
  Future<int> remind(FormSnapshot form);

  /// Uploads a picture for an answer into the conversation's folder.
  Future<FormImageAnswer> uploadImage({
    required String conversationId,
    required String formId,
    required ChatImageUpload image,
  });

  /// A link that shows a picture answer for a while.
  Future<String> imageUrl(FormImageAnswer image);

  /// Fires whenever the form changes (Realtime).
  Stream<void> changes(String formId);
}

class SupabaseFormRepository implements FormRepository {
  SupabaseFormRepository(this._client) {
    _reads = ChainReadBatcher<FormSnapshot>(_readMany);
    _hub = ChainChangeHub(_openChannel);
  }

  final SupabaseClient _client;

  /// Forms asked for in the same moment (every card on screen) are read with
  /// one request.
  late final ChainReadBatcher<FormSnapshot> _reads;

  /// One Realtime channel per conversation for all its form cards.
  late final ChainChangeHub _hub;

  void dispose() => _hub.dispose();

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw FormException.fromPostgrest(error);
    }
  }

  Map<String, dynamic> _object(Object? data) {
    return Map<String, dynamic>.from(data! as Map);
  }

  @override
  Future<String> create(String conversationId, FormDraft draft) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'create_form',
        params: {
          'target_conversation_id': conversationId,
          'form_title': draft.title.trim(),
          'form_description': draft.description.trim().isEmpty
              ? null
              : draft.description.trim(),
          'form_fields': [for (final field in draft.fields) field.toJson()],
          'form_settings': draft.settings.toJson(),
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
  Future<FormSnapshot> get(String formId) {
    return _guard(() async {
      try {
        return await _reads.read(formId);
      } on ChainNotAvailable {
        throw const FormException(FormFailureKind.gone);
      }
    });
  }

  Future<Map<String, FormSnapshot>> _readMany(List<String> formIds) async {
    final data = await _client.rpc<Object?>(
      'get_forms',
      params: {'target_form_ids': formIds},
    );
    final snapshots = <String, FormSnapshot>{
      for (final item in data! as List)
        if (item is Map)
          (item['id'] as String): FormSnapshot.fromJson(
            Map<String, dynamic>.from(item),
          ),
    };
    snapshots.forEach(
      (id, snapshot) => _hub.learn(id, snapshot.conversationId),
    );
    return snapshots;
  }

  @override
  Future<FormSubmitResult> submit(String formId, FormAnswers answers) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'submit_form_response',
        params: {
          'target_form_id': formId,
          'response_answers': answersToJson(answers),
        },
      );
      final result = data is Map ? data : const {};
      return FormSubmitResult(
        updated: result['updated'] == true,
        textHeld: result['text_held'] == true,
      );
    });
  }

  @override
  Future<FormResults> results(String formId) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'get_form_results',
        params: {'target_form_id': formId},
      );
      return FormResults.fromJson(_object(data));
    });
  }

  @override
  Future<void> setClosed(String formId, {required bool closed}) {
    return _guard(
      () => _client.rpc<Object?>(
        'set_form_closed',
        params: {'target_form_id': formId, 'closed': closed},
      ),
    );
  }

  @override
  Future<int> remind(FormSnapshot form) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'remind_form_unfilled',
        params: {'target_form_id': form.id},
      );
      final messageId = form.messageId;
      if (messageId != null) {
        try {
          await _client.functions.invoke(
            'push',
            body: {'read_reminder_message_id': messageId},
          );
        } on Object {
          // The reminder is in their notifications either way.
        }
      }
      return (data as num?)?.toInt() ?? 0;
    });
  }

  static final _random = math.Random.secure();

  @override
  Future<FormImageAnswer> uploadImage({
    required String conversationId,
    required String formId,
    required ChatImageUpload image,
  }) async {
    const bucket = 'chat-images';
    final seed =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    final path =
        '$conversationId/forms/$formId/$seed.${formImageExtension(image.mimeType)}';
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
      throw const FormException(FormFailureKind.imageUpload);
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
  Stream<void> changes(String formId) => _hub.changes(formId);

  /// The conversation's channel (`forms:<conversation id>`), with the
  /// changes of its forms.
  FutureOr<void> Function() _openChannel(
    String conversationId,
    void Function(String? formId) onChange,
  ) {
    final channel = _client
        .channel('forms:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'forms',
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

/// The file extension for a picture of this type: letters and digits only,
/// which is all a form's folder takes.
String formImageExtension(String mimeType) {
  return switch (mimeType.toLowerCase()) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    _ => 'jpg',
  };
}

class _UninitializedFormRepository implements FormRepository {
  const _UninitializedFormRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized before using forms.');

  @override
  Future<String> create(String conversationId, FormDraft draft) => _fail();

  @override
  Future<FormSnapshot> get(String formId) => _fail();

  @override
  Future<FormSubmitResult> submit(String formId, FormAnswers answers) =>
      _fail();

  @override
  Future<FormResults> results(String formId) => _fail();

  @override
  Future<void> setClosed(String formId, {required bool closed}) => _fail();

  @override
  Future<int> remind(FormSnapshot form) => _fail();

  @override
  Future<FormImageAnswer> uploadImage({
    required String conversationId,
    required String formId,
    required ChatImageUpload image,
  }) => _fail();

  @override
  Future<String> imageUrl(FormImageAnswer image) => _fail();

  @override
  Stream<void> changes(String formId) => const Stream.empty();
}

final formRepositoryProvider = Provider<FormRepository>((ref) {
  try {
    final repository = SupabaseFormRepository(
      ref.watch(supabaseClientProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  } on ProviderException {
    return const _UninitializedFormRepository();
  }
});

/// A form with the caller's own answer. Reads again (at most every 300 ms)
/// when anyone changes it, and when its deadline passes, so a card is always
/// live.
final formProvider = FutureProvider.autoDispose.family<FormSnapshot, String>((
  ref,
  formId,
) async {
  final repository = ref.watch(formRepositoryProvider);
  Timer? pending;
  final subscription = repository.changes(formId).listen((_) {
    pending ??= Timer(const Duration(milliseconds: 300), () {
      pending = null;
      ref.invalidateSelf();
    });
  }, onError: (Object _) {});
  ref.onDispose(() {
    pending?.cancel();
    unawaited(subscription.cancel());
  });
  final snapshot = await repository.get(formId);
  final deadline = snapshot.settings.deadline;
  if (deadline != null) {
    final wait = deadline.difference(DateTime.now());
    if (wait > Duration.zero && wait < const Duration(days: 7)) {
      final timer = Timer(
        wait + const Duration(seconds: 1),
        ref.invalidateSelf,
      );
      ref.onDispose(timer.cancel);
    }
  }
  return snapshot;
});

/// The answers of a form. Not live: opened from the card, and read again
/// when the person pulls or the form changes.
final formResultsProvider = FutureProvider.autoDispose
    .family<FormResults, String>((ref, formId) {
      final repository = ref.watch(formRepositoryProvider);
      final subscription = repository.changes(formId).listen((_) {
        ref.invalidateSelf();
      }, onError: (Object _) {});
      ref.onDispose(() => unawaited(subscription.cancel()));
      return repository.results(formId);
    });
