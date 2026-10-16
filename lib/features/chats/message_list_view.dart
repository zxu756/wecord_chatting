import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The chat's message list, built lazily around an anchor message.
///
/// Messages are given oldest first ([itemBuilder] takes that index). The
/// anchor message sits at scroll offset 0 and the list grows away from it
/// in both directions, through two slivers around the viewport's center:
/// chats (reversed, newest at the bottom) put the anchor and everything
/// older in the center sliver, growing up, and newer messages below it;
/// forum posts (read top down) put the anchor and everything newer in the
/// center, growing down, and older messages above it. Loading older or
/// newer pages only adds to the far ends of the slivers, so what is on
/// screen stays where it is. Children are found by key when messages are
/// added ([indexOfMessage]), so their state and layout are reused.
class MessageListView extends StatelessWidget {
  const MessageListView({
    required this.controller,
    required this.forum,
    required this.itemCount,
    required this.anchorIndex,
    required this.indexOfMessage,
    required this.messageIdOfKey,
    required this.itemBuilder,
    required this.viewportHeight,
    required this.sidePadding,
    required this.topPadding,
    required this.bottomPadding,
    this.loadingOlder = false,
    this.loadingNewer = false,
    this.onScrollEnd,
    super.key,
  });

  final ScrollController controller;

  /// A forum post: oldest at the top, not reversed.
  final bool forum;
  final int itemCount;

  /// Where the anchor message is (oldest-first index).
  final int anchorIndex;

  /// The oldest-first index of a message by id.
  final int? Function(String messageId) indexOfMessage;

  /// The message id a child's key stands for.
  final String? Function(Key key) messageIdOfKey;
  final Widget Function(int index) itemBuilder;
  final double viewportHeight;
  final double sidePadding;

  /// Clear of the floating header (phones) at the top, and of the
  /// composer at the bottom.
  final double topPadding;
  final double bottomPadding;
  final bool loadingOlder;
  final bool loadingNewer;

  /// The list stopped scrolling.
  final VoidCallback? onScrollEnd;

  static const _centerKey = ValueKey('chat-message-list-center');

  @override
  Widget build(BuildContext context) {
    final anchor = math.max(0, math.min(anchorIndex, itemCount - 1));
    // Offset 0 is the anchor's edge: just clear of the composer in chats
    // and of the header in forum posts.
    final homePadding = forum ? topPadding : bottomPadding;
    final viewport = viewportHeight.isFinite && viewportHeight > 0
        ? viewportHeight
        : 600.0;
    final anchorFraction = (homePadding / viewport).clamp(0.0, 0.9);
    // The gap at the home edge equals the anchor's offset, so a list
    // without messages past the anchor starts exactly at offset 0.
    final homeGap = anchorFraction * viewport;
    final farGap = forum ? bottomPadding : topPadding;

    // Chats: center = anchor and older (index 0 is the anchor), before =
    // newer than the anchor (index 0 is just after it). Forum posts:
    // center = anchor and newer, before = older than the anchor.
    final centerCount = forum ? itemCount - anchor : anchor + 1;
    final beforeCount = itemCount - centerCount;
    int centerToIndex(int i) => forum ? anchor + i : anchor - i;
    int beforeToIndex(int i) => forum ? anchor - 1 - i : anchor + 1 + i;

    int? centerChild(Key key) {
      final id = messageIdOfKey(key);
      final index = id == null ? null : indexOfMessage(id);
      if (index == null) {
        return null;
      }
      final i = forum ? index - anchor : anchor - index;
      return i >= 0 && i < centerCount ? i : null;
    }

    int? beforeChild(Key key) {
      final id = messageIdOfKey(key);
      final index = id == null ? null : indexOfMessage(id);
      if (index == null) {
        return null;
      }
      final i = forum ? anchor - 1 - index : index - anchor - 1;
      return i >= 0 && i < beforeCount ? i : null;
    }

    Widget pageSpinner(Key key) =>
        SliverToBoxAdapter(key: key, child: const _PageSpinner());

    final horizontal = EdgeInsets.symmetric(horizontal: sidePadding);
    final homeEnd = <Widget>[
      SliverToBoxAdapter(child: SizedBox(height: homeGap)),
      if (forum ? loadingOlder : loadingNewer)
        pageSpinner(const ValueKey('chat-message-list-home-spinner')),
    ];
    final farEnd = <Widget>[
      if (forum ? loadingNewer : loadingOlder)
        pageSpinner(const ValueKey('chat-message-list-far-spinner')),
      SliverToBoxAdapter(child: SizedBox(height: farGap)),
    ];
    final before = SliverPadding(
      padding: horizontal,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => itemBuilder(beforeToIndex(i)),
          childCount: beforeCount,
          findChildIndexCallback: beforeChild,
        ),
      ),
    );
    final center = SliverPadding(
      key: _centerKey,
      padding: horizontal,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => itemBuilder(centerToIndex(i)),
          childCount: centerCount,
          findChildIndexCallback: centerChild,
        ),
      ),
    );
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          onScrollEnd?.call();
        }
        return false;
      },
      child: _AnchoredScrollView(
        controller: controller,
        reverse: !forum,
        center: _centerKey,
        anchor: anchorFraction,
        // Slivers before the center are laid out from the center outward:
        // the one listed last sits next to it.
        slivers: [...homeEnd, before, center, ...farEnd],
      ),
    );
  }
}

