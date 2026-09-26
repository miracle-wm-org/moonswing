// The settings search index: what is in it, how it ranks, and the seam that
// carries a picked result to the row.
//
// The catalogue's invariants are the load-bearing half. It is a hand-written
// table of destinations, and the two ways such a table rots are a renamed
// category leaving a result pointing nowhere and two entries sharing an id —
// neither of which the compiler can see, and both of which these tests can.

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/overlay/settings/miracle.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';

/// The sidebar ids `_SettingsSidebar` offers, and the only categories a route
/// can name.
const _sidebarCategories = {
  'network',
  'bluetooth',
  'display',
  'audio',
  'keyboard',
  'miracle',
  'accounts',
  'shell',
};

/// The Shell categories, as `shell.dart` titles them. Spelled here rather than
/// exported, because what is being pinned is that the two agree — see the
/// `isShellCategory` check below, which is the one that actually reads them.
const _shellCategories = {
  'Appearance',
  'Module Settings',
  'Panels & Layout',
  'Background',
  'Desktop',
  'Lock Screen',
  'Power Button',
  'Calendar',
};

/// The Window Manager categories, as `miracle.dart` titles them. Spelled here
/// for the same reason the Shell ones are: what is being pinned is that the two
/// agree, and `isMiracleCategory` below is what actually reads them.
const _miracleCategories = {
  'General',
  'Gaps & Borders',
  'Animations',
  'Key Bindings',
  'Mouse',
  'Touchpad',
  'Keyboard',
  'Accessibility',
  'Workspaces',
  'Startup',
  'Includes & Plugins',
};

SearchableSetting _searchable(
  String label, {
  String description = '',
  List<String> tags = const [],
}) => SearchableSetting(
  shellField(
    'test.$label',
    label,
    section: 'Test',
    description: description,
    tags: tags,
  ),
);

/// The labels [rankSettings] answers with, in order.
List<String> _labels(List<SettingsField> fields) => [
  for (final field in fields) field.label,
];

