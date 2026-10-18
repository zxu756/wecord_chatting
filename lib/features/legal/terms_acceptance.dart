import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/legal/terms_checkbox.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether the signed-in person agreed to the Terms and Community Guidelines
/// and confirmed their age (profiles.accepted_terms_at, age_confirmed_at).
class TermsStatus {
  const TermsStatus({this.acceptedAt, this.ageConfirmedAt});

  factory TermsStatus.fromJson(Map<String, dynamic> json) => TermsStatus(
    acceptedAt: _time(json['accepted_terms_at']),
    ageConfirmedAt: _time(json['age_confirmed_at']),
  );

  final DateTime? acceptedAt;
  final DateTime? ageConfirmedAt;

  /// Both are on record.
  bool get isAccepted => acceptedAt != null && ageConfirmedAt != null;

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

class TermsRepository {
  const TermsRepository(this._rpc);

  final CircleRpc _rpc;

  Future<TermsStatus> status() async => TermsStatus.fromJson(
    rpcObject(await _rpc('get_my_terms_status', const {})),
  );

  /// Records that the person agrees and is old enough, now.
  Future<TermsStatus> accept() async =>
      TermsStatus.fromJson(rpcObject(await _rpc('accept_terms', const {})));
}

final termsRepositoryProvider = Provider<TermsRepository>(
  (ref) => TermsRepository(ref.watch(circleRpcProvider)),
);

/// What is on record for the signed-in person, or null when it cannot be
/// read (offline, no backend): then nobody is asked.
final termsStatusProvider = FutureProvider<TermsStatus?>((ref) async {
  final userId = ref.watch(
    authStateProvider.select((state) => state.value?.id),
  );
  if (userId == null) {
    return null;
  }
  try {
    return await ref.watch(termsRepositoryProvider).status();
  } on Object {
    return null;
  }
});

/// Asks people who signed up before the terms existed to agree, once per
/// app start, with a banner at the top that never blocks anything. Sits
/// above the signed-in app; shows nothing for anybody on record.
class TermsPromptHost extends ConsumerStatefulWidget {
  const TermsPromptHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TermsPromptHost> createState() => _TermsPromptHostState();
}

class _TermsPromptHostState extends ConsumerState<TermsPromptHost> {
  var _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(termsStatusProvider).value;
    final ask = status != null && !status.isAccepted && !_dismissed;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (ask)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TermsBanner(
                      onDismissed: () => setState(() => _dismissed = true),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The one-time question: tick the box, press Agree. "Not now" hides it
/// until the next start of the app.
class TermsBanner extends ConsumerStatefulWidget {
  const TermsBanner({required this.onDismissed, super.key});

  final VoidCallback onDismissed;

  @override
  ConsumerState<TermsBanner> createState() => _TermsBannerState();
}

class _TermsBannerState extends ConsumerState<TermsBanner> {
  var _checked = false;
  var _busy = false;
  String? _error;

  Future<void> _accept() async {
    if (!_checked || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(termsRepositoryProvider).accept();
      ref.invalidate(termsStatusProvider);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Could not save that. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('terms-banner'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: c.line),
          boxShadow: tokens.shadows.hairline,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr('Please review our terms'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'We have written down the Terms of Service and Community '
                'Guidelines. Please read them and confirm once.',
              ),
              style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
            ),
            const SizedBox(height: 10),
            TermsAgreementCheckbox(
              key: const ValueKey('terms-banner-checkbox'),
              value: _checked,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _checked = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: WeCordButton(
                    key: const ValueKey('terms-banner-later'),
                    label: tr('Not now'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _busy ? null : widget.onDismissed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: WeCordButton(
                    key: const ValueKey('terms-banner-agree'),
                    label: tr('Agree'),
                    loading: _busy,
                    onPressed: _checked && !_busy
                        ? () => unawaited(_accept())
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
