import 'package:wecord/features/error_reports/error_description.dart';
import 'package:wecord/features/local_search/local_message_search.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';

/// Message search that asks the server and, when the server cannot be
/// reached, answers from the messages saved on this device (L3). While
/// there is a connection the server's answer is the only one: a local
/// answer is never mixed into it, and a server that answers with an error
/// (as opposed to not answering) shows that error as before.
class OfflineFallbackSearchRepository implements MessageSearchRepository {
  const OfflineFallbackSearchRepository({
    required this.online,
    required this.local,
    required this.deviceOffline,
  });

  final MessageSearchRepository online;
  final LocalMessageSearch local;

  /// The device has no network at all: no use asking the server.
  final bool Function() deviceOffline;

  Future<T> _either<T>(
    Future<T> Function() fromServer,
    Future<T> Function() fromDevice,
  ) async {
    if (deviceOffline()) {
      return fromDevice();
    }
    try {
      return await fromServer();
    } on Object catch (error) {
      if (!isNetworkError(error)) {
        rethrow;
      }
      return fromDevice();
    }
  }

  @override
  Future<SearchPage> search(MessageSearchRequest request) {
    final cursor = request.cursor;
    if (cursor != null) {
      // The next page goes where the first one came from: the device's own
      // cursor is a position in its own list, the server's is not.
      return cursor.containsKey('local_offset')
          ? local.search(request)
          : online.search(request);
    }
    return _either(() => online.search(request), () => local.search(request));
  }

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) => _either(
    () => online.context(messageId, before: before, after: after),
    () => local.context(messageId, before: before, after: after),
  );

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) => _either(
    () => online.suggestPeople(prefix, scope: scope, limit: limit),
    () => local.suggestPeople(prefix, scope: scope, limit: limit),
  );

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) => _either(
    () => online.suggestPlaces(prefix, scope: scope, limit: limit),
    () => local.suggestPlaces(prefix, scope: scope, limit: limit),
  );
}
