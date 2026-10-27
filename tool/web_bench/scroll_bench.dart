// A scrolling benchmark for the web builds (L5, docs/wasm-report.md).
//
// Not part of the app: it is its own entry point, built with
//
//   flutter build web --wasm --release -t tool/web_bench/scroll_bench.dart
//
// and driven by tool/web_bench/bench.mjs. It shows the chat's real message
// list (MessageListView, the same slivers, anchor and keys the chat uses)
// holding thousands of bubble-like items: long mixed Chinese and English
// text, avatars, reactions, a photo placeholder, shadows and clipping. After
// a warm-up it scrolls the list at a steady speed for a while, then leaves
// the frame timings in `window.__wecordBenchResult` (a JSON string) for the
// driver to read. The real chat screen needs a signed-in Supabase session, so
// this stands in for it; what it measures is the engine (layout, paint,
// raster), which is what differs between the JS and the wasm builds.
//
// Query parameters: `items` (default 5000), `warmup` seconds (3),
// `seconds` of scrolling (12), `speed` in logical pixels per second (2400).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wecord/features/chats/message_list_view.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

const _english = [
  'Did you see the new design? I think the spacing is finally right.',
  'Meeting moved to 3pm, please bring the draft and the numbers from last week. '
      'We also need to decide who presents the roadmap, and how much time each '
      'section gets, because the last review ran over by twenty minutes.',
  'ok',
  'Sounds good, let me check and get back to you in a bit.',
  'Here is the long version: the migration touches the messages table, the '
      'read receipts, the notification counters and the search index, so we '
      'should do it in the quiet hours and keep the old columns for a week in '
      'case something goes wrong. If the backfill takes longer than expected '
      'we can pause it and continue the next night without any downtime.',
];

const _chinese = [
  '今天晚上有空吗？一起吃饭吧，我知道一家新开的店，味道还不错。',
  '会议改到下午三点，请带上上周的草稿和数据。另外还需要确定谁来讲路线图，'
      '每一部分各讲多长时间，因为上次评审超时了二十分钟，大家都有点累。',
  '好的',
  '收到，我先看一下，等会儿回复你。',
  '完整版本是这样的：这次迁移会动到消息表、已读回执、通知计数和搜索索引，'
      '所以最好在凌晨安静的时候做，并且把旧的列再保留一个星期，万一出了问题还能回退。'
      '如果回填花的时间比预想的长，可以先暂停，第二天晚上接着做，不需要停机。',
];

class _Item {
  const _Item(this.text, this.mine, this.photo, this.reactions);
  final String text;
  final bool mine;
  final bool photo;
  final int reactions;
}

List<_Item> _items(int count) {
  var seed = 7;
  int next(int max) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % max;
  }

  return List.generate(count, (i) {
    final chinese = next(2) == 0;
    final pool = chinese ? _chinese : _english;
    return _Item(
      pool[next(pool.length)],
      next(3) == 0,
      next(12) == 0,
      next(5) == 0 ? 1 + next(3) : 0,
    );
  });
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.item);
  final _Item item;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shadows = context.tokens.shadows;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: item.mine ? c.accent : c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        boxShadow: shadows.hairline,
        border: item.mine ? null : Border.all(color: c.lineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.photo)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  child: Container(
                    width: 220,
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.accentSoft, c.successSoft, c.warningSoft],
                      ),
                    ),
                  ),
                ),
              ),
            Text(
              item.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: item.mine ? c.onAccent : c.ink,
                height: 1.4,
              ),
            ),
            if (item.reactions > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < item.reactions; i++)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(fontSize: 12, color: c.accentText),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: item.mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!item.mine)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: c.accentSoft,
                child: Icon(Icons.person, size: 18, color: c.accentText),
              ),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenchPage extends StatefulWidget {
  const _BenchPage({
    required this.count,
    required this.warmup,
    required this.seconds,
    required this.speed,
  });

  final int count;
  final Duration warmup;
  final Duration seconds;
  final double speed;

  @override
  State<_BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<_BenchPage>
    with SingleTickerProviderStateMixin {
  final _controller = ScrollController();
  late final List<_Item> _data = _items(widget.count);
  final _timings = <ui.FrameTiming>[];
  late final Ticker _ticker;
  Duration? _started;
  var _measuring = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (_measuring) {
        _timings.addAll(timings);
      }
    });
    Timer(widget.warmup, () {
      _measuring = true;
      _ticker.start();
      _signal('measuring');
    });
  }

  void _tick(Duration elapsed) {
    _started ??= elapsed;
    final seconds = (elapsed - _started!).inMicroseconds / 1e6;
    if (seconds >= widget.seconds.inMicroseconds / 1e6) {
      _ticker.stop();
      // Let the last frames report their timings first.
      Timer(const Duration(milliseconds: 600), _finish);
      return;
    }
    if (_controller.hasClients) {
      _controller.jumpTo(seconds * widget.speed);
    }
  }

  void _signal(String state) {
    globalContext.setProperty('__wecordBenchState'.toJS, state.toJS);
  }

  void _finish() {
    _measuring = false;
    double ms(Duration d) => d.inMicroseconds / 1000;
    double percentile(List<double> sorted, double p) => sorted.isEmpty
        ? 0
        : sorted[((sorted.length - 1) * p).round().clamp(0, sorted.length - 1)];
    final build = _timings.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = _timings.map((t) => ms(t.rasterDuration)).toList()..sort();
    final total = _timings.map((t) => ms(t.totalSpan)).toList()..sort();
    final result = {
      'frames': _timings.length,
      'seconds': widget.seconds.inMilliseconds / 1000,
      'items': widget.count,
      'speedPxPerSecond': widget.speed,
      'build': {
        'p50': percentile(build, 0.5),
        'p90': percentile(build, 0.9),
        'p99': percentile(build, 0.99),
        'max': build.isEmpty ? 0 : build.last,
      },
      'raster': {
        'p50': percentile(raster, 0.5),
        'p90': percentile(raster, 0.9),
        'p99': percentile(raster, 0.99),
        'max': raster.isEmpty ? 0 : raster.last,
      },
      'total': {
        'p50': percentile(total, 0.5),
        'p90': percentile(total, 0.9),
        'p99': percentile(total, 0.99),
        'max': total.isEmpty ? 0 : total.last,
      },
      'slowFrames16': total.where((v) => v > 16.7).length,
      'slowFrames33': total.where((v) => v > 33.4).length,
    };
    globalContext.setProperty(
      '__wecordBenchResult'.toJS,
      jsonEncode(result).toJS,
    );
    _signal('done');
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.count - 1;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => MessageListView(
          controller: _controller,
          forum: false,
          itemCount: widget.count,
          anchorIndex: last,
          indexOfMessage: int.tryParse,
          messageIdOfKey: (key) =>
              key is ValueKey<String> ? key.value : null,
          itemBuilder: (index) => KeyedSubtree(
            key: ValueKey<String>('$index'),
            child: _Bubble(_data[index]),
          ),
          viewportHeight: constraints.maxHeight,
          sidePadding: 12,
          topPadding: 16,
          bottomPadding: 16,
        ),
      ),
    );
  }
}

void main() {
  final query = Uri.base.queryParameters;
  int number(String key, int fallback) =>
      int.tryParse(query[key] ?? '') ?? fallback;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: WeCordTheme.light(),
      home: _BenchPage(
        count: number('items', 5000),
        warmup: Duration(seconds: number('warmup', 3)),
        seconds: Duration(seconds: number('seconds', 12)),
        speed: number('speed', 2400).toDouble(),
      ),
    ),
  );
}
