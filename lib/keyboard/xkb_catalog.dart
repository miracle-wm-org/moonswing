// The xkb layouts and variants installed on this machine, from
// xkeyboard-config's own rules listing.
//
// `base.lst` rather than `evdev.xml`: the two carry the same tables, the `.lst`
// is a fifth the size, and parsing it needs no XML dependency — which this repo
// does not have. What the XML has and the list does not is `<shortDescription>`,
// the `en`-for-`us` column; see `keyboard_short_codes.dart` for what stands in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/keyboard/keyboard_config.dart';

/// Where xkeyboard-config's rules listing is looked for, in order.
const List<String> kXkbRulesPaths = [
  '/usr/share/X11/xkb/rules/base.lst',
  '/usr/share/X11/xkb/rules/evdev.lst',
  '/usr/local/share/X11/xkb/rules/base.lst',
];

/// A base layout: `us` / "English (US)".
@immutable
class XkbLayout {
  const XkbLayout({required this.code, required this.description});

  final String code;
  final String description;

  @override
  bool operator ==(Object other) =>
      other is XkbLayout &&
      other.code == code &&
      other.description == description;

  @override
  int get hashCode => Object.hash(code, description);
}

/// A layout's variant: `br` + `nativo` / "Portuguese (Brazil, Nativo)".
///
/// Keyed on the pair. A variant code is not unique on its own — `nativo` is a
/// variant of both `pt` and `br`.
@immutable
class XkbVariant {
  const XkbVariant({
    required this.layout,
    required this.code,
    required this.description,
  });

  final String layout;
  final String code;
  final String description;

  @override
  bool operator ==(Object other) =>
      other is XkbVariant &&
      other.layout == layout &&
      other.code == code &&
      other.description == description;

  @override
  int get hashCode => Object.hash(layout, code, description);
}

/// One selectable row in the picker: a layout, or one of its variants.
@immutable
class XkbEntry {
  const XkbEntry({required this.source, required this.description});

  final InputSource source;

  /// What the picker and the settings list show. Taken **verbatim** from the
  /// rules file: a variant's description already carries its language
  /// ("Portuguese (Brazil, Nativo)"), so concatenating the layout's onto it
  /// would read "Portuguese (Brazil) — Portuguese (Brazil, Nativo)".
  final String description;

  bool get isVariant => source.hasVariant;

  @override
  bool operator ==(Object other) =>
      other is XkbEntry &&
      other.source == source &&
      other.description == description;

  @override
  int get hashCode => Object.hash(source, description);
}

/// The parsed rules listing.
///
/// A value type: the *loading* of it is [XkbCatalogReader]'s, so everything
/// here is a plain unit test with no filesystem behind it.
@immutable
class XkbCatalog {
  XkbCatalog({
    List<XkbLayout> layouts = const [],
    List<XkbVariant> variants = const [],
  }) : layouts = List.unmodifiable(layouts),
       variants = List.unmodifiable(variants),
       _layoutsByCode = {for (final l in layouts) l.code: l},
       _variantsByPair = {
         for (final v in variants) '${v.layout}+${v.code}': v,
       };

  static final XkbCatalog empty = XkbCatalog();

  final List<XkbLayout> layouts;
  final List<XkbVariant> variants;

  final Map<String, XkbLayout> _layoutsByCode;
  final Map<String, XkbVariant> _variantsByPair;

  bool get isEmpty => layouts.isEmpty && variants.isEmpty;
  bool get isNotEmpty => !isEmpty;

  XkbLayout? layoutFor(String code) => _layoutsByCode[code];

  XkbVariant? variantFor(String layout, String code) =>
      code.isEmpty ? null : _variantsByPair['$layout+$code'];

  /// Every selectable row, each layout followed by its own variants.
  ///
  /// Built once and cached: the picker filters this on every keystroke, and
  /// the settings pane it lives on rebuilds on every store notification.
  late final List<XkbEntry> entries = _buildEntries();

