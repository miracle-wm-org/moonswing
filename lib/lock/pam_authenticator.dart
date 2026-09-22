import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:moonswing/native/ffi_util.dart';

import 'user_identity.dart';

/// Outcome of an unlock attempt.
enum PamResult {
  /// The password was accepted.
  success,

  /// The password was rejected.
  incorrect,

  /// PAM itself is unusable (no `libpam`, `pam_start` failed). The user cannot
  /// fix this by typing a different password, so the UI says so plainly.
  unavailable,
}

// <security/_pam_types.h>
const int _pamSuccess = 0;
const int _pamPromptEchoOff = 1;
const int _pamPromptEchoOn = 2;
const int _pamConvErr = 19;
const int _pamMaxNumMsg = 32;

// struct pam_message { int msg_style; const char *msg; }
final class _PamMessage extends ffi.Struct {
  @ffi.Int32()
  external int msgStyle;

  external ffi.Pointer<Utf8> msg;
}

// struct pam_response { char *resp; int resp_retcode; }
final class _PamResponse extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> resp;

  @ffi.Int32()
  external int respRetcode;
}

typedef _ConvNative = ffi.Int32 Function(
  ffi.Int32 numMsg,
  ffi.Pointer<ffi.Pointer<_PamMessage>> msg,
  ffi.Pointer<ffi.Pointer<_PamResponse>> resp,
  ffi.Pointer<ffi.Void> appdata,
);

// struct pam_conv { int (*conv)(...); void *appdata_ptr; }
final class _PamConv extends ffi.Struct {
  external ffi.Pointer<ffi.NativeFunction<_ConvNative>> conv;
  external ffi.Pointer<ffi.Void> appdataPtr;
}

/// Verifies the user's login password with PAM.
///
/// Everything happens through `dart:ffi` rather than native runner code, and the
/// whole blocking `pam_start` → `pam_authenticate` → `pam_end` sequence runs
/// inside [Isolate.run] so the lock screen keeps painting while a slow PAM stack
/// (`pam_unix` deliberately delays failures by seconds) works. The conversation
/// callback is `isolateLocal` because PAM invokes it synchronously, on the very
/// thread that called `pam_authenticate`.
///
/// This works without the shell being root because `pam_unix` shells out to the
/// setuid-root `unix_chkpwd` helper to read the shadow database.
class PamAuthenticator {
  const PamAuthenticator._();

  /// PAM service names to try, most preferred first.
  ///
  /// We ship `/etc/pam.d/moonswing`; `login` is the universally present
  /// fallback for installs that could not write to `/etc` (its `auth` stack
  /// includes `common-auth`, which is all we exercise — we never open a session).
  static const List<String> _serviceCandidates = <String>[
    'moonswing',
    'login',
  ];

  /// The PAM service this machine will actually use.
  static String resolveService() {
    for (final candidate in _serviceCandidates) {
      if (File('/etc/pam.d/$candidate').existsSync()) return candidate;
    }
    return _serviceCandidates.first;
  }

  /// Checks [password] against the current user's login credentials.
  static Future<PamResult> authenticate(String password) async {
    // Never hand an empty secret to PAM: an account configured with `nullok`
    // would otherwise unlock on a bare Enter press.
    if (password.isEmpty) return PamResult.incorrect;

    final identity = UserIdentity.current();
    if (identity.username.isEmpty) return PamResult.unavailable;

    final service = resolveService();
    final username = identity.username;

    try {
      return await Isolate.run(
        () => _authenticateSync(service, username, password),
      );
    } catch (_) {
      return PamResult.unavailable;
    }
  }
}

/// The blocking PAM conversation. Runs on its own isolate.
PamResult _authenticateSync(String service, String username, String password) {
  final opened = openFirstLibrary(const ['libpam.so.0', 'libpam.so']);
  if (opened == null) return PamResult.unavailable;
  final lib = opened;

  final pamStart = lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>,
          ffi.Pointer<_PamConv>, ffi.Pointer<ffi.Pointer<ffi.Void>>),
      int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<_PamConv>,
          ffi.Pointer<ffi.Pointer<ffi.Void>>)>('pam_start');
  final pamAuthenticate = lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
      int Function(ffi.Pointer<ffi.Void>, int)>('pam_authenticate');
  final pamEnd = lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
      int Function(ffi.Pointer<ffi.Void>, int)>('pam_end');

  // Answers every password prompt with the secret the user typed. PAM takes
  // ownership of the array and each string, so they are allocated with the C
  // allocator and deliberately not freed here.
  int converse(
    int numMsg,
    ffi.Pointer<ffi.Pointer<_PamMessage>> msg,
    ffi.Pointer<ffi.Pointer<_PamResponse>> resp,
    ffi.Pointer<ffi.Void> appdata,
  ) {
    if (numMsg <= 0 || numMsg > _pamMaxNumMsg) return _pamConvErr;
    final replies = calloc<_PamResponse>(numMsg);
    for (var i = 0; i < numMsg; i++) {
      final style = msg[i].ref.msgStyle;
      if (style == _pamPromptEchoOff || style == _pamPromptEchoOn) {
        replies[i].resp = _dupUtf8(password);
      }
    }
    resp.value = replies;
    return _pamSuccess;
  }

  final callable = ffi.NativeCallable<_ConvNative>.isolateLocal(
    converse,
    exceptionalReturn: _pamConvErr,
  );

  final conv = calloc<_PamConv>();
  final handleOut = calloc<ffi.Pointer<ffi.Void>>();
  final servicePtr = service.toNativeUtf8();
  final userPtr = username.toNativeUtf8();

  try {
    conv.ref.conv = callable.nativeFunction;
    conv.ref.appdataPtr = ffi.nullptr;

    final startStatus = pamStart(servicePtr, userPtr, conv, handleOut);
    if (startStatus != _pamSuccess) return PamResult.unavailable;

    final handle = handleOut.value;
    final authStatus = pamAuthenticate(handle, 0);
    pamEnd(handle, authStatus);

    return authStatus == _pamSuccess ? PamResult.success : PamResult.incorrect;
  } catch (_) {
    return PamResult.unavailable;
  } finally {
    callable.close();
    calloc.free(conv);
    calloc.free(handleOut);
    calloc.free(servicePtr);
    calloc.free(userPtr);
  }
}

/// `strdup` for a Dart string, using the C allocator so PAM can `free()` it.
ffi.Pointer<ffi.Uint8> _dupUtf8(String value) {
  final units = utf8.encode(value);
  final ptr = calloc<ffi.Uint8>(units.length + 1);
  ptr.asTypedList(units.length + 1).setAll(0, units);
  return ptr;
}
