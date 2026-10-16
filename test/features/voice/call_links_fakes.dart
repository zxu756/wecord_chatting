import 'package:wecord/features/voice/call_links/call_links.dart';

/// Call links kept in memory.
class FakeCallLinksRepository implements CallLinksRepository {
  final created = <({CallLinkTarget target, CallLinkExpiry expiry})>[];
  final revoked = <String>[];
  final links = <String, CallLink>{};
  final _targets = <String, CallLinkTarget>{};
  var _next = 0;

  /// What [resolve] answers per code; unknown codes are not found.
  final resolutions = <String, CallLinkResolution>{};
  final resolved = <String>[];

  /// Thrown by [create] and [resolve] when set.
  Object? error;

  @override
  Future<CallLink> create(CallLinkTarget target, CallLinkExpiry expiry) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    created.add((target: target, expiry: expiry));
    final code = 'code${(_next++).toString().padLeft(8, '0')}';
    final link = CallLink(
      code: code,
      createdAt: DateTime.utc(2026, 10, 17, 9),
      expiresAt: switch (expiry) {
        CallLinkExpiry.day => DateTime.now().toUtc().add(
          const Duration(hours: 24),
        ),
        CallLinkExpiry.week => DateTime.now().toUtc().add(
          const Duration(days: 7),
        ),
        CallLinkExpiry.never => null,
      },
    );
    links[code] = link;
    _targets[code] = target;
    return link;
  }

  @override
  Future<List<CallLink>> list(CallLinkTarget target) async {
    return [
      for (final entry in links.entries)
        if (_targets[entry.key] == target) entry.value,
    ];
  }

  @override
  Future<void> revoke(String code) async {
    revoked.add(code);
    links.remove(code);
  }

  @override
  Future<CallLinkResolution> resolve(String code) async {
    resolved.add(code);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return resolutions[code] ??
        const CallLinkResolution.problem(CallLinkProblem.notFound);
  }
}
