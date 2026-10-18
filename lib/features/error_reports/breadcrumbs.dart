/// One thing that happened shortly before an error: a route change, an auth
/// event or an app lifecycle change. Only short labels, never content.
class Breadcrumb {
  const Breadcrumb(this.at, this.kind, this.label);

  final DateTime at;

  /// `route`, `auth` or `lifecycle`.
  final String kind;
  final String label;
}

/// The last [capacity] breadcrumbs, kept in memory only.
class Breadcrumbs {
  Breadcrumbs({this.capacity = 30, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int capacity;
  final DateTime Function() _clock;
  final List<Breadcrumb> _items = [];

  void add(String kind, String label) {
    _items.add(Breadcrumb(_clock(), kind, label));
    if (_items.length > capacity) {
      _items.removeRange(0, _items.length - capacity);
    }
  }

  List<Breadcrumb> get items => List.unmodifiable(_items);

  /// The last [count] as small JSON: how many seconds ago, kind and label.
  List<Map<String, Object?>> recent([int count = 8]) {
    final now = _clock();
    final from = _items.length > count ? _items.length - count : 0;
    return [
      for (final crumb in _items.sublist(from))
        {
          't': now.difference(crumb.at).inSeconds,
          'k': crumb.kind,
          'v': crumb.label.length > 60
              ? crumb.label.substring(0, 60)
              : crumb.label,
        },
    ];
  }
}
