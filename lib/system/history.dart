import 'dart:collection';

/// A fixed-capacity FIFO of samples, oldest first.
///
/// The graphs read this straight through: [toList] is in chart order, and
/// [capacity] — not [length] — is what maps the x axis, so a buffer that is
/// still filling draws a line growing in from the left instead of one that
/// rescales horizontally on every new sample.
class HistoryBuffer<T> {
  HistoryBuffer(int capacity) : _capacity = capacity < 1 ? 1 : capacity;

  final ListQueue<T> _items = ListQueue<T>();
  int _capacity;

  int get capacity => _capacity;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  void add(T item) {
    _items.addLast(item);
    while (_items.length > _capacity) {
      _items.removeFirst();
    }
  }

  /// Resizes in place, dropping the oldest samples if the buffer shrinks. Used
  /// when `history_samples` changes in the settings UI — the graph keeps the
  /// history it has rather than starting over.
  void resize(int capacity) {
    _capacity = capacity < 1 ? 1 : capacity;
    while (_items.length > _capacity) {
      _items.removeFirst();
    }
  }

  void clear() => _items.clear();

  List<T> toList() => _items.toList(growable: false);
}
