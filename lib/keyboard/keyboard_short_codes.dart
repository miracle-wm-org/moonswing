// The two- or three-letter badge the bar module draws — `en`, `de`, `ara`.
//
// Its own file because it is the one piece of this feature that is **not**
// derived from anything, and its provenance has to be obvious.
//
// `base.lst` has no such column. GNOME's `en` for `us` comes from `evdev.xml`'s
// `<shortDescription>`, which needs an XML parser this repo has no dependency
// for. So the table below is curated, and the fallback is the layout code itself:
// an unlisted layout shows `ara` rather than a guessed language, which is
// worse-looking than GNOME and never false.

import 'package:graceful_shell/keyboard/keyboard_config.dart';

/// Layout codes whose ISO-3166 country differs from the ISO-639 language a reader
/// expects to see on the badge.
///
/// Only the ones that differ are listed — `de`, `fr`, `es`, `it`, `ru` and most
/// of the rest already *are* their language and fall through to the identity case.
const Map<String, String> kLayoutShortCodes = {
  'us': 'en',
  'gb': 'en',
  'au': 'en',
  'nz': 'en',
  'ie': 'ga',
  'ca': 'fr',
  'at': 'de',
  'ch': 'de',
  'be': 'nl',
  'br': 'pt',
  'latam': 'es',
  'cz': 'cs',
  'dk': 'da',
  'gr': 'el',
  'il': 'he',
  'ir': 'fa',
  'iq': 'ar',
  'sy': 'ar',
  'eg': 'ar',
  'ma': 'ar',
  'ara': 'ar',
  'jp': 'ja',
  'kr': 'ko',
  'cn': 'zh',
  'tw': 'zh',
  'se': 'sv',
  'no': 'nb',
  'ee': 'et',
  'ua': 'uk',
  'by': 'be',
  'rs': 'sr',
  'ge': 'ka',
  'am': 'hy',
  'in': 'hi',
  'bd': 'bn',
  'lk': 'si',
  'np': 'ne',
  'mm': 'my',
  'kh': 'km',
  'la': 'lo',
  'vn': 'vi',
  'kz': 'kk',
  'af': 'ps',
  'pk': 'ur',
  'et': 'am',
  'mv': 'dv',
  'epo': 'eo',
  'phi': 'fil',
  'nec_vndr/jp': 'ja',
};

/// The badge text for a layout code, before de-duplication.
String shortCodeFor(String layout) {
  final code = layout.trim().toLowerCase();
  if (code.isEmpty) return '';
  final mapped = kLayoutShortCodes[code];
  if (mapped != null) return mapped;
  return code.length <= 3 ? code : code.substring(0, 3);
}

/// The badge text for each of [sources], positionally.
///
/// Two sources can share a code — `us` and `gb` are both `en` — and a bar showing
/// `en` twice says nothing about which is live. gnome-shell answers this the same
/// way: the first source keeping a code keeps it bare, and each later collision
/// takes a 1-based ordinal (`en`, `en2`, `en3`).
List<String> assignShortCodes(List<InputSource> sources) {
  final counts = <String, int>{};
  final codes = <String>[];
  for (final source in sources) {
    final base = shortCodeFor(source.layout);
    final seen = (counts[base] ?? 0) + 1;
    counts[base] = seen;
    codes.add(seen == 1 ? base : '$base$seen');
  }
  return codes;
}
