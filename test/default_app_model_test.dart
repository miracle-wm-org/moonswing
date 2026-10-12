// The Default Apps pane's pure half: the category table, the claim rule, the
// `mimeapps.list` reader and the full list's naming and filter.

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/default_apps/default_app_model.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/overlay/settings_route.dart';

DefaultAppCategory _category(String id) =>
    kDefaultAppCategories.firstWhere((c) => c.id == id);

void main() {
  group('the category table', () {
    test('ids are unique and every primary type is a media type', () {
      final ids = <String>{};
      for (final category in kDefaultAppCategories) {
        expect(
          ids.add(category.id),
          isTrue,
          reason: 'duplicate ${category.id}',
        );
        expect(category.primaryType, contains('/'));
        expect(category.label, isNotEmpty);
        expect(category.description, isNotEmpty);
        for (final type in category.alsoTypes) {
          expect(type, contains('/'));
          expect(type, isNot(category.primaryType));
        }
        final family = category.family;
        if (family != null) {
          expect(family, endsWith('/'));
          // A family that did not contain the primary type would claim a
          // different kind of file from the one the row reads.
          expect(category.primaryType, startsWith(family));
        }
      }
    });

    // Two rows claiming one type would fight: choosing either would quietly
    // change what the other row shows.
    test('no two rows claim the same type', () {
      final owners = <String, String>{};
      for (final category in kDefaultAppCategories) {
        for (final type in [category.primaryType, ...category.alsoTypes]) {
          expect(
            owners[type],
            isNull,
            reason: '$type is in ${owners[type]} and ${category.id}',
          );
          owners[type] = category.id;
        }
      }
    });

    test('the browser row reads links, not files', () {
      final browser = _category('browser');
      expect(browser.primaryType, 'x-scheme-handler/https');
      expect(browser.alsoTypes, contains('x-scheme-handler/http'));
      expect(browser.alsoTypes, contains('text/html'));
    });

    test('covers a primary, an extra and a family member', () {
      expect(_category('browser').covers('text/html'), isTrue);
      expect(_category('browser').covers('text/plain'), isFalse);
      expect(_category('images').covers('image/webp'), isTrue);
      expect(_category('images').covers('video/mp4'), isFalse);
    });
  });

  group('the search catalogue', () {
    test('has one highlightable row per category, routed to the pane', () {
      expect(
        SettingsCatalog.defaultAppFields.map((f) => f.label).toList(),
        kDefaultAppCategories.map((c) => c.label).toList(),
      );
      for (final category in kDefaultAppCategories) {
        final field = SettingsCatalog.defaultApp(category);
        expect(field.id, 'default_apps.${category.id}');
        expect(field.highlights, isTrue);
        expect(field.route, SettingsRoute.defaultApps);
        expect(SettingsCatalog.all, contains(field));
      }
    });

    test('"browser" and "default" find the pane', () {
      String top(String query) =>
          rankSettings(SettingsCatalog.searchable, query).first.label;
      expect(top('web browser'), 'Web browser');
      expect(
        rankSettings(
          SettingsCatalog.searchable,
          'default applications',
        ).map((f) => f.label),
        contains('Default applications'),
      );
      expect(
        rankSettings(SettingsCatalog.searchable, 'pdf').map((f) => f.label),
        contains('PDF documents'),
      );
    });
  });

  group('typesToClaim', () {
    test('always claims the primary type', () {
      expect(typesToClaim(_category('files'), const []), ['inode/directory']);
    });

    test('claims an extra type only where the application declares it', () {
      final claimed = typesToClaim(_category('browser'), const [
        'text/html',
        'x-scheme-handler/http',
        'x-scheme-handler/https',
        'image/png',
      ]);
      expect(claimed, [
        'x-scheme-handler/https',
        'x-scheme-handler/http',
        'text/html',
      ]);
    });

    test('claims every declared member of a family, sorted, once', () {
      final claimed = typesToClaim(_category('images'), const [
        'image/webp',
        'image/jpeg',
        'image/png',
        'image/png',
        'application/pdf',
      ]);
      expect(claimed, ['image/jpeg', 'image/png', 'image/webp']);
    });
  });

  group('parseMimeAppsDefaults', () {
    test('reads the [Default Applications] group only', () {
      final defaults = parseMimeAppsDefaults('''
# A comment
[Added Associations]
text/markdown=org.gnome.TextEditor.desktop;

[Default Applications]
x-scheme-handler/https=firefox.desktop
text/plain=org.gnome.TextEditor.desktop;code.desktop;
  image/png = org.gnome.Loupe.desktop

[Removed Associations]
image/jpeg=gimp.desktop;
''');
      expect(defaults, {'x-scheme-handler/https', 'text/plain', 'image/png'});
    });

    test('a malformed or empty line costs that line', () {
      final defaults = parseMimeAppsDefaults('''
[Default Applications]
not a key value pair
=firefox.desktop
nonsense=firefox.desktop
text/plain=
text/x-c=;
application/pdf=org.gnome.Evince.desktop
''');
      expect(defaults, {'application/pdf'});
    });

    test('an empty file names nothing', () {
      expect(parseMimeAppsDefaults(''), isEmpty);
    });
  });

  group('describeContentType', () {
    test('names a URL scheme after its links', () {
      expect(
        describeContentType(
          'x-scheme-handler/mailto',
          'x-scheme-handler/mailto type',
        ),
        'mailto: links',
      );
    });

    test('uses GIO\'s description, and the type when there is none', () {
      expect(describeContentType('image/png', 'PNG image'), 'PNG image');
      expect(describeContentType('text/x-odd', '  '), 'text/x-odd');
    });
  });

  group('the full list', () {
    final types = sortContentTypes(const [
      ContentTypeInfo(type: 'image/png', description: 'PNG image'),
      ContentTypeInfo(type: 'text/markdown', description: 'Markdown document'),
      ContentTypeInfo(
        type: 'x-scheme-handler/mailto',
        description: 'mailto: links',
      ),
      ContentTypeInfo(type: 'message/rfc822', description: 'email message'),
      ContentTypeInfo(type: 'image/apng', description: 'PNG image'),
    ]);

    test('sorts by description, case-insensitively, then by type', () {
      expect(types.map((t) => t.type).toList(), [
        'message/rfc822',
        'x-scheme-handler/mailto',
        'text/markdown',
        'image/apng',
        'image/png',
      ]);
    });

    test('filters on every word, across description and type', () {
      List<String> filter(String query) =>
          filterContentTypes(types, query).map((t) => t.type).toList();
      expect(filter(''), hasLength(5));
      expect(filter('  '), hasLength(5));
      expect(filter('image/png'), ['image/png']);
      expect(filter('PNG'), ['image/apng', 'image/png']);
      expect(filter('png image apng'), ['image/apng']);
      expect(filter('mail'), ['message/rfc822', 'x-scheme-handler/mailto']);
      expect(filter('nothing like it'), isEmpty);
    });
  });

  group('handlerOptions', () {
    const firefox = HandlerApp(id: 'firefox.desktop', name: 'Firefox');
    const chromium = HandlerApp(id: 'chromium.desktop', name: 'chromium');
    const lynx = HandlerApp(id: 'lynx.desktop', name: 'Lynx');

    test('sorts by name and drops duplicates', () {
      expect(handlerOptions([firefox, lynx, chromium, firefox], null), [
        chromium,
        firefox,
        lynx,
      ]);
    });

    test('keeps a current default GIO would not offer', () {
      expect(handlerOptions([firefox], lynx), [firefox, lynx]);
    });
  });
}
