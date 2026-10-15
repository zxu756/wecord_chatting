import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// A GIF from the `gif-search` Edge Function.
class GifResult {
  const GifResult({
    required this.id,
    required this.url,
    required this.previewUrl,
    this.title = '',
    this.width = 0,
    this.height = 0,
  });

  static GifResult? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final url = json['url'];
    final preview = json['preview_url'];
    if (id is! String || url is! String || gifUrlIn(url) == null) {
      return null;
    }
    return GifResult(
      id: id,
      url: url,
      previewUrl: preview is String && gifUrlIn(preview) != null
          ? preview
          : url,
      title: json['title'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;

  /// What is sent: the GIF's address, which chats show as the GIF.
  final String url;
  final String previewUrl;
  final String title;
  final int width;
  final int height;
}

/// GIF search isn't set up on the server (no provider key yet).
class GifNotConfiguredException implements Exception {
  const GifNotConfiguredException();
}

abstract interface class GifSearchRepository {
  /// Trending GIFs for an empty [query], otherwise matches.
  Future<List<GifResult>> search(String query, {int offset = 0});
}

class SupabaseGifSearchRepository implements GifSearchRepository {
  const SupabaseGifSearchRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GifResult>> search(String query, {int offset = 0}) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'gif-search',
        body: {'query': query.trim(), 'offset': offset},
      );
      data = response.data;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      if (error.status == 503 && code == 'gif_not_configured') {
        throw const GifNotConfiguredException();
      }
      rethrow;
    }
    final gifs = data is Map ? data['gifs'] : null;
    return [
      if (gifs is List)
        for (final gif in gifs) ?GifResult.fromJson(gif),
    ];
  }
}

class NoGifSearchRepository implements GifSearchRepository {
  const NoGifSearchRepository();

  @override
  Future<List<GifResult>> search(String query, {int offset = 0}) {
    throw const GifNotConfiguredException();
  }
}

final gifSearchRepositoryProvider = Provider<GifSearchRepository>((ref) {
  try {
    return SupabaseGifSearchRepository(ref.watch(supabaseClientProvider));
  } on AssertionError {
    return const NoGifSearchRepository();
  }
});

/// False once the server said GIF search isn't set up, so the GIF button
/// stays off for the session; null until known.
final gifSearchAvailableProvider = StateProvider<bool?>((ref) => null);

final _gifUrlPattern = RegExp(
  r'^https://([a-z0-9-]+\.)*giphy\.com/[^\s?#]+\.gif$',
  caseSensitive: false,
);

/// The GIF address when [body] is nothing but one (as sent from the GIF
/// picker), else null. Such messages show the GIF instead of the link.
String? gifUrlIn(String body) {
  final text = body.trim();
  return _gifUrlPattern.hasMatch(text) ? text : null;
}

/// Opens the GIF picker; the chosen GIF, or null.
Future<GifResult?> showGifPicker(BuildContext context) {
  return showModalBottomSheet<GifResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const GifPickerSheet(),
  );
}

class GifPickerSheet extends ConsumerStatefulWidget {
  const GifPickerSheet({super.key});

  @override
  ConsumerState<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends ConsumerState<GifPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _query = '';
  var _loading = true;
  var _notConfigured = false;
  var _failed = false;
  var _gifs = const <GifResult>[];

  /// Ignores answers to searches that were replaced meanwhile.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (value.trim() != _query) {
        unawaited(_load(value.trim()));
      }
    });
  }

  Future<void> _load(String query) async {
    final generation = ++_generation;
    setState(() {
      _query = query;
      _loading = true;
      _failed = false;
    });
    try {
      final gifs = await ref.read(gifSearchRepositoryProvider).search(query);
      if (!mounted || generation != _generation) {
        return;
      }
      ref.read(gifSearchAvailableProvider.notifier).state = true;
      setState(() {
        _gifs = gifs;
        _loading = false;
      });
    } on GifNotConfiguredException {
      if (!mounted) {
        return;
      }
      ref.read(gifSearchAvailableProvider.notifier).state = false;
      setState(() {
        _notConfigured = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.7;

    final Widget body;
    if (_notConfigured) {
      body = _Message(
        icon: Icons.gif_box_outlined,
        text: tr("GIF search isn't set up on this server yet."),
      );
    } else if (_loading && _gifs.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = _Message(
        icon: Icons.error_outline,
        text: tr('Could not load GIFs. Try again.'),
        action: TextButton(
          onPressed: () => unawaited(_load(_query)),
          child: Text(tr('Retry')),
        ),
      );
    } else if (_gifs.isEmpty) {
      body = _Message(icon: Icons.search_off, text: tr('No GIFs found.'));
    } else {
      body = GridView.builder(
        key: const ValueKey('gif-grid'),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.3,
        ),
        itemCount: _gifs.length,
        itemBuilder: (context, index) {
          final gif = _gifs[index];
          return Material(
            key: ValueKey('gif-${gif.id}'),
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(gif),
              child: Tooltip(
                message: gif.title.isEmpty ? tr('GIF') : gif.title,
                child: Image.network(
                  gif.previewUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.broken_image_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              key: const ValueKey('gif-search-field'),
              controller: _controller,
              enabled: !_notConfigured,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Search GIFs'),
              ),
              onChanged: _onChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                unawaited(_load(value.trim()));
              },
            ),
          ),
          if (!_notConfigured)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _query.isEmpty ? tr('Trending') : tr('Results'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(child: body),
          if (!_notConfigured)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              // The provider asks apps to credit it.
              child: Text(
                'Powered by GIPHY',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A GIF message: the GIF itself, at most a bubble wide.
class GifMessageImage extends StatelessWidget {
  const GifMessageImage({required this.url, this.textColor, super.key});

  final String url;

  /// For the link shown when the GIF fails to load.
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      key: const ValueKey('gif-message'),
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 240),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          label: tr('GIF'),
          image: true,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    width: 200,
                    height: 150,
                    color: colorScheme.surfaceContainerHighest,
                  ),
            errorBuilder: (context, error, stackTrace) => Text(
              url,
              style: TextStyle(color: textColor ?? colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