/// A [CustomScrollView] whose viewport reveals children (for
/// [Scrollable.ensureVisible], focus and accessibility) correctly when the
/// zero offset is not at the leading edge ([CustomScrollView.anchor]):
/// Flutter's viewport works out those offsets as if it were.
class _AnchoredScrollView extends CustomScrollView {
  const _AnchoredScrollView({
    super.controller,
    super.reverse,
    super.center,
    super.anchor,
    super.slivers,
  });

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) {
    return _AnchoredViewport(
      axisDirection: axisDirection,
      offset: offset,
      slivers: slivers,
      center: center,
      anchor: anchor,
      paintOrder: paintOrder,
      clipBehavior: clipBehavior,
    );
  }
}

class _AnchoredViewport extends Viewport {
  _AnchoredViewport({
    required super.axisDirection,
    required super.offset,
    required super.slivers,
    super.center,
    super.anchor,
    super.paintOrder,
    super.clipBehavior,
  });

  @override
  RenderViewport createRenderObject(BuildContext context) {
    return _AnchoredRenderViewport(
      axisDirection: axisDirection,
      crossAxisDirection:
          crossAxisDirection ??
          Viewport.getDefaultCrossAxisDirection(context, axisDirection),
      anchor: anchor,
      offset: offset,
      scrollCacheExtent: scrollCacheExtent,
      paintOrder: paintOrder,
      clipBehavior: clipBehavior,
    );
  }
}

class _AnchoredRenderViewport extends RenderViewport {
  _AnchoredRenderViewport({
    super.axisDirection,
    required super.crossAxisDirection,
    required super.offset,
    super.anchor,
    super.scrollCacheExtent,
    super.paintOrder,
    super.clipBehavior,
  });

  @override
  RevealedOffset getOffsetToReveal(
    RenderObject target,
    double alignment, {
    Rect? rect,
    Axis? axis,
  }) {
    final revealed = super.getOffsetToReveal(
      target,
      alignment,
      rect: rect,
      axis: axis,
    );
    final extent = switch (this.axis) {
      Axis.vertical => size.height,
      Axis.horizontal => size.width,
    };
    final shift = anchor * extent;
    if (shift == 0 || !revealed.offset.isFinite) {
      return revealed;
    }
    // Offset 0 puts the center sliver `shift` in from the leading edge, so
    // every offset is that much further along; the revealed rect moves
    // back by as much.
    final rectShift = switch (axisDirection) {
      AxisDirection.up => Offset(0, shift),
      AxisDirection.down => Offset(0, -shift),
      AxisDirection.left => Offset(shift, 0),
      AxisDirection.right => Offset(-shift, 0),
    };
    return RevealedOffset(
      offset: revealed.offset + shift,
      rect: revealed.rect.shift(rectShift),
    );
  }
}

class _PageSpinner extends StatelessWidget {
  const _PageSpinner();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: c.faint),
        ),
      ),
    );
  }
}