  List<XkbEntry> _buildEntries() {
    final byLayout = <String, List<XkbVariant>>{};
    for (final variant in variants) {
      (byLayout[variant.layout] ??= []).add(variant);
    }
    final ordered = [...layouts]
      ..sort((a, b) => a.description.toLowerCase().compareTo(
        b.description.toLowerCase(),
      ));
    final entries = <XkbEntry>[];
    for (final layout in ordered) {
      entries.add(
        XkbEntry(
          source: InputSource(layout.code),
          description: layout.description,
        ),
      );
      final children = byLayout[layout.code];
      if (children == null) continue;
      children.sort((a, b) => a.description.toLowerCase().compareTo(
        b.description.toLowerCase(),
      ));
      for (final variant in children) {
        entries.add(
          XkbEntry(
            source: InputSource(layout.code, variant: variant.code),
            description: variant.description,
          ),
        );
      }
    }
    return List.unmodifiable(entries);
  }
}

enum _Section { none, layouts, variants }

/// Parses xkeyboard-config's `*.lst` rules listing.
///
/// The format is a series of `! <section>` headers over two-column rows. Only
/// `! layout` and `! variant` are consumed; every other header — `! model`,
/// `! option`, and the `! include %S/base.lst` some distributions ship —
/// puts the parser in a skip state rather than being mistaken for data.
///
/// Nothing here throws. A malformed row costs that row, an unreadable file
/// costs the picker (see [XkbCatalogReader]), and neither costs the settings
/// page it is on.
XkbCatalog parseXkbRulesList(String text) {
  final layouts = <XkbLayout>[];
  final variants = <XkbVariant>[];
  final seenLayouts = <String>{};
  final seenVariants = <String>{};
  var section = _Section.none;

  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('!')) {
      final name = line.substring(1).trim().split(RegExp(r'\s+')).first;
      section = switch (name) {
        'layout' => _Section.layouts,
        'variant' => _Section.variants,
        _ => _Section.none,
      };
      continue;
    }
    if (section == _Section.none) continue;

    // The code column is not fixed width — `latinalternatequotes rs: Serbian
    // (Latin, with guillemets)` runs past every other row on the page — so the
    // split is on the first whitespace run and never on an offset.
    final match = RegExp(r'^(\S+)\s+(.+)$').firstMatch(line);
    if (match == null) continue;
    final code = match.group(1)!;
    final rest = match.group(2)!.trim();

    if (section == _Section.layouts) {
      if (!seenLayouts.add(code)) continue;
      layouts.add(XkbLayout(code: code, description: rest));
      continue;
    }

    // `chr             us: Cherokee`
    final colon = rest.indexOf(':');
    if (colon < 0) continue;
    final layout = rest.substring(0, colon).trim();
    final description = rest.substring(colon + 1).trim();
    if (layout.isEmpty || description.isEmpty) continue;
    if (layout.contains(RegExp(r'\s'))) continue;
    if (!seenVariants.add('$layout+$code')) continue;
    variants.add(
      XkbVariant(layout: layout, code: code, description: description),
    );
  }

  return XkbCatalog(layouts: layouts, variants: variants);
}

/// Reads the rules listing off disk, once.
///
/// [FontCatalog]'s shape (`lib/theme/font_catalog.dart`): the reader is
/// injectable so tests never touch `/usr/share`, the *future* is memoised so
/// two callers racing on a cold catalogue share one read, and every failure
/// resolves to [XkbCatalog.empty]. A machine with no `xkb-data` — a container,
/// a stripped image — is not an error: the picker degrades to a free-typed
/// field, which is what `SettingsFontField` does with no fontconfig.
///
/// Loaded lazily by the settings page and by nothing else. This is a large part
/// of why the feature needs no `ShellService`: with no module in a bar and no
/// visit to the page, the file is never opened.
class XkbCatalogReader {
  XkbCatalogReader({
    List<String>? paths,
    Future<String?> Function(String path)? reader,
  }) : _paths = paths ?? kXkbRulesPaths,
       _read = reader ?? _readFile;

  static final XkbCatalogReader instance = XkbCatalogReader();

  final List<String> _paths;
  final Future<String?> Function(String path) _read;

  Future<XkbCatalog>? _cached;

  Future<XkbCatalog> load() => _cached ??= _load();

  Future<XkbCatalog> _load() async {
    for (final path in _paths) {
      try {
        final text = await _read(path);
        if (text == null || text.isEmpty) continue;
        final catalog = parseXkbRulesList(text);
        if (catalog.isNotEmpty) return catalog;
      } catch (_) {
        // Unreadable, or not there. Try the next candidate.
      }
    }
    return XkbCatalog.empty;
  }

  static Future<String?> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
