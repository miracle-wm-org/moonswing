// What the window switcher (Alt+Tab) switches between, and the arithmetic that
// decides which one is selected and where it is drawn.
//
// Deliberately Flutter-free and Wayland-free: an [OpenWindow] is the three
// fields `ext_foreign_toplevel_handle_v1` reports, so the recency ordering, the
// cycling and the grid layout are all a plain unit test on a machine with no
// compositor. The store that fills it is `open_window_store.dart`; the join
// back to miracle's window tree is `window_activation.dart`.

import 'package:moonswing/capture/toplevel_match.dart';

/// One toplevel the compositor has told the shell about.
///
/// [identifier] is `ext_foreign_toplevel_handle_v1.identifier` — the one field
/// of the three that is stable and unique, and so the only thing the switcher
/// keys anything on. [appId] and [title] are what the window calls itself, and
/// are both allowed to be empty (an XWayland toplevel carries no `app_id`, and
/// a window mid-map carries no title).
class OpenWindow {
  const OpenWindow({
    required this.identifier,
    required this.appId,
    required this.title,
  });

  final String identifier;
  final String appId;
  final String title;

  /// What the switcher writes under the selected icon.
  ///
  /// The title, because that is what tells two windows of one application
  /// apart — which is the whole reason the name is shown at all. A window that
  /// has not got one yet falls back to its `app_id`, and one with neither to a
  /// word rather than an empty line, because a blank label under a highlighted
  /// icon reads as a rendering bug.
  String get label {
    if (title.isNotEmpty) return title;
    if (appId.isNotEmpty) return appId;
    return 'Untitled window';
  }

  /// The [ToplevelDescriptor] the capture stack's matcher takes, so the
  /// switcher and the window picker join miracle's tree the one way.
  ToplevelDescriptor get descriptor =>
      ToplevelDescriptor(identifier: identifier, appId: appId, title: title);

  @override
  bool operator ==(Object other) =>
      other is OpenWindow &&
      other.identifier == identifier &&
      other.appId == appId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(identifier, appId, title);

  @override
  String toString() => 'OpenWindow($identifier, $appId, "$title")';
}

/// A spelling of everything the switcher draws, for the store's "a read that
/// finds nothing new must not notify" guard.
///
/// Every surface on every monitor listens, so a `done` event that only
/// re-reports a title the switcher already has must not reach any of them.
String openWindowSignature(List<OpenWindow> windows) => windows
    .map((w) => '${w.identifier}\u0000${w.appId}\u0000${w.title}')
    .join('\u0001');

/// [windows] in most-recently-focused order.
///
/// [recent] is a list of identifiers, most recent first, and need not agree
/// with [windows] about anything: an identifier that has since closed is
/// skipped, and a window the recency list has never heard of keeps its place
/// after the ones it has. That is what makes the ordering *best effort* — the
/// foreign-toplevel protocol reports no focus at all, so recency comes from
/// miracle's `window` events and a shell not connected to miracle simply gets
/// the compositor's own order.
List<OpenWindow> orderByRecency(
  List<OpenWindow> windows,
  List<String> recent,
) {
  if (recent.isEmpty || windows.length < 2) return windows;
  final byIdentifier = {for (final window in windows) window.identifier: window};
  final ordered = <OpenWindow>[];
  final taken = <String>{};
  for (final identifier in recent) {
    final window = byIdentifier[identifier];
    if (window == null || !taken.add(identifier)) continue;
    ordered.add(window);
  }
  for (final window in windows) {
    if (taken.contains(window.identifier)) continue;
    ordered.add(window);
  }
  return ordered;
}

/// [recent] with [identifier] moved to the front.
///
/// Bounded by [limit], because this list is fed by every focus change in the
/// session and nothing ever removes from it otherwise: an identifier past the
/// end is one whose window almost certainly closed long ago, and dropping it
/// costs the ordering nothing a person could notice.
List<String> promoteRecent(
  List<String> recent,
  String identifier, {
  int limit = 64,
}) {
  if (identifier.isEmpty) return recent;
  if (recent.isNotEmpty && recent.first == identifier) return recent;
  final next = <String>[identifier];
  for (final other in recent) {
    if (other == identifier) continue;
    next.add(other);
    if (next.length == limit) break;
  }
  return next;
}

/// The index [delta] steps from [current] through [length] items, wrapping.
///
/// Wrapping in both directions is the whole interaction: Alt+Tab past the end
/// comes back to the front, and Alt+Shift+Tab off the front lands on the back.
/// An empty list has no selection to move, and answers 0 rather than throwing —
/// the switcher renders its empty state and the commit does nothing.
int cycleIndex(int current, int delta, int length) {
  if (length <= 0) return 0;
  final next = (current + delta) % length;
  return next < 0 ? next + length : next;
}

/// How many icons the switcher puts on one row before wrapping to the next.
///
/// Five, so the grid reads as a grid rather than as a strip the eye has to
/// scan: past about that many, "which one is highlighted" stops being a glance.
const int kSwitcherColumns = 5;

/// The row [index] falls on in a grid [columns] wide.
int switcherRowOf(int index, {int columns = kSwitcherColumns}) =>
    columns <= 0 ? 0 : index ~/ columns;

/// How many rows [count] windows need.
int switcherRowCount(int count, {int columns = kSwitcherColumns}) =>
    columns <= 0 || count <= 0 ? 0 : (count + columns - 1) ~/ columns;

/// The scroll offset that brings [row] fully into a viewport [viewportExtent]
/// tall, given rows of [rowExtent] and a current offset of [offset].
///
/// The minimum move that works, in both directions: a row above the viewport
/// scrolls to sit at its top, a row below scrolls to sit at its bottom, and a
/// row already visible does not move at all. Cycling through a long list should
/// slide the grid by a row at a time rather than re-centring on every press,
/// which is what a "scroll so the selection is in the middle" rule would do.
double switcherScrollOffset({
  required int row,
  required double rowExtent,
  required double viewportExtent,
  required double offset,
  required int rowCount,
}) {
  if (rowExtent <= 0 || rowCount <= 0) return 0;
  final maxOffset = (rowCount * rowExtent - viewportExtent).clamp(
    0.0,
    double.infinity,
  );
  final top = row * rowExtent;
  final bottom = top + rowExtent;
  var next = offset;
  if (top < offset) {
    next = top;
  } else if (bottom > offset + viewportExtent) {
    next = bottom - viewportExtent;
  }
  return next.clamp(0.0, maxOffset);
}
