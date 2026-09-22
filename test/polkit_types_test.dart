import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/polkit/polkit_types.dart';

DBusValue _identity(String kind, Map<String, DBusValue> details) =>
    DBusStruct([DBusString(kind), DBusDict.stringVariant(details)]);

DBusValue _identities(List<DBusValue> entries) => DBusArray(
      DBusSignature('(sa{sv})'),
      entries,
    );

({String username, String displayName})? _lookup(int uid) => switch (uid) {
      0 => (username: 'root', displayName: 'root'),
      1000 => (username: 'ada', displayName: 'Ada Lovelace'),
      1001 => (username: 'svc', displayName: ''),
      _ => null,
    };

void main() {
  group('parsePolkitIdentities', () {
    test('reads unix-user identities in the order polkit listed them', () {
      final parsed = parsePolkitIdentities(
        _identities([
          _identity('unix-user', {'uid': DBusUint32(0)}),
          _identity('unix-user', {'uid': DBusUint32(1000)}),
        ]),
        lookup: _lookup,
      );
      expect(parsed.map((i) => i.username), ['root', 'ada']);
      expect(parsed.last.displayName, 'Ada Lovelace');
    });

    // A group is not something an agent can authenticate: the helper takes a
    // user, and polkit does not say which member of the group it means.
    test('drops unix-group identities', () {
      final parsed = parsePolkitIdentities(
        _identities([
          _identity('unix-group', {'gid': DBusUint32(27)}),
          _identity('unix-user', {'uid': DBusUint32(1000)}),
        ]),
        lookup: _lookup,
      );
      expect(parsed.map((i) => i.uid), [1000]);
    });

    // The TomlReader rule at the other end of the shell: one unusable entry
    // costs that entry, never the prompt.
    test('a uid with no passwd entry costs that identity alone', () {
      final parsed = parsePolkitIdentities(
        _identities([
          _identity('unix-user', {'uid': DBusUint32(4242)}),
          _identity('unix-user', {'uid': DBusUint32(1000)}),
        ]),
        lookup: _lookup,
      );
      expect(parsed.map((i) => i.uid), [1000]);
    });

    test('an entry with no uid, and a repeated uid, are both dropped', () {
      final parsed = parsePolkitIdentities(
        _identities([
          _identity('unix-user', const {}),
          _identity('unix-user', {'uid': DBusUint32(1000)}),
          _identity('unix-user', {'uid': DBusUint32(1000)}),
        ]),
        lookup: _lookup,
      );
      expect(parsed.length, 1);
    });

    // The dict is a{sv}, so the width of the variant is whoever built it.
    test('accepts a uid at any unsigned width', () {
      for (final value in <DBusValue>[
        DBusUint32(1000),
        DBusUint64(1000),
        DBusInt32(1000),
      ]) {
        final parsed = parsePolkitIdentities(
          _identities([
            _identity('unix-user', {'uid': value}),
          ]),
          lookup: _lookup,
        );
        expect(parsed.single.uid, 1000, reason: '$value');
      }
    });

    test('an empty display name falls back to the account name', () {
      final parsed = parsePolkitIdentities(
        _identities([
          _identity('unix-user', {'uid': DBusUint32(1001)}),
        ]),
        lookup: _lookup,
      );
      expect(parsed.single.displayName, 'svc');
    });

    test('a value that is not an identity array is empty, never a throw', () {
      expect(parsePolkitIdentities(null, lookup: _lookup), isEmpty);
      expect(
        parsePolkitIdentities(DBusString('nonsense'), lookup: _lookup),
        isEmpty,
      );
    });
  });

  group('defaultIdentityIndex', () {
    const root = PolkitIdentity(uid: 0, username: 'root', displayName: 'root');
    const ada = PolkitIdentity(uid: 1000, username: 'ada', displayName: 'Ada');

    // Answering as yourself is the case that needs no thought — and opening
    // on the root row would be teaching the user to type the root password at
    // prompts they could have answered themselves.
    test('opens on the current user when polkit named them', () {
      expect(defaultIdentityIndex([root, ada], currentUid: 1000), 1);
    });

    test('falls back to the order polkit listed', () {
      expect(defaultIdentityIndex([root, ada], currentUid: 4242), 0);
      expect(defaultIdentityIndex([root, ada]), 0);
      expect(defaultIdentityIndex([], currentUid: 0), 0);
    });
  });

  group('PolkitAuthRequest', () {
    test('an empty message still says what is happening', () {
      const request = PolkitAuthRequest(
        actionId: 'org.freedesktop.locale1.set-keyboard',
        message: '   ',
        iconName: '',
        details: {},
        cookie: 'c',
        identities: [],
      );
      expect(request.displayMessage, isNotEmpty);
      expect(request.displayMessage.trim(), request.displayMessage);
    });

    // The cookie is what an attacker would want out of a log line.
    test('does not print its cookie', () {
      const request = PolkitAuthRequest(
        actionId: 'a',
        message: 'm',
        iconName: '',
        details: {},
        cookie: 'super-secret-cookie',
        identities: [],
      );
      expect(request.toString(), isNot(contains('super-secret-cookie')));
    });
  });
}
