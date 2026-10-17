import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the "Copy call link" sheet for [target]: pick how long the link
/// works, copy a new one, and copy or revoke the ones made before.
Future<void> showCallLinkSheet(
  BuildContext context, {
  required CallLinkTarget target,
  required String name,
}) {
  return showWeCordSheet<void>(
    context,
    builder: (context, scrollController) =>
        CallLinkSheet(target: target, name: name),
  );
}

/// The sheet's content (see [showCallLinkSheet]).
class CallLinkSheet extends ConsumerStatefulWidget {
  const CallLinkSheet({required this.target, required this.name, super.key});

  final CallLinkTarget target;

  /// The call's or channel's name, shown under the title.
  final String name;

  @override
  ConsumerState<CallLinkSheet> createState() => _CallLinkSheetState();
}

class _CallLinkSheetState extends ConsumerState<CallLinkSheet> {
  var _expiry = CallLinkExpiry.week;
  var _busy = false;
  String? _copiedCode;
  String? _error;
  late Future<List<CallLink>> _links = _load();

  Future<List<CallLink>> _load() {
    return ref.read(callLinksRepositoryProvider).list(widget.target);
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await ref
          .read(callLinksRepositoryProvider)
          .create(widget.target, _expiry);
      await Clipboard.setData(ClipboardData(text: callLinkUrl(link.code)));
      if (!mounted) {
        return;
      }
      WeCordHaptics.light();
      setState(() {
        _copiedCode = link.code;
        _links = _load();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr('Could not create the call link. Try again.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy(CallLink link) async {
    await Clipboard.setData(ClipboardData(text: callLinkUrl(link.code)));
    if (mounted) {
      setState(() => _copiedCode = link.code);
    }
  }

  Future<void> _revoke(CallLink link) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(callLinksRepositoryProvider).revoke(link.code);
      if (mounted) {
        setState(() {
          if (_copiedCode == link.code) {
            _copiedCode = null;
          }
          _links = _load();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Could not turn the link off. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                tr('Call link'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('Link works for'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  WeCordSegmented<CallLinkExpiry>(
                    expand: true,
                    selected: _expiry,
                    onChanged: _busy
                        ? null
                        : (expiry) => setState(() => _expiry = expiry),
                    semanticLabel: tr('Link works for'),
                    segments: [
                      WeCordSegment(
                        key: const ValueKey('call-link-expiry-day'),
                        value: CallLinkExpiry.day,
                        label: tr('24 hours'),
                      ),
                      WeCordSegment(
                        key: const ValueKey('call-link-expiry-week'),
                        value: CallLinkExpiry.week,
                        label: tr('7 days'),
                      ),
                      WeCordSegment(
                        key: const ValueKey('call-link-expiry-never'),
                        value: CallLinkExpiry.never,
                        label: tr('No expiry'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  WeCordButton(
                    key: const ValueKey('call-link-create'),
                    variant: WeCordButtonVariant.accent,
                    icon: _copiedCode != null && !_busy
                        ? Icons.check_rounded
                        : Icons.link_rounded,
                    label: _copiedCode != null && !_busy
                        ? tr('Link copied')
                        : tr('Copy call link'),
                    loading: _busy,
                    onPressed: _busy ? null : _create,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Anyone who can join this call can use the link. Everyone '
                "else sees a page saying they don't have access.",
              ),
              style: TextStyle(fontSize: 13, color: c.muted, height: 1.35),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: c.dangerText),
                ),
              ),
            ],
            FutureBuilder<List<CallLink>>(
              future: _links,
              builder: (context, snapshot) {
                final links = snapshot.data ?? const <CallLink>[];
                if (links.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsSectionHeader(tr('Your active links')),
                    SettingsGroup(
                      color: c.well,
                      children: [
                        for (final link in links)
                          SettingsRow(
                            key: ValueKey('call-link-${link.code}'),
                            icon: Icons.link_rounded,
                            tone: SettingsTone.accent,
                            title: callLinkPath(link.code),
                            subtitle: callLinkExpiryLabel(link.expiresAt),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WeCordIconButton(
                                  tooltip: _copiedCode == link.code
                                      ? tr('Link copied')
                                      : tr('Copy this link'),
                                  icon: _copiedCode == link.code
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  size: 34,
                                  variant: WeCordButtonVariant.ghost,
                                  onPressed: () => unawaited(_copy(link)),
                                ),
                                WeCordIconButton(
                                  key: ValueKey(
                                    'call-link-revoke-${link.code}',
                                  ),
                                  tooltip: tr('Turn this link off'),
                                  icon: Icons.link_off_rounded,
                                  size: 34,
                                  variant: WeCordButtonVariant.ghost,
                                  onPressed: _busy
                                      ? null
                                      : () => unawaited(_revoke(link)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Never expires", "Expires in 5 hours", "Expires in 3 days".
String callLinkExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) {
    return tr('Never expires');
  }
  final left = expiresAt.difference((now ?? DateTime.now()).toUtc());
  if (left.inHours < 1) {
    return tr('Expires within the hour');
  }
  if (left.inHours < 24) {
    return left.inHours == 1
        ? tr('Expires in 1 hour')
        : tr('Expires in {count} hours', {'count': left.inHours});
  }
  return left.inDays == 1
      ? tr('Expires in 1 day')
      : tr('Expires in {count} days', {'count': left.inDays});
}
