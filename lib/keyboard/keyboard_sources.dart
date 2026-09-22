// The pure derivations between locale1's four strings and the shell's ordered
// list of input sources.
//
// Kept out of `keyboard_store.dart` so all of it is a plain unit test with no
// D-Bus behind it.

import 'package:moonswing/keyboard/keyboard_config.dart';
import 'package:moonswing/keyboard/locale1_client.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';

/// The source locale1 is *currently* applying, or null when it reports nothing.
///
/// `X11Layout` and `X11Variant` are comma-separated lists when more than one xkb
/// group is configured. miral joins layout, variant and options into a single
/// `ParameterKeymap`, and nothing in the stack can select a group, so group 1 is
/// what the user is actually typing in and is the only honest answer.
InputSource? effectiveSource(Locale1Keyboard state) {
  final layout = state.layout.split(',').first.trim();
  if (layout.isEmpty) return null;
  final variants = state.variant.split(',');
  final variant = variants.isEmpty ? '' : variants.first.trim();
  return InputSource(layout, variant: variant);
}

/// Which of [sources] locale1 is applying, or `-1`.
///
/// Matching is **exact** on the pair: `de` and `de+nodeadkeys` are two rows in
/// the user's list, and matching one against the other lights the wrong one.
///
/// `-1` is a real answer, not a failure — see `KeyboardStore.unlistedActive`.
/// Falling back to index 0 would be the lie.
int activeSourceIndex(List<InputSource> sources, Locale1Keyboard state) {
  final active = effectiveSource(state);
  if (active == null) return -1;
  return sources.indexOf(active);
}

/// Every group locale1 has configured, as sources.
///
/// What the shell's list is seeded from on first run, because locale1 holds only
/// the *active* layout: the first `SetX11Keyboard` destroys whatever the
/// installer configured, and this is the one moment it still exists.
///
/// The variant list can be shorter than the layout list (`X11Layout="us,de"` with
/// `X11Variant=""` is two groups on their default variant), so it is indexed
/// defensively rather than zipped.
List<InputSource> seedSourcesFrom(Locale1Keyboard state) {
  final layouts = state.layout
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (layouts.isEmpty) return const [];
  final variants = state.variant.split(',');
  final seen = <InputSource>{};
  final sources = <InputSource>[];
  for (var i = 0; i < layouts.length; i++) {
    final variant = i < variants.length ? variants[i].trim() : '';
    final source = InputSource(layouts[i], variant: variant);
    if (!seen.add(source)) continue;
    sources.add(source);
  }
  return sources;
}

/// What a source is called, for a human.
///
/// A variant's own description already carries its language ("Portuguese (Brazil,
/// Nativo)"), so it is returned **verbatim** rather than concatenated onto the
/// layout's. With no catalogue — or a layout this build's xkeyboard-config does
/// not know — the xkb spelling is the answer, which is truthful where a guess
/// would not be.
String describeSource(XkbCatalog catalog, InputSource source) {
  if (source.hasVariant) {
    final variant = catalog.variantFor(source.layout, source.variant);
    if (variant != null) return variant.description;
  }
  final layout = catalog.layoutFor(source.layout);
  if (layout == null) return source.id;
  if (!source.hasVariant) return layout.description;
  // A variant the catalogue does not carry, on a layout it does.
  return '${layout.description} (${source.variant})';
}

/// Ranks catalogue entries for the picker's query.
///
/// `rankTimeZones`'s discipline: pure, so the ordering is a unit test rather
/// than something only observable by typing into a dropdown. Ties keep the
/// catalogue's own order, which is each layout followed by its own variants.
List<XkbEntry> rankXkbEntries(List<XkbEntry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;

  final scored = <(int, int, XkbEntry)>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final code = entry.source.id.toLowerCase();
    final layout = entry.source.layout.toLowerCase();
    final description = entry.description.toLowerCase();

    int? score;
    if (code == q || layout == q) {
      score = 0;
    } else if (code.startsWith(q) || layout.startsWith(q)) {
      score = 1;
    } else if (description.startsWith(q)) {
      score = 2;
    } else if (_wordStart(description, q)) {
      score = 3;
    } else if (description.contains(q)) {
      score = 4;
    } else if (code.contains(q)) {
      score = 5;
    }
    if (score == null) continue;
    // A base layout sorts above its own variants at the same score: somebody
    // typing "german" wants German before German (dead acute).
    scored.add((score * 2 + (entry.isVariant ? 1 : 0), i, entry));
  }

  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });
  return [for (final entry in scored) entry.$3];
}

bool _wordStart(String haystack, String needle) {
  var at = haystack.indexOf(needle);
  while (at > 0) {
    if (!_isWordChar(haystack.codeUnitAt(at - 1))) return true;
    at = haystack.indexOf(needle, at + 1);
  }
  return false;
}

bool _isWordChar(int code) =>
    (code >= 0x61 && code <= 0x7a) || // a-z
    (code >= 0x41 && code <= 0x5a) || // A-Z
    (code >= 0x30 && code <= 0x39); // 0-9
