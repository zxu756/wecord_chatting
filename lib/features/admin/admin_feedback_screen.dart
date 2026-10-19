import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_ops_models.dart';
import 'package:wecord/features/admin/admin_ops_repository.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// One piece of feedback: who sent it, from which version and platform, the
/// text and the screenshot, the replies so far, and a box to reply. A reply
/// reaches only that person, as an official notice in their Notifications.
class AdminFeedbackScreen extends ConsumerStatefulWidget {
  const AdminFeedbackScreen({required this.feedbackId, super.key});

  final String feedbackId;

  @override
  ConsumerState<AdminFeedbackScreen> createState() =>
      _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends ConsumerState<AdminFeedbackScreen> {
  final _reply = TextEditingController();
  AdminFeedbackDetail? _detail;
  Object? _error;
  var _closeAfter = true;
  var _busy = false;
  Future<String>? _screenshot;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await ref
          .read(adminOpsRepositoryProvider)
          .feedbackDetail(widget.feedbackId);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _error = null;
        final path = detail.screenshotPath;
        _screenshot ??= path == null
            ? null
            : ref.read(adminOpsRepositoryProvider).screenshotUrl(path);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminOpsRepositoryProvider)
          .replyToFeedback(
            id: widget.feedbackId,
            text: text,
            closeAfter: _closeAfter,
          );
      _reply.clear();
      await _load();
      _say(tr('Reply sent.'));
    } catch (error) {
      _say(adminErrorText(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleClosed(AdminFeedbackDetail detail) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(adminOpsRepositoryProvider)
          .setFeedbackClosed(
            widget.feedbackId,
            closed: !detail.feedback.closed,
          );
      await _load();
    } catch (error) {
      _say(adminErrorText(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return CirclePageScaffold(
      title: tr('Feedback'),
      subtitle: detail == null
          ? null
          : (detail.feedback.username.isEmpty
                ? null
                : '@${detail.feedback.username}'),
      body: detail == null
          ? (_error != null
                ? CircleEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: tr('Could not load this feedback.'),
                    message: adminErrorText(_error!),
                    action: WeCordButton(
                      label: tr('Retry'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _load,
                    ),
                  )
                : const Center(child: CircularProgressIndicator()))
          : _buildBody(context, detail),
    );
  }

  Widget _buildBody(BuildContext context, AdminFeedbackDetail detail) {
    final c = context.tokens.colors;
    final item = detail.feedback;
    final who = item.displayName.isEmpty
        ? '@${item.username}'
        : '${item.displayName} (@${item.username})';
    return ListView(
      key: const ValueKey('admin-feedback-detail'),
      padding: circlePagePadding(context),
      children: [
        AdminSection(
          title: tr('From'),
          caption: [
            if (item.appLabel.isNotEmpty) item.appLabel,
            adminDateTime(item.createdAt),
          ].join(' · '),
          trailing: AdminStateTag(
            label: item.closed
                ? trIn('Feedback', 'Closed')
                : trIn('Admin', 'Open'),
            tone: item.closed ? SettingsTone.neutral : SettingsTone.accent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                who,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                item.message,
                key: const ValueKey('admin-feedback-message'),
                style: TextStyle(fontSize: 15, height: 1.45, color: c.ink),
              ),
            ],
          ),
        ),
        if (_screenshot != null) ...[
          const SizedBox(height: 12),
          AdminSection(
            title: tr('Screenshot'),
            child: FutureBuilder<String>(
              future: _screenshot,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    tr('Could not load the screenshot.'),
                    style: TextStyle(color: c.dangerText, fontSize: 14),
                  );
                }
                final url = snapshot.data;
                if (url == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: Image.network(
                      url,
                      key: const ValueKey('admin-feedback-screenshot'),
                      fit: BoxFit.contain,
                      semanticLabel: tr('Screenshot sent with the feedback'),
                      errorBuilder: (context, error, stack) => Text(
                        tr('Could not load the screenshot.'),
                        style: TextStyle(color: c.dangerText, fontSize: 14),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (detail.replies.isNotEmpty) ...[
          const SizedBox(height: 12),
          AdminSection(
            title: tr('Replies'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final reply in detail.replies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reply.body,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: reply.retracted ? c.muted : c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          adminDateTime(reply.publishedAt),
                          style: TextStyle(fontSize: 12, color: c.subtle),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        AdminSection(
          title: tr('Reply'),
          caption: tr(
            'Only this person sees it, as a notice from the WeCord team.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('admin-feedback-reply'),
                controller: _reply,
                hint: tr('Write a reply'),
                minLines: 3,
                maxLines: 8,
                maxLength: 1500,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Close after replying'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  WeCordSwitch(
                    key: const ValueKey('admin-feedback-close-after'),
                    value: _closeAfter,
                    semanticLabel: tr('Close after replying'),
                    onChanged: (value) => setState(() => _closeAfter = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              WeCordButton(
                key: const ValueKey('admin-feedback-send'),
                label: tr('Send reply'),
                variant: WeCordButtonVariant.primary,
                expand: true,
                onPressed: _busy || _reply.text.trim().isEmpty ? null : _send,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        WeCordButton(
          key: const ValueKey('admin-feedback-toggle'),
          label: item.closed ? tr('Open again') : tr('Close without replying'),
          variant: WeCordButtonVariant.onPaper,
          expand: true,
          onPressed: _busy ? null : () => unawaited(_toggleClosed(detail)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
