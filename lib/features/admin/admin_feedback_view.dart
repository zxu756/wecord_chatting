import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_feedback_screen.dart';
import 'package:wecord/features/admin/admin_ops_models.dart';
import 'package:wecord/features/admin/admin_ops_repository.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The console's "Feedback" tab (K7): what people wrote in Settings,
/// Feedback and help, newest first. Open ones by default; tapping one opens
/// it with its screenshot, where the team replies.
class AdminFeedbackView extends ConsumerStatefulWidget {
  const AdminFeedbackView({this.pageSize = 30, this.now, super.key});

  final int pageSize;

  /// The current time, for tests.
  final DateTime Function()? now;

  @override
  ConsumerState<AdminFeedbackView> createState() => _AdminFeedbackViewState();
}

class _AdminFeedbackViewState extends ConsumerState<AdminFeedbackView> {
  final _items = <AdminFeedback>[];
  var _status = FeedbackQueueStatus.open;
  var _loading = false;
  var _hasMore = true;
  Object? _error;

  /// Bumped on every reload, so pages of an old filter are dropped.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  void _reload({FeedbackQueueStatus? status}) {
    setState(() {
      _status = status ?? _status;
      _generation += 1;
      _items.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) {
      return;
    }
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(adminOpsRepositoryProvider)
          .listFeedback(
            status: _status,
            before: _items.isEmpty ? null : _items.last.createdAt,
            pageSize: widget.pageSize,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= widget.pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _open(AdminFeedback item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AdminFeedbackScreen(feedbackId: item.id),
      ),
    );
    // Answering or closing it changes the queue.
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in FeedbackQueueStatus.values)
                WeCordChip(
                  key: ValueKey('admin-feedback-${status.value}'),
                  label: status.label,
                  selected: _status == status,
                  onPaper: true,
                  onPressed: () {
                    if (status != _status) {
                      _reload(status: status);
                    }
                  },
                ),
            ],
          ),
        ),
        Expanded(child: _buildList(now)),
      ],
    );
  }

  Widget _buildList(DateTime now) {
    if (_items.isEmpty) {
      if (_error != null) {
        return CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not load the feedback.'),
          message: adminErrorText(_error!),
          action: WeCordButton(
            label: tr('Retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _loadMore,
          ),
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return CircleEmptyState(
        icon: Icons.inbox_outlined,
        title: _status == FeedbackQueueStatus.open
            ? tr('No open feedback.')
            : tr('No feedback here.'),
        message: _status == FeedbackQueueStatus.open
            ? tr('What people send from Settings shows up here.')
            : null,
      );
    }
    return ListView.builder(
      key: const ValueKey('admin-feedback-list'),
      padding: circlePagePadding(context),
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index == _items.length) {
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
        final item = _items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _FeedbackTile(
            item: item,
            now: now,
            onTap: () => unawaited(_open(item)),
          ),
        );
      },
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final AdminFeedback item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final who = item.username.isEmpty ? tr('Someone') : '@${item.username}';
    final meta = [
      who,
      if (item.appLabel.isNotEmpty) item.appLabel,
      formatAuditTime(item.createdAt, now: now),
    ].join(' · ');
    return WeCordPressable(
      key: ValueKey('admin-feedback-item-${item.id}'),
      onPressed: onTap,
      semanticLabel: '$meta. ${item.message}',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.panel)
                : c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsIconTile(
                icon: Icons.chat_bubble_outline_rounded,
                tone: SettingsTone.accent,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    if (item.hasScreenshot ||
                        item.repliedAt != null ||
                        item.closed) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item.hasScreenshot)
                            AdminStateTag(label: tr('Screenshot')),
                          if (item.repliedAt != null)
                            AdminStateTag(
                              label: tr('Answered'),
                              tone: SettingsTone.success,
                            ),
                          if (item.closed)
                            AdminStateTag(label: trIn('Feedback', 'Closed')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.faint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
