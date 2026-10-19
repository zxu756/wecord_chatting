import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_ops_models.dart';
import 'package:wecord/features/admin/admin_ops_repository.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The console's "Notices" tab (K6): the official notices that every
/// person's Notifications show as WeCord team cards. Owners and moderators
/// publish and take back; support staff read.
class AdminNoticesView extends ConsumerStatefulWidget {
  const AdminNoticesView({this.pageSize = 30, this.now, super.key});

  final int pageSize;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AdminNoticesView> createState() => _AdminNoticesViewState();
}

class _AdminNoticesViewState extends ConsumerState<AdminNoticesView> {
  final _notices = <AdminNotice>[];
  var _loading = false;
  var _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _reload() async {
    setState(() {
      _notices.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(adminOpsRepositoryProvider)
          .listNotices(
            before: _notices.isEmpty ? null : _notices.last.publishedAt,
            pageSize: widget.pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _notices.addAll(page);
        _hasMore = page.length >= widget.pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _compose() async {
    final draft = await showCircleDialog<_NoticeDraft>(
      context,
      builder: (context) => const _NoticeDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    final sure = await confirmCircleAction(
      context,
      title: tr('Publish to everybody?'),
      message: draft.push
          ? tr(
              'Every person will see this in Notifications, and devices with '
              'push get one notification. You cannot send another push for a '
              'day.',
            )
          : tr('Every person will see this in Notifications.'),
      confirmLabel: tr('Publish'),
      destructive: false,
    );
    if (!sure || !mounted) {
      return;
    }
    try {
      await ref
          .read(adminOpsRepositoryProvider)
          .publishNotice(
            titleEn: draft.titleEn,
            titleZh: draft.titleZh,
            bodyEn: draft.bodyEn,
            bodyZh: draft.bodyZh,
            push: draft.push,
          );
      await _reload();
    } catch (error) {
      if (mounted) {
        _say(adminErrorText(error));
      }
    }
  }

  Future<void> _retract(AdminNotice notice) async {
    final sure = await confirmCircleAction(
      context,
      title: tr('Take this notice back?'),
      message: tr(
        'It disappears from every Notifications page. A push that has not '
        'gone out yet is cancelled.',
      ),
      confirmLabel: tr('Take back'),
    );
    if (!sure || !mounted) {
      return;
    }
    try {
      await ref.read(adminOpsRepositoryProvider).retractNotice(notice.id);
      await _reload();
    } catch (error) {
      if (mounted) {
        _say(adminErrorText(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(adminRoleProvider).value;
    final canPublish = role != null && role.canSanction;
    final now = widget.now?.call() ?? DateTime.now();
    final compose = canPublish
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: WeCordButton(
                key: const ValueKey('admin-notice-new'),
                label: tr('New notice'),
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.onPaper,
                onPressed: () => unawaited(_compose()),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (_notices.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the notices.'),
          message: adminErrorText(_error!),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _reload,
          ),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          compose,
          Expanded(
            child: CircleEmptyState(
              icon: Icons.campaign_outlined,
              title: tr('No notices yet.'),
              message: tr('A notice shows in every person’s Notifications.'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compose,
        Expanded(
          child: ListView.builder(
            key: const ValueKey('admin-notice-list'),
            padding: circlePagePadding(context),
            itemCount: _notices.length + 1,
            itemBuilder: (context, index) {
              if (index == _notices.length) {
                if (_error != null || _hasMore) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : WeCordButton(
                              label: _error != null
                                  ? tr('Could not load more. Retry')
                                  : tr('Load more'),
                              variant: WeCordButtonVariant.onPaper,
                              size: WeCordButtonSize.small,
                              onPressed: _loadMore,
                            ),
                    ),
                  );
                }
                return const SizedBox(height: 16);
              }
              final notice = _notices[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NoticeTile(
                  notice: notice,
                  now: now,
                  onRetract: canPublish && !notice.isRetracted
                      ? () => unawaited(_retract(notice))
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.notice,
    required this.now,
    required this.onRetract,
  });

  final AdminNotice notice;
  final DateTime now;
  final VoidCallback? onRetract;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tags = <Widget>[
      if (notice.isRetracted)
        AdminStateTag(label: tr('Taken back'), tone: SettingsTone.warning),
      if (notice.push && !notice.isRetracted)
        AdminStateTag(
          label: notice.pushDone ? tr('Push sent') : tr('Push waiting'),
        ),
    ];
    return Container(
      key: ValueKey('admin-notice-${notice.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            notice.title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: notice.isRetracted ? c.muted : c.ink,
            ),
          ),
          if (notice.body.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              notice.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: tags),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('{time} · read by {read} · dismissed by {dismissed}', {
                    'time': formatAuditTime(notice.publishedAt, now: now),
                    'read': notice.readCount,
                    'dismissed': notice.dismissedCount,
                  }),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.subtle,
                  ),
                ),
              ),
              if (onRetract != null)
                WeCordButton(
                  key: ValueKey('admin-notice-retract-${notice.id}'),
                  label: tr('Take back'),
                  size: WeCordButtonSize.small,
                  variant: WeCordButtonVariant.onPaper,
                  onPressed: onRetract,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoticeDraft {
  const _NoticeDraft({
    required this.titleEn,
    required this.titleZh,
    required this.bodyEn,
    required this.bodyZh,
    required this.push,
  });

  final String titleEn;
  final String titleZh;
  final String bodyEn;
  final String bodyZh;
  final bool push;
}

class _NoticeDialog extends StatefulWidget {
  const _NoticeDialog();

  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> {
  final _titleEn = TextEditingController();
  final _titleZh = TextEditingController();
  final _bodyEn = TextEditingController();
  final _bodyZh = TextEditingController();
  var _push = false;

  @override
  void dispose() {
    _titleEn.dispose();
    _titleZh.dispose();
    _bodyEn.dispose();
    _bodyZh.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleEn.text.trim().isNotEmpty || _titleZh.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleDialog(
      title: tr('New notice'),
      message: tr(
        'Write it in both languages if you can. Each person sees the one in '
        'their app language.',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('admin-notice-title-en'),
            controller: _titleEn,
            label: tr('Title (English)'),
            maxLength: 120,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            fieldKey: const ValueKey('admin-notice-body-en'),
            controller: _bodyEn,
            label: tr('Text (English)'),
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            fieldKey: const ValueKey('admin-notice-title-zh'),
            controller: _titleZh,
            label: tr('Title (Chinese)'),
            maxLength: 120,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            fieldKey: const ValueKey('admin-notice-body-zh'),
            controller: _bodyZh,
            label: tr('Text (Chinese)'),
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Also send one push'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      tr('Once, and not more than one push a day.'),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              WeCordSwitch(
                key: const ValueKey('admin-notice-push'),
                value: _push,
                semanticLabel: tr('Also send one push'),
                onChanged: (value) => setState(() => _push = value),
              ),
            ],
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('admin-notice-publish'),
          label: tr('Publish'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  _NoticeDraft(
                    titleEn: _titleEn.text,
                    titleZh: _titleZh.text,
                    bodyEn: _bodyEn.text,
                    bodyZh: _bodyZh.text,
                    push: _push,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
