// The values that cross the polkit wire, as types the rest of the shell can
// use, plus the two decisions that are pure arithmetic over them: which
// identities the agent can actually authenticate, and which of them the
// dialog should start on.
//
// Flutter-free (it imports `package:dbus` alone, the way
// `lib/keyboard/locale1_client.dart` does), so the identity parse and the
// default-identity rule are plain unit tests with no bus and no passwd
// database behind them.

import 'package:dbus/dbus.dart';

/// An account polkit will accept an answer from.
///
/// Only `unix-user` identities become one of these. polkit also names
/// `unix-group` identities in a `BeginAuthentication` call, and there is
/// nothing an agent can do with one: the helper authenticates *a user*, so a
/// group has to be resolved to a member first and polkit does not say which
/// member it means. libpolkit-agent draws the same line — its session takes a
/// `PolkitUnixUser` and nothing else — so [parsePolkitIdentities] drops them.
class PolkitIdentity {
  const PolkitIdentity({
    required this.uid,
    required this.username,
    required this.displayName,
  });

  final int uid;

  /// The passwd name, which is what `polkit-agent-helper-1` is given as
  /// `argv[1]` and what PAM authenticates.
  final String username;

  /// The GECOS name, falling back to [username] — what the dialog shows.
  final String displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolkitIdentity &&
          other.uid == uid &&
          other.username == username &&
          other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, username, displayName);

  @override
  String toString() => 'PolkitIdentity($uid, $username)';
}

/// Resolves a uid to its passwd entry, or null when the machine has no such
/// account. Injected rather than called directly so the parse below is a unit
/// test rather than an assertion about the host's `/etc/passwd`.
typedef PolkitUserLookup = ({String username, String displayName})? Function(
  int uid,
);

/// Turns `BeginAuthentication`'s `a(sa{sv})` identity array into the accounts
/// the agent can actually offer.
///
/// Degrades per entry, the rule `TomlReader` states at the config end of the
/// shell: an identity of a kind this build cannot use, one with no `uid`, or
/// one naming a uid with no passwd entry costs *that identity* and never the
/// prompt — the remaining ones are still offered, and a request whose whole
/// array is unusable is refused with a reason rather than throwing out of a
/// D-Bus handler.
List<PolkitIdentity> parsePolkitIdentities(
  DBusValue? raw, {
  required PolkitUserLookup lookup,
}) {
  if (raw == null) return const [];
  final List<DBusValue> entries;
  try {
    entries = raw.asArray().toList();
  } catch (_) {
    return const [];
  }
  final identities = <PolkitIdentity>[];
  final seen = <int>{};
  for (final entry in entries) {
    int? uid;
    try {
      final fields = entry.asStruct();
      if (fields.length < 2) continue;
      if (fields[0].asString() != 'unix-user') continue;
      uid = _uidOf(fields[1].asStringVariantDict());
    } catch (_) {
      continue;
    }
    if (uid == null || !seen.add(uid)) continue;
    final user = lookup(uid);
    if (user == null || user.username.isEmpty) continue;
    identities.add(PolkitIdentity(
      uid: uid,
      username: user.username,
      displayName:
          user.displayName.isEmpty ? user.username : user.displayName,
    ));
  }
  return identities;
}

/// polkit sends the uid as a `u` variant, but the dict is `a{sv}` and a
/// variant is only ever as narrow as whoever built it — so every unsigned
/// width is accepted rather than one.
int? _uidOf(Map<String, DBusValue> details) {
  return switch (details['uid']) {
    DBusUint32(value: final uid) => uid,
    DBusUint64(value: final uid) => uid,
    DBusInt32(value: final uid) when uid >= 0 => uid,
    DBusInt64(value: final uid) when uid >= 0 => uid,
    _ => null,
  };
}

/// Which identity the dialog starts on.
///
/// The current user when polkit named them, because answering as yourself is
/// the case that needs no thought and no second password; otherwise the first
/// identity polkit listed, which is the order it considers them in. Nothing
/// here prefers root: an agent that opened on the root row would be teaching
/// the user to type the root password at prompts they could have answered
/// themselves.
int defaultIdentityIndex(List<PolkitIdentity> identities, {int? currentUid}) {
  if (identities.isEmpty) return 0;
  if (currentUid != null) {
    final index = identities.indexWhere((i) => i.uid == currentUid);
    if (index >= 0) return index;
  }
  return 0;
}

/// One `BeginAuthentication` call: everything polkit says about why it is
/// asking, plus the cookie that identifies the answer.
class PolkitAuthRequest {
  const PolkitAuthRequest({
    required this.actionId,
    required this.message,
    required this.iconName,
    required this.details,
    required this.cookie,
    required this.identities,
  });

  /// e.g. `org.freedesktop.locale1.set-keyboard`.
  final String actionId;

  /// The sentence polkit wants shown — already localized by polkitd for the
  /// locale the agent registered with.
  final String message;

  /// A themed icon name, often empty. The dialog draws its own glyph either
  /// way: the shell has no icon-theme lookup on this path and a padlock is
  /// what every one of these prompts means.
  final String iconName;

  /// The action's own details plus whatever the caller attached. Rendered
  /// only as the trailing "what is asking" line — never trusted as markup,
  /// and never parsed for meaning.
  final Map<String, String> details;

  /// polkit's handle for this authentication. It goes to the helper on
  /// **stdin** and never onto a command line: see [PolkitHelperRunner].
  final String cookie;

  /// Who may answer. Empty means nobody this agent can authenticate — see
  /// [parsePolkitIdentities].
  final List<PolkitIdentity> identities;

  /// The message, or a fallback for a caller that sent none. polkitd fills
  /// this from the action's `.policy` file, but the argument is a plain string
  /// and an empty dialog would leave the user approving something unnamed.
  String get displayMessage => message.trim().isEmpty
      ? 'An application is asking for administrator rights.'
      : message.trim();

  @override
  String toString() => 'PolkitAuthRequest($actionId, cookie: <redacted>)';
}

/// How an authentication ended.
enum PolkitAuthOutcome {
  /// The helper answered `SUCCESS`; polkitd has already been told.
  authenticated,

  /// Every attempt was refused, or the helper died. polkit is answered with
  /// `org.freedesktop.PolicyKit1.Error.Failed`.
  failed,

  /// The user said no — Escape, the backdrop, the Cancel button — or polkitd
  /// withdrew the request. Answered with
  /// `org.freedesktop.PolicyKit1.Error.Cancelled`, which is what stops the
  /// caller retrying in a loop.
  cancelled,

  /// There is no `polkit-agent-helper-1` on this machine, or no identity the
  /// agent could offer. Distinct from [failed] because no password the user
  /// types would change it, so the dialog says so instead of asking again.
  unavailable,
}
