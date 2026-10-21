import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/icons/icon_resolver.dart';
import 'package:moonswing/icons/pack_glyph.dart';
import 'package:moonswing/icons/packs/font_awesome.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/icon_pack.dart';
import 'package:moonswing/theme/theme_config.dart';

import 'glyph_finder.dart';

/// The glyphs each pack has no drawing of its own for, and so borrows Font
/// Awesome's. Pinned so the list only ever grows on purpose: a new member that
/// a pack answers with `null` has to be added here, by someone who looked.
const Map<IconPack, Set<ShellGlyph>> _kFallbacks = {
  IconPack.fontAwesome: {},
  // Google ships no brands, and nothing that reads as a pull request.
  IconPack.materialRounded: _materialFallbacks,
  IconPack.materialOutlined: _materialFallbacks,
  IconPack.materialSharp: _materialFallbacks,
  // Lucide dropped its logos.
  IconPack.lucide: {
    ShellGlyph.github,
    ShellGlyph.linux,
    ShellGlyph.googleDrive,
  },
  IconPack.remix: {},
};

const Set<ShellGlyph> _materialFallbacks = {
  ShellGlyph.pullRequest,
  ShellGlyph.github,
  ShellGlyph.linux,
  ShellGlyph.googleDrive,
};

/// The family each pack's own glyphs are set in.
String _familyOf(IconPack pack) => switch (pack) {
  IconPack.fontAwesome => '',
  IconPack.materialRounded => 'MaterialSymbolsRounded',
  IconPack.materialOutlined => 'MaterialSymbolsOutlined',
  IconPack.materialSharp => 'MaterialSymbolsSharp',
  IconPack.lucide => 'Lucide',
  IconPack.remix => 'remix',
};

Widget _host(Widget child, {IconPack? pack}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: pack == null
        ? child
        : ThemeScope(
            theme: ThemeConfig(iconPack: pack),
            child: child,
          ),
  ),
);