void main() {
  group('SettingsCatalog', () {
    test('every non-empty id is unique', () {
      final seen = <String, String>{};
      for (final field in SettingsCatalog.all) {
        if (field.id.isEmpty) continue;
        expect(
          seen.containsKey(field.id),
          isFalse,
          reason:
              'duplicate id ${field.id}: "${seen[field.id]}" and '
              '"${field.label}". Two rows answering to one id would both '
              'flash, and the search would scroll to whichever mounted first.',
        );
        seen[field.id] = field.label;
      }
    });

    test('every entry says what it is and what it does', () {
      for (final field in SettingsCatalog.all) {
        expect(field.label, isNotEmpty);
        // The description is half of what the index matches on and the whole
        // of the result row's second line, so an entry without one is a row
        // that can only be found by its own label.
        expect(
          field.description,
          isNotEmpty,
          reason: '${field.label} has no description',
        );
        expect(field.section, isNotEmpty);
      }
    });

    test('every route names a real destination', () {
      for (final field in SettingsCatalog.all) {
        expect(field.route.tab, 'settings');
        expect(
          _sidebarCategories,
          contains(field.route.category),
          reason: '${field.label} points at sidebar "${field.route.category}"',
        );
        final shellCategory = field.route.shellCategory;
        if (shellCategory != null) {
          expect(field.route.category, 'shell');
          expect(
            _shellCategories,
            contains(shellCategory),
            reason: '${field.label} points at Shell category "$shellCategory"',
          );
        }
        final miracleCategory = field.route.miracleCategory;
        if (miracleCategory == null) continue;
        expect(field.route.category, 'miracle');
        expect(
          _miracleCategories,
          contains(miracleCategory),
          reason:
              '${field.label} points at Window Manager category '
              '"$miracleCategory"',
        );
      }
    });

    // The pane's own list, read from the pane rather than spelled twice — the
    // half of the check the constant set above cannot make.
    test('the Window Manager categories are the ones the pane offers', () {
      expect(miracleCategoryTitles.toSet(), _miracleCategories);
      for (final title in _miracleCategories) {
        expect(isMiracleCategory(title), isTrue, reason: title);
      }
      expect(isMiracleCategory('Nonexistent'), isFalse);
    });

    // `settings/miracle/` addresses each row by the setting it edits, and the
    // ids are what the search jumps to. A row under another pane's prefix
    // would flash on a page that does not contain it.
    test('a Window Manager row id names a miracle setting', () {
      for (final field in SettingsCatalog.miracleFields) {
        expect(field.route.category, 'miracle');
        expect(field.route.shellCategory, isNull);
        expect(field.route.miracleCategory, isNotNull);
        if (field.id.isEmpty) continue;
        expect(field.id, startsWith('miracle.'));
      }
      expect(
        rankSettings(SettingsCatalog.searchable, 'action key')
            .map((f) => f.label),
        contains('Action Key'),
      );
      expect(
        rankSettings(SettingsCatalog.searchable, 'gaps').map((f) => f.label),
        contains('Inner gap, horizontal'),
      );
    });

    // The `_pane` entries are the hardware panes, which are lists of whatever
    // the machine has rather than tables of named rows. A field-level entry
    // that lost its id would silently become one of those — it would still
    // navigate, and would simply stop highlighting anything.
    test('only the pane-level entries decline to highlight', () {
      final unhighlightable = [
        for (final field in SettingsCatalog.all)
          if (!field.highlights) field.label,
      ];
      expect(
        unhighlightable,
        containsAll(<String>[
          'Theme',
          'Panel modules',
          'Wallpapers',
          'Pinned items',
          'Wi-Fi and wired networks',
          'Bluetooth devices',
          'Displays and resolution',
          'Sound output and input',
          'Keyboard layout',
          'Google accounts',
          // The Window Manager pane's collections: a list of key bindings or
          // of startup applications is not a row anything can scroll to.
          'Animated events',
          'Custom key bindings',
          'Built-in command overrides',
          'Startup applications',
          'Environment variables',
          'Workspaces',
          'Included files',
          'Plugins',
        ]),
      );
      expect(unhighlightable, hasLength(18));
    });

    // `modules.dart` builds each row's config path by splitting the id on its
    // dots, so an id that is not a `[modules.*]` path would write the setting
    // to a key nothing reads.
    test('a module row id is its config path', () {
      for (final field in SettingsCatalog.moduleFields) {
        expect(field.id, startsWith('modules.'));
        expect(field.id.split('.'), hasLength(3));
        expect(field.route.shellCategory, 'Module Settings');
      }
      // Every module row carries its module's own name among its tags: the
      // group heading is what a user reads the row under, and it is in neither
      // the label nor, for most of them, the description.
      expect(
        rankSettings(SettingsCatalog.searchable, 'clock').map((f) => f.label),
        contains('Show date'),
      );
      expect(
        rankSettings(SettingsCatalog.searchable, 'tray').map((f) => f.label),
        contains('Hidden items'),
      );
    });

    test('the palette is spelled once, and the pane reads it', () {
      final keys = [for (final c in SettingsCatalog.themeColors) c.key];
      expect(keys, contains('accent'));
      expect(keys, contains('panel_background'));
      expect(keys.toSet(), hasLength(keys.length));
      for (final colour in SettingsCatalog.themeColors) {
        expect(colour.field.id, 'theme.${colour.key}');
        expect(colour.field.route.shellCategory, 'Appearance');
      }
    });

    test('searchable is folded to lower case, once', () {
      expect(SettingsCatalog.searchable, hasLength(SettingsCatalog.all.length));
      // Identity, not equality: the fold is memoised in a static, so a shell
      // whose user never searches builds it never and one who searches builds
      // it once.
      expect(
        identical(SettingsCatalog.searchable, SettingsCatalog.searchable),
        isTrue,
      );
      for (final setting in SettingsCatalog.searchable) {
        expect(setting.label, setting.label.toLowerCase());
        expect(setting.description, setting.description.toLowerCase());
      }
    });
  });

  group('rankSettings', () {
    test('an empty query answers nothing at all', () {
      expect(rankSettings(SettingsCatalog.searchable, ''), isEmpty);
      expect(rankSettings(SettingsCatalog.searchable, '   '), isEmpty);
    });

    test('a hit in the label outranks the same hit anywhere else', () {
      final settings = [
        _searchable('Zebra', description: 'nothing to see'),
        _searchable('Nothing', description: 'the frobnicate of a thing'),
        _searchable('Also nothing', tags: const ['frobnicate']),
        _searchable('Frobnicate', description: 'a label hit'),
      ];
      expect(_labels(rankSettings(settings, 'frobnicate')), [
        'Frobnicate',
        'Nothing',
        'Also nothing',
      ]);
    });

    test('exact beats prefix beats word-start beats substring', () {
      final settings = [
        _searchable('Unfitted'),
        _searchable('Screen fit'),
        _searchable('Fitting'),
        _searchable('Fit'),
      ];
      expect(_labels(rankSettings(settings, 'fit')), [
        'Fit',
        'Fitting',
        'Screen fit',
        'Unfitted',
      ]);
    });

    test('the section is matched, and ranks below every other dimension', () {
      final settings = [
        SearchableSetting(
          shellField('a', 'Nothing', section: 'Widget', description: 'no hit'),
        ),
        SearchableSetting(
          shellField('b', 'Widget', section: 'Other', description: 'a label'),
        ),
      ];
      // The one whose *section* is "Widget" is found, and the one whose label
      // is leads it.
      expect(_labels(rankSettings(settings, 'widget')), ['Widget', 'Nothing']);

      // And in the real catalogue: a category name types like one.
      final lock = rankSettings(SettingsCatalog.searchable, 'lock screen');
      expect(
        lock.map((f) => f.label),
        containsAll(<String>['Blur when unlocking', 'Show name']),
      );
    });

    // The pass that makes a *description* of a setting work when its exact
    // words are spread across the entry.
    test('every word present somewhere is a match, and ranks last', () {
      final settings = [
        _searchable('Wallpaper', description: 'the picture on the desktop'),
        _searchable('Desktop picture'),
      ];
      expect(_labels(rankSettings(settings, 'desktop picture')), [
        'Desktop picture',
        'Wallpaper',
      ]);
    });

    test('a single word that matches nothing is not spread across fields', () {
      final settings = [
        _searchable('Alpha', description: 'beta', tags: const ['gamma']),
      ];
      expect(rankSettings(settings, 'delta'), isEmpty);
      // Both words present, in different dimensions: a match.
      expect(_labels(rankSettings(settings, 'alpha gamma')), ['Alpha']);
      // One of the two absent: not.
      expect(rankSettings(settings, 'alpha delta'), isEmpty);
    });

    test('ties break by label and then section, never by table order', () {
      final forwards = rankSettings(SettingsCatalog.searchable, 'icon size');
      final backwards = rankSettings(
        SettingsCatalog.searchable.reversed.toList(),
        'icon size',
      );
      expect(_labels(forwards), _labels(backwards));
      // Several modules have one, and so does the desktop grid.
      expect(
        forwards.where((f) => f.label == 'Icon size').length,
        greaterThan(1),
      );
    });

    test('the limit caps the card rather than the index', () {
      final all = rankSettings(SettingsCatalog.searchable, 'p', limit: 1000);
      expect(all.length, greaterThan(3));
      expect(
        rankSettings(SettingsCatalog.searchable, 'p', limit: 3),
        hasLength(3),
      );
    });

    test('the queries a user actually types land somewhere sensible', () {
      void expectFirst(String query, String label) {
        final results = rankSettings(SettingsCatalog.searchable, query);
        expect(
          results.isNotEmpty ? results.first.label : '<no results>',
          label,
          reason: 'searching "$query"',
        );
      }

      expectFirst('font size', 'Font size');
      expectFirst('week', 'Week starts on');
      expectFirst('blur', 'Blur when unlocking');

      // Two rows are called some form of "Wallpaper" and the shell must not
      // guess which one is meant: the exact label leads, per the tier rules,
      // and the other is right behind it rather than buried.
      final wallpaper = rankSettings(SettingsCatalog.searchable, 'wallpaper');
      expect(_labels(wallpaper.take(2).toList()), ['Wallpaper', 'Wallpapers']);

      // Reached by a tag alone: neither word is in the label or the
      // description of the row that answers it.
      expectFirst('wifi', 'Wi-Fi and wired networks');
      expectFirst('microphone', 'Sound output and input');
      expectFirst('resolution', 'Displays and resolution');
    });
  });

  group('SettingsHighlightController', () {
    test('a target is handed to exactly one claimant', () {
      final controller = SettingsHighlightController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.target, isNull);
      expect(controller.claim('theme.font'), isFalse);

      controller.jumpTo(SettingsCatalog.font);
      expect(notifications, 1);
      expect(controller.target?.field, SettingsCatalog.font);

      // A row with some other id is not the claimant, and does not consume it.
      expect(controller.claim('theme.font_size'), isFalse);
      expect(controller.claimed, isFalse);

      expect(controller.claim('theme.font'), isTrue);
      expect(controller.claimed, isTrue);
      // The second row carrying the same field — every panel in Panels &
      // Layout renders one "Height" — gets nothing.
      expect(controller.claim('theme.font'), isFalse);
      // Claiming is bookkeeping, not a rebuild.
      expect(notifications, 1);
    });

    test('clearing is what ends the jump, and is idempotent', () {
      final controller = SettingsHighlightController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.jumpTo(SettingsCatalog.lockBlurSigma);
      controller.clear();
      expect(controller.target, isNull);
      expect(notifications, 2);

      controller.clear();
      expect(notifications, 2);
    });

    test('a second jump supersedes the first, unclaimed', () {
      final controller = SettingsHighlightController();
      addTearDown(controller.dispose);

      controller.jumpTo(SettingsCatalog.font);
      expect(controller.claim('theme.font'), isTrue);
      final first = controller.target!.serial;

      controller.jumpTo(SettingsCatalog.font);
      expect(controller.target!.serial, greaterThan(first));
      expect(controller.claimed, isFalse);
      // Picking the same result twice is two jumps: the row is already mounted
      // and has to flash again.
      expect(controller.claim('theme.font'), isTrue);
    });

    // The category view holds its whole page mounted while a target for it is
    // pending, so a target nothing claims — a pane-level result, or a row
    // behind a `ConfigValue` that is not rendering — cannot be allowed to sit
    // there.
    testWidgets('an unclaimed target expires', (tester) async {
      final controller = SettingsHighlightController();
      addTearDown(controller.dispose);

      controller.jumpTo(SettingsCatalog.desktopCellWidth);
      expect(controller.target, isNotNull);

      await tester.pump(kSettingsHighlightTimeout + const Duration(seconds: 1));
      expect(controller.target, isNull);
    });

    testWidgets('a claimed one does not outlive the overlay', (tester) async {
      final controller = SettingsHighlightController();
      controller.jumpTo(SettingsCatalog.font);
      controller.dispose();
      // No pending timer left to fire into a disposed notifier.
      await tester.pump(kSettingsHighlightTimeout + const Duration(seconds: 1));
    });
  });
}
