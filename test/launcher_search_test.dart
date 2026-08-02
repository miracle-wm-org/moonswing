import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/launcher/app_search.dart';

AppEntry _app(
  String name, {
  String? id,
  String genericName = '',
  List<String> keywords = const [],
}) =>
    AppEntry(
      id: id ?? name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      iconName: '',
      categories: const [],
      genericName: genericName,
      keywords: keywords,
      appInfo: ffi.nullptr,
    );

List<String> _names(List<AppEntry> entries) =>
    [for (final entry in entries) entry.name];

void main() {
  group('rankApps', () {
    test('an empty query lists the index in its own order', () {
      final apps = [_app('Files'), _app('Ardour')]
          .map(SearchableApp.new)
          .toList();
      expect(_names(rankApps(apps, '')), ['Files', 'Ardour']);
      expect(_names(rankApps(apps, '   ')), ['Files', 'Ardour']);
    });

    test('exact beats prefix beats word-start beats substring', () {
      final apps = [
        _app('Xcodebuild'), // substring, mid-word
        _app('Visual Studio Code'), // word-start
        _app('Codeblocks'), // prefix
        _app('Code'), // exact
      ].map(SearchableApp.new).toList();

      expect(_names(rankApps(apps, 'code')), [
        'Code',
        'Codeblocks',
        'Visual Studio Code',
        'Xcodebuild',
      ]);
    });

    test('a name hit always outranks a generic-name or keyword hit', () {
      final apps = [
        _app('Konsole', keywords: ['terminal']),
        _app('Kitty', genericName: 'Terminal emulator'),
        _app('Terminal'),
      ].map(SearchableApp.new).toList();

      // Even though Konsole's keyword and Kitty's generic name match exactly,
      // the app actually called Terminal comes first.
      expect(_names(rankApps(apps, 'terminal')).first, 'Terminal');
      expect(_names(rankApps(apps, 'terminal')), contains('Kitty'));
      expect(_names(rankApps(apps, 'terminal')), contains('Konsole'));
    });

    test('a generic-name hit outranks a keyword hit', () {
      final apps = [
        _app('Alpha', keywords: ['browser']),
        _app('Beta', genericName: 'Browser'),
      ].map(SearchableApp.new).toList();
      expect(_names(rankApps(apps, 'browser')), ['Beta', 'Alpha']);
    });

    test('the desktop id is searchable, and ranks last', () {
      final apps = [
        _app('Nautilus', id: 'org.gnome.Nautilus'),
        _app('Gnome Something'),
      ].map(SearchableApp.new).toList();

      expect(_names(rankApps(apps, 'gnome')), ['Gnome Something', 'Nautilus']);
    });

    test('matching is case-insensitive on both sides', () {
      final apps = [_app('GIMP')].map(SearchableApp.new).toList();
      expect(_names(rankApps(apps, 'gimp')), ['GIMP']);
      expect(_names(rankApps(apps, 'GiMp')), ['GIMP']);
    });

    test('non-matches are dropped', () {
      final apps = [_app('Firefox'), _app('Thunderbird')]
          .map(SearchableApp.new)
          .toList();
      expect(rankApps(apps, 'zzz'), isEmpty);
    });

    test('equal scores break by name, not by index order', () {
      final apps = [_app('Zebra Notes'), _app('Apple Notes')]
          .map(SearchableApp.new)
          .toList();
      expect(_names(rankApps(apps, 'notes')), ['Apple Notes', 'Zebra Notes']);
    });

    test('the result cap is respected', () {
      final apps = [
        for (var i = 0; i < 50; i++) _app('App $i'),
      ].map(SearchableApp.new).toList();

      expect(rankApps(apps, 'app', limit: 5), hasLength(5));
      expect(rankApps(apps, '', limit: 5), hasLength(5));
    });
  });
}
