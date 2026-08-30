import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/keyboard/locale1_client.dart';

void main() {
  test('polkit interaction is its own kind', () {
    expect(
      mapLocale1Error(
        'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired',
        '',
      ).kind,
      Locale1FailureKind.interactionRequired,
    );
  });

  test('a refusal and a missing polkit agent are the same answer', () {
    // Deliberate: polkit returns AccessDenied for both, so the two are
    // indistinguishable at the wire and the wording has to cover them.
    for (final name in const [
      'org.freedesktop.DBus.Error.AccessDenied',
      'org.freedesktop.DBus.Error.AuthFailed',
      'org.freedesktop.DBus.Error.NotSupported',
    ]) {
      expect(mapLocale1Error(name, '').kind, Locale1FailureKind.denied,
          reason: name);
    }
    expect(
      mapLocale1Error('org.freedesktop.DBus.Error.AccessDenied', '').message,
      contains('administrator approval'),
    );
  });

  test('a bus that is not there is unavailable', () {
    for (final name in const [
      'org.freedesktop.DBus.Error.ServiceUnknown',
      'org.freedesktop.DBus.Error.NameHasNoOwner',
      'org.freedesktop.DBus.Error.NoReply',
      'org.freedesktop.DBus.Error.Timeout',
      'org.freedesktop.DBus.Error.TimedOut',
      'org.freedesktop.DBus.Error.NoServer',
      'org.freedesktop.DBus.Error.Disconnected',
    ]) {
      expect(mapLocale1Error(name, '').kind, Locale1FailureKind.unavailable,
          reason: name);
    }
  });

  test('anything else keeps its own detail, and never renders empty', () {
    final named = mapLocale1Error('com.example.Whatever', 'it went wrong');
    expect(named.kind, Locale1FailureKind.failed);
    expect(named.message, 'it went wrong');
    expect(mapLocale1Error('', '').message, isNotEmpty);
  });
}
