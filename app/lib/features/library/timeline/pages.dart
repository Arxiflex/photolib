import 'package:flutter/foundation.dart';

/// The items of a timeline by position, fetched a page at a time as cells
/// need them (docs/10 §3.1), keeping the [keep] most recently used pages.
class TimelinePages extends ChangeNotifier {
  TimelinePages(this.fetch, {this.size = 128, this.keep = 64});

  /// The items from position [first] on, [count] or fewer at the end.
  final Future<List<Object>> Function(int first, int count) fetch;
  final int size, keep;
  final _pages = <int, List<Object>>{}; // least recently used first
  final _loading = <int>{};
  var _disposed = false;

  /// The item at [position], or null until its page arrives, which notifies.
  Object? operator [](int position) {
    final page = position ~/ size;
    final items = _pages.remove(page);
    if (items == null) {
      _load(page);
      return null;
    }
    _pages[page] = items;
    final i = position % size;
    return i < items.length ? items[i] : null;
  }

  /// Fetches the page of [position] before a cell asks for it.
  Future<void> preload(int position) => _load(position ~/ size);

  Future<void> _load(int page) async {
    if (!_loading.add(page)) return;
    try {
      final items = await fetch(page * size, size);
      if (_disposed) return;
      _pages[page] = items;
      while (_pages.length > keep) {
        _pages.remove(_pages.keys.first);
      }
      notifyListeners();
    } finally {
      _loading.remove(page);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
