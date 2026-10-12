// DefaultAppsStore over a fake GIO: the lease, what a choice writes, and that
// every failure is a visible state.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/default_apps/default_app_associations.dart';
import 'package:moonswing/default_apps/default_app_model.dart';
import 'package:moonswing/default_apps/default_apps_store.dart';

import 'default_apps_fakes.dart';

DefaultAppCategory _category(String id) =>
    kDefaultAppCategories.firstWhere((c) => c.id == id);

void main() {
  late FakeAssociations gio;
  late ChangeNotifier changes;
  late DefaultAppsStore store;
  late int notifications;

  setUp(() {
    gio = FakeAssociations();
    changes = ChangeNotifier();
    store = DefaultAppsStore(associations: gio, changes: changes);
    notifications = 0;
    store.addListener(() => notifications++);
  });

  tearDown(() {
    store.dispose();
    changes.dispose();
  });

  /// Acquires and lets the deferred first read land.
  Future<void> acquire() async {
    store.acquire();
    await Future<void>.delayed(Duration.zero);
  }

  group('the lease', () {
    test('acquire reads later, never synchronously', () async {
      store.acquire();
      expect(notifications, 0);
      expect(store.status, DefaultAppsStatus.loading);
      await Future<void>.delayed(Duration.zero);
      expect(store.status, DefaultAppsStatus.ready);
      expect(notifications, 1);
      expect(store.categoryChoice(_category('browser'))?.current, chromium);
      expect(store.userListPath, '/home/me/.config/mimeapps.list');
    });

    test('listens for changes only while leased', () async {
      await acquire();
      gio.user['x-scheme-handler/https'] = 'firefox.desktop';
      changes.notifyListeners();
      expect(store.categoryChoice(_category('browser'))?.current, firefox);

      store.release();
      gio.user['x-scheme-handler/https'] = 'chromium.desktop';
      final before = notifications;
      changes.notifyListeners();
      expect(notifications, before);
      expect(store.categoryChoice(_category('browser'))?.current, firefox);
    });

    test('a change that moved nothing does not notify', () async {
      await acquire();
      final before = notifications;
      changes.notifyListeners();
      expect(notifications, before);
    });
  });

  group('a category choice', () {
    test('offers what declares the primary type, sorted by name', () async {
      await acquire();
      final browser = store.categoryChoice(_category('browser'))!;
      expect(browser.options, [chromium, firefox]);
      expect(browser.userSet, isFalse);
      // Nothing declares a directory here.
      expect(store.categoryChoice(_category('files'))!.options, isEmpty);
      expect(store.categoryChoice(_category('files'))!.current, isNull);
    });

    test(
      'claims every type the category covers that the app declares',
      () async {
        await acquire();
        expect(store.setCategoryDefault(_category('browser'), firefox), isTrue);
        expect(gio.writes, [
          'x-scheme-handler/https=firefox.desktop',
          'x-scheme-handler/http=firefox.desktop',
          'text/html=firefox.desktop',
        ]);
        final browser = store.categoryChoice(_category('browser'))!;
        expect(browser.current, firefox);
        expect(browser.userSet, isTrue);
        expect(store.error, isEmpty);
      },
    );

    test('a family row claims each declared member of the family', () async {
      await acquire();
      store.setCategoryDefault(_category('images'), loupe);
      expect(gio.writes, [
        'image/jpeg=loupe.desktop',
        'image/png=loupe.desktop',
        'image/webp=loupe.desktop',
      ]);
    });

    test('a write that does not take says why', () async {
      gio.pinned['x-scheme-handler/https'] = 'chromium.desktop';
      await acquire();
      expect(store.setCategoryDefault(_category('browser'), firefox), isFalse);
      expect(store.errorTitle, 'Firefox was saved but is not in effect');
      expect(store.error, contains('miracle-wm-mimeapps.list'));
      expect(store.error, contains('Chromium'));
      // The read still works, so the pane stays usable.
      expect(store.status, DefaultAppsStatus.ready);
      store.clearError();
      expect(store.error, isEmpty);
    });

    test('a refused write is the banner, with GIO\'s words', () async {
      await acquire();
      gio.failWrite = const DefaultAppException('Permission denied');
      expect(store.setCategoryDefault(_category('browser'), firefox), isFalse);
      expect(store.errorTitle, 'Could not change the default application');
      expect(store.error, 'Permission denied');
    });

    test('reset hands back every covered type the user set', () async {
      await acquire();
      store.setCategoryDefault(_category('images'), loupe);
      gio.user['text/plain'] = 'text-editor.desktop';
      store.resetCategory(_category('images'));
      expect(gio.user.keys, ['text/plain']);
      final images = store.categoryChoice(_category('images'))!;
      expect(images.current, gimp);
      expect(images.userSet, isFalse);
    });
  });

  group('the full list', () {
    test('is read only when asked for', () async {
      await acquire();
      expect(store.types, isNull);
      store.showAllTypes();
      final types = store.types!;
      expect(types.map((t) => t.type), contains('image/x-xcf'));
      expect(
        types.firstWhere((t) => t.type == 'x-scheme-handler/https').description,
        'https: links',
      );
      expect(
        types.firstWhere((t) => t.type == 'image/png').description,
        'PNG image',
      );
    });

    test('a type row reads once and is dropped by a write', () async {
      await acquire();
      final reads = gio.defaultReads;
      expect(store.typeChoice('image/png').current, isNull);
      expect(store.typeChoice('image/png').options, [gimp, loupe]);
      expect(gio.defaultReads, reads + 1);

      expect(store.setTypeDefault('image/png', loupe), isTrue);
      expect(gio.writes, ['image/png=loupe.desktop']);
      final png = store.typeChoice('image/png');
      expect(png.current, loupe);
      expect(png.userSet, isTrue);

      store.resetType('image/png');
      expect(store.typeChoice('image/png').current, isNull);
    });
  });

  group('a failed read', () {
    test('is a visible state with a retry', () async {
      gio.failReads = ArgumentError('Couldn\'t resolve native function');
      await acquire();
      expect(store.status, DefaultAppsStatus.failed);
      expect(store.errorTitle, 'Default applications unavailable');
      expect(store.error, contains('resolve native function'));

      gio.failReads = null;
      store.retry();
      expect(store.status, DefaultAppsStatus.ready);
      expect(store.error, isEmpty);
      expect(store.categoryChoice(_category('browser'))?.current, chromium);
    });

    test('an unreadable type row shows no handler', () async {
      await acquire();
      gio.failReads = StateError('boom');
      final choice = store.typeChoice('image/png');
      expect(choice.current, isNull);
      expect(choice.options, isEmpty);
    });
  });
}