void main() {
  group('IconPack', () {
    test('every slug round-trips, and an unknown one is null', () {
      for (final pack in IconPack.values) {
        expect(IconPack.fromSlug(pack.slug), pack);
      }
      expect(IconPack.fromSlug('nope'), isNull);
      expect(IconPack.fromSlug(null), isNull);
    });

    test('slugs are distinct', () {
      final slugs = {for (final pack in IconPack.values) pack.slug};
      expect(slugs, hasLength(IconPack.values.length));
    });

    test('only the default pack is drawn at its own size', () {
      expect(IconPack.fontAwesome.opticalScale, 1.0);
      for (final pack in IconPack.values) {
        if (pack == IconPack.fontAwesome) continue;
        expect(pack.opticalScale, greaterThan(1.0), reason: pack.slug);
      }
    });
  });

  group('the tables', () {
    test('each pack falls back for exactly the pinned glyphs', () {
      for (final pack in IconPack.values) {
        final missing = {
          for (final glyph in ShellGlyph.values)
            if (packGlyph(glyph, pack) == null) glyph,
        };
        expect(missing, _kFallbacks[pack], reason: pack.slug);
      }
    });

    test("a pack's own glyphs come from its own font", () {
      for (final pack in IconPack.values) {
        if (pack == IconPack.fontAwesome) continue;
        for (final glyph in ShellGlyph.values) {
          final own = packGlyph(glyph, pack);
          if (own == null) continue;
          expect(own, isA<FontGlyph>(), reason: '${pack.slug} $glyph');
          expect(
            (own as FontGlyph).data.fontFamily,
            _familyOf(pack),
            reason: '${pack.slug} $glyph',
          );
        }
      }
    });

    test('a fallback is the default glyph, at the default size', () {
      for (final pack in IconPack.values) {
        for (final glyph in _kFallbacks[pack]!) {
          final resolved = resolveGlyph(glyph, pack);
          expect(resolved.glyph, fontAwesomeGlyph(glyph));
          expect(resolved.scale, 1.0);
        }
      }
    });

    test('the default table is one to one with what the shell drew', () {
      // One member per glyph: two members drawing the same constant would
      // mean the rename folded two call sites' choices into one, which is a
      // decision this table exists not to make.
      final drawn = <Object>{};
      for (final glyph in ShellGlyph.values) {
        final g = fontAwesomeGlyph(glyph);
        final key = switch (g) {
          FaGlyph(:final data) => data,
          FontGlyph(:final data) => data,
        };
        expect(drawn.add(key), isTrue, reason: '$glyph repeats a glyph');
      }
    });

    test('the default pack draws what the call sites named', () {
      // A sample, one from each family the default table mixes: Font Awesome's
      // solid and regular styles, its brands, and the sky cards' Material
      // Symbols.
      expect(
        fontAwesomeGlyph(ShellGlyph.close),
        const FaGlyph(FontAwesomeIcons.xmark),
      );
      expect(
        fontAwesomeGlyph(ShellGlyph.folderFilled),
        const FaGlyph(FontAwesomeIcons.solidFolder),
      );
      expect(
        fontAwesomeGlyph(ShellGlyph.github),
        const FaGlyph(FontAwesomeIcons.github),
      );
      final pin = fontAwesomeGlyph(ShellGlyph.placeMarker) as FontGlyph;
      expect(pin.data.fontFamily, 'MaterialSymbolsOutlined');
      expect(pin.fill, isNull);
    });

    test('Material draws a solid glyph by its fill axis', () {
      final folder =
          packGlyph(ShellGlyph.folder, IconPack.materialRounded) as FontGlyph;
      final filled =
          packGlyph(ShellGlyph.folderFilled, IconPack.materialRounded)
              as FontGlyph;
      expect(filled.data, folder.data);
      expect(folder.fill, isNull);
      expect(filled.fill, 1);
    });

    test('brands are brands', () {
      expect(
        {
          for (final g in ShellGlyph.values)
            if (g.isBrand) g,
        },
        {ShellGlyph.github, ShellGlyph.linux, ShellGlyph.googleDrive},
      );
    });
  });

  test('no font is named outside lib/icons/packs/', () {
    // The rule that makes the key mean anything: a call site that names a
    // font's constants has opted its surface out of the user's choice.
    final named = RegExp(
      r'\b(FontAwesomeIcons|Symbols|LucideIcons\w*|'
      r'RemixIcons|Remix)\.\w',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.startsWith('lib/icons/packs/')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (named.hasMatch(line)) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  group('ShellIcon', () {
    testWidgets('with no theme, draws Font Awesome', (tester) async {
      await tester.pumpWidget(
        _host(const ShellIcon(ShellGlyph.close, size: 12)),
      );
      expect(find.byType(FaIcon), findsOneWidget);
      expect(findGlyph(ShellGlyph.close), findsOneWidget);
    });

    testWidgets("draws in the theme's pack", (tester) async {
      await tester.pumpWidget(
        _host(
          const ShellIcon(ShellGlyph.close, size: 12),
          pack: IconPack.lucide,
        ),
      );
      expect(find.byType(FaIcon), findsNothing);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon!.fontFamily, 'Lucide');
      expect(icon.size, closeTo(12 * IconPack.lucide.opticalScale, 1e-9));
    });

    testWidgets('follows a change of pack', (tester) async {
      const icon = ShellIcon(ShellGlyph.search, size: 14);
      await tester.pumpWidget(_host(icon, pack: IconPack.fontAwesome));
      expect(find.byType(FaIcon), findsOneWidget);

      await tester.pumpWidget(_host(icon, pack: IconPack.remix));
      expect(find.byType(FaIcon), findsNothing);
      expect(tester.widget<Icon>(find.byType(Icon)).icon!.fontFamily, 'remix');
    });

    testWidgets('the box is the requested size under every pack', (
      tester,
    ) async {
      for (final pack in IconPack.values) {
        if (pack == IconPack.fontAwesome) continue;
        await tester.pumpWidget(
          _host(const ShellIcon(ShellGlyph.bell, size: 16), pack: pack),
        );
        expect(
          tester.getSize(find.byType(ShellIcon)),
          const Size(16, 16),
          reason: pack.slug,
        );
      }
    });

    testWidgets('a fallback is drawn as the default draws it', (tester) async {
      await tester.pumpWidget(
        _host(
          const ShellIcon(ShellGlyph.github, size: 12),
          pack: IconPack.lucide,
        ),
      );
      expect(find.byType(FaIcon), findsOneWidget);
    });

    testWidgets('a Material pack fills a solid glyph and sizes its optics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ShellIcon(ShellGlyph.folderFilled, size: 20),
          pack: IconPack.materialSharp,
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon!.fontFamily, 'MaterialSymbolsSharp');
      expect(icon.fill, 1);
      expect(icon.opticalSize, 20 * IconPack.materialSharp.opticalScale);
    });

    testWidgets("a call site's own axes win", (tester) async {
      await tester.pumpWidget(
        _host(
          const ShellIcon(
            ShellGlyph.folderFilled,
            size: 12,
            fill: 0.5,
            opticalSize: 24,
          ),
          pack: IconPack.materialRounded,
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.fill, 0.5);
      expect(icon.opticalSize, 24);
    });

    testWidgets('an explicit pack beats the theme', (tester) async {
      await tester.pumpWidget(
        _host(
          const ShellIcon(
            ShellGlyph.close,
            size: 12,
            pack: IconPack.fontAwesome,
          ),
          pack: IconPack.lucide,
        ),
      );
      expect(find.byType(FaIcon), findsOneWidget);
    });
  });

  group('icon_pack', () {
    test('defaults to Font Awesome', () {
      expect(const ThemeConfig().iconPack, IconPack.fontAwesome);
      expect(ThemeConfig.fromMap(const {}).iconPack, IconPack.fontAwesome);
    });

    test('reads every slug', () {
      for (final pack in IconPack.values) {
        expect(ThemeConfig.fromMap({'icon_pack': pack.slug}).iconPack, pack);
      }
    });

    test('a bad value costs the key and nothing else', () {
      for (final bad in <Object>[
        'nope',
        3,
        true,
        const ['lucide'],
      ]) {
        final theme = ThemeConfig.fromMap({'icon_pack': bad, 'font': 'Inter'});
        expect(theme.iconPack, IconPack.fontAwesome, reason: '$bad');
        expect(theme.fontFamily, 'Inter', reason: '$bad');
      }
    });

    test('is written, and takes part in equality', () {
      const lucide = ThemeConfig(iconPack: IconPack.lucide);
      expect(lucide.toMap()['icon_pack'], 'lucide');
      expect(ThemeConfig.fromMap(lucide.toMap()), lucide);
      expect(lucide == const ThemeConfig(), isFalse);
    });
  });
}
