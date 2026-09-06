// Joining miracle's view of a window to the compositor's capture handle for it.
//
// The two halves of the window picker come from different protocols with no id in
// common. miracle's `GET_TREE` says *where* a window is — the only thing that can
// draw a rectangle under the pointer — and `ext-foreign-toplevel-list-v1` is what
// the capture stack can turn into a source that follows it. All they share is
// what the window calls itself, so this is a match on `app_id` and title.
//
// The rule that matters is the one about *not* matching: an ambiguous pair
// answers null and the caller falls back to cropping the output. A rectangle that
// stops following a window the user moves is a disappointment; silently recording
// somebody's *other* Firefox window is a leak.

/// One entry of the compositor's foreign-toplevel list, reduced to the three
/// fields the match uses. Its own type so the match is a plain unit test with
/// no Wayland behind it.
class ToplevelDescriptor {
  const ToplevelDescriptor({
    required this.identifier,
    required this.appId,
    required this.title,
  });

  final String identifier;
  final String appId;
  final String title;
}

/// The identifier of the toplevel that is the window miracle calls
/// [appId]/[title], or null when no single one is.
///
/// Three passes, narrowing: both fields, then the title alone (an XWayland
/// window's `app_id` is its WM class on one side and empty on the other), then
/// the `app_id` alone (a window whose title changed between the tree read and the
/// pick — a browser tab switch is enough). Each pass answers only when exactly one
/// candidate survives it.
String? matchToplevel(
  List<ToplevelDescriptor> toplevels, {
  required String appId,
  required String title,
}) {
  String? unique(bool Function(ToplevelDescriptor) test) {
    String? found;
    for (final toplevel in toplevels) {
      if (toplevel.identifier.isEmpty || !test(toplevel)) continue;
      if (found != null) return null; // ambiguous — decline rather than guess
      found = toplevel.identifier;
    }
    return found;
  }

  final normalizedApp = appId.toLowerCase();

  if (appId.isNotEmpty && title.isNotEmpty) {
    final both = unique((t) =>
        t.title == title && t.appId.toLowerCase() == normalizedApp);
    if (both != null) return both;
  }
  if (title.isNotEmpty) {
    final byTitle = unique((t) => t.title == title);
    if (byTitle != null) return byTitle;
  }
  if (appId.isNotEmpty) {
    final byApp = unique((t) => t.appId.toLowerCase() == normalizedApp);
    if (byApp != null) return byApp;
  }
  return null;
}
