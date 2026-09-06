import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

// struct passwd, from <pwd.h>. Only the fields we read are named; the rest are
// present so the layout matches.
//
//   char   *pw_name;
//   char   *pw_passwd;
//   uid_t   pw_uid;
//   gid_t   pw_gid;
//   char   *pw_gecos;
//   char   *pw_dir;
//   char   *pw_shell;
final class _Passwd extends ffi.Struct {
  external ffi.Pointer<Utf8> pwName;
  external ffi.Pointer<Utf8> pwPasswd;

  @ffi.Uint32()
  external int pwUid;

  @ffi.Uint32()
  external int pwGid;

  external ffi.Pointer<Utf8> pwGecos;
  external ffi.Pointer<Utf8> pwDir;
  external ffi.Pointer<Utf8> pwShell;
}

final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();

final int Function() _getuid =
    _libc.lookupFunction<ffi.Uint32 Function(), int Function()>('getuid');

final ffi.Pointer<_Passwd> Function(int) _getpwuid = _libc.lookupFunction<
    ffi.Pointer<_Passwd> Function(ffi.Uint32),
    ffi.Pointer<_Passwd> Function(int)>('getpwuid');

/// The uid the shell is running as.
///
/// Its own function because the polkit agent wants the *number* rather than the
/// account: `BeginAuthentication` names the identities it will accept by uid, and
/// the dialog opens on the current user's row when they are one of them. Answers
/// null only if `getuid` itself is unreachable.
int? currentUid() {
  try {
    return _getuid();
  } catch (_) {
    return null;
  }
}

/// Who the shell is running as.
///
/// Read from `getpwuid(getuid())` rather than `$USER`: the lock screen has to
/// authenticate the account that actually owns the session, and the passwd
/// database is the authority. It also hands us the GECOS field, which is the
/// display name the rest of the desktop shows.
class UserIdentity {
  const UserIdentity({required this.username, required this.displayName});

  /// The account name, as PAM expects it.
  final String username;

  /// The human-readable name, falling back to [username].
  final String displayName;

  /// Looks up the current user, falling back to the environment if the passwd
  /// lookup fails for any reason (which should not happen, but a lock screen
  /// that throws on startup would be far worse than one showing a bare name).
  static UserIdentity current() {
    try {
      final entry = _getpwuid(_getuid());
      if (entry.address != 0) {
        final name = _readUtf8(entry.ref.pwName);
        if (name != null && name.isNotEmpty) {
          return UserIdentity(
            username: name,
            displayName: _realNameFromGecos(_readUtf8(entry.ref.pwGecos)) ?? name,
          );
        }
      }
    } catch (_) {
      // Fall through to the environment.
    }
    final fallback = Platform.environment['USER'] ??
        Platform.environment['LOGNAME'] ??
        '';
    return UserIdentity(username: fallback, displayName: fallback);
  }

  /// The account [uid] names, or null when the passwd database has no such entry.
  ///
  /// Null rather than a synthesised name: the polkit agent hands [username]
  /// straight to `polkit-agent-helper-1`, which authenticates whatever it is
  /// given — so a guess here would be an authentication attempt against an
  /// account nobody asked about.
  static UserIdentity? forUid(int uid) {
    try {
      final entry = _getpwuid(uid);
      if (entry.address == 0) return null;
      final name = _readUtf8(entry.ref.pwName);
      if (name == null || name.isEmpty) return null;
      return UserIdentity(
        username: name,
        displayName: _realNameFromGecos(_readUtf8(entry.ref.pwGecos)) ?? name,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _readUtf8(ffi.Pointer<Utf8> ptr) {
    if (ptr.address == 0) return null;
    try {
      return ptr.toDartString();
    } catch (_) {
      return null;
    }
  }

  /// GECOS is comma-separated (`full name,room,work phone,home phone,other`);
  /// only the first field is the person's name.
  static String? _realNameFromGecos(String? gecos) {
    if (gecos == null) return null;
    final full = gecos.split(',').first.trim();
    return full.isEmpty ? null : full;
  }
}
