import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_scope.dart';

/// Records what would have been asked of systemd, and can be told to refuse.
class _FakeStarter {
  _FakeStarter({this.error});

  /// Thrown instead of starting a scope, when set.
  Object? error;

  final List<({String unitName, int pid, String description})> calls = [];

  Future<void> call({
    required String unitName,
    required int pid,
    required String description,
  }) async {
    calls.add((unitName: unitName, pid: pid, description: description));
    final failure = error;
    if (failure != null) throw failure;
  }
}

DBusMethodResponseException _busError(String name) =>
    DBusMethodResponseException(DBusMethodErrorResponse(name));

void main() {
  group('appScopeUnitName', () {
    test('is a systemd app scope named for the launcher, app and pid', () {
      expect(
        appScopeUnitName(appId: 'org.gnome.Nautilus.desktop', pid: 4321),
        r'app-graceful\x2dshell-org.gnome.Nautilus-4321.scope',
      );
    });

    test('escapes a dash in the app id, which separates unit name segments',
        () {
      expect(
        appScopeUnitName(appId: 'google-chrome.desktop', pid: 7),
        r'app-graceful\x2dshell-google\x2dchrome-7.scope',
      );
    });

    test('replaces what systemd will not accept in a unit name', () {
      expect(
        appScopeUnitName(appId: 'my app/v2!.desktop', pid: 9),
        r'app-graceful\x2dshell-my_app_v2_-9.scope',
      );
    });

    test('an appinfo with no id still gets a name', () {
      expect(appScopeUnitName(appId: '', pid: 11),
          r'app-graceful\x2dshell-app-11.scope');
      expect(appScopeUnitName(appId: '   ', pid: 11),
          r'app-graceful\x2dshell-app-11.scope');
    });

    test('a preposterous id is truncated rather than rejected by systemd', () {
      final name = appScopeUnitName(appId: 'x' * 500, pid: 3);
      expect(name.length, lessThan(255));
      expect(name, endsWith('-3.scope'));
    });
  });

  group('AppScopeAdopter', () {
    test('adopts a launched pid into a scope of its own', () async {
      final starter = _FakeStarter();
      final adopter = AppScopeAdopter(start: starter.call);

      expect(
        await adopter.adopt(
            pid: 1234, appId: 'firefox.desktop', appName: 'Firefox'),
        isTrue,
      );
      expect(starter.calls.single.pid, 1234);
      expect(starter.calls.single.unitName,
          r'app-graceful\x2dshell-firefox-1234.scope');
      expect(starter.calls.single.description, contains('Firefox'));
    });

    test('an appinfo with no id is named after the application', () async {
      final starter = _FakeStarter();
      final adopter = AppScopeAdopter(start: starter.call);

      expect(
        await adopter.adopt(pid: 12, appId: '', appName: 'Text Editor'),
        isTrue,
      );
      expect(starter.calls.single.unitName,
          r'app-graceful\x2dshell-Text_Editor-12.scope');
    });

    test('a pid GIO did not report is not asked about', () async {
      final starter = _FakeStarter();
      final adopter = AppScopeAdopter(start: starter.call);

      expect(await adopter.adopt(pid: 0, appId: 'firefox.desktop'), isFalse);
      expect(starter.calls, isEmpty);
    });

    test('a session with no systemd user manager is asked exactly once',
        () async {
      final starter = _FakeStarter(
          error: _busError('org.freedesktop.DBus.Error.ServiceUnknown'));
      final adopter = AppScopeAdopter(start: starter.call);

      expect(await adopter.adopt(pid: 1, appId: 'a'), isFalse);
      expect(adopter.unavailable, isTrue);
      expect(await adopter.adopt(pid: 2, appId: 'b'), isFalse);
      expect(starter.calls, hasLength(1));
    });

    test('one refused launch does not stop the next one', () async {
      final starter =
          _FakeStarter(error: _busError('org.freedesktop.systemd1.NoSuchUnit'));
      final adopter = AppScopeAdopter(start: starter.call);

      expect(await adopter.adopt(pid: 1, appId: 'a'), isFalse);
      expect(adopter.unavailable, isFalse);

      starter.error = null;
      expect(await adopter.adopt(pid: 2, appId: 'b'), isTrue);
      expect(starter.calls, hasLength(2));
    });

    test('an unreachable bus gives up rather than failing every launch',
        () async {
      final starter = _FakeStarter(error: StateError('no session bus'));
      final adopter = AppScopeAdopter(start: starter.call);

      expect(await adopter.adopt(pid: 1, appId: 'a'), isFalse);
      expect(adopter.unavailable, isTrue);
      expect(await adopter.adopt(pid: 2, appId: 'b'), isFalse);
      expect(starter.calls, hasLength(1));
    });

    test('a launch never throws out of the adopter', () async {
      final adopter = AppScopeAdopter(start: ({
        required String unitName,
        required int pid,
        required String description,
      }) =>
          throw Exception('boom'));
      expect(await adopter.adopt(pid: 1, appId: 'a'), isFalse);
    });
  });
}
