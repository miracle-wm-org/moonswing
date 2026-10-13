// A raw file descriptor as a `dart:io` `ResourceHandle`.
//
// `package:dbus` passes a file descriptor (`h`) only as a `ResourceHandle`, and
// `dart:io` makes those only out of objects it opened itself — a file, a socket,
// a pipe. A descriptor that came out of a C library (libeis's end of an EI
// socketpair, for `ConnectToEIS`) has no such object, and no constructor takes a
// bare number.
//
// So one is borrowed: a scratch file is opened through `dart:io`, its descriptor
// number is found under `/proc/self/fd`, and `dup2` points that number at the
// foreign descriptor. The `RandomAccessFile` now owns the socket — closing it
// closes the socket — and `ResourceHandle.fromFile` hands its number to the
// bus, which `sendmsg`s it synchronously as the reply is written. The kernel
// gives the receiver its own copy, so ours is closed shortly after.
//
// Flutter-free.

import 'dart:async';
import 'dart:io';

import 'libc.dart';

int _counter = 0;

/// A foreign descriptor adopted into `dart:io`. [handle] is what D-Bus sends;
/// [close] gives the descriptor up, and is idempotent.
class AdoptedFd {
  AdoptedFd._(this._file) : handle = ResourceHandle.fromFile(_file);

  final RandomAccessFile _file;
  final ResourceHandle handle;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _file.closeSync();
    } catch (_) {}
  }

  /// Closes after [delay] — long enough for the reply carrying [handle] to
  /// have been written.
  void closeSoon([Duration delay = const Duration(seconds: 2)]) =>
      Timer(delay, close);
}

/// Takes ownership of [fd]: on success the original number is closed and the
/// descriptor lives on inside the returned [AdoptedFd]. Throws on failure, with
/// [fd] closed either way.
AdoptedFd adoptRawFd(int fd) {
  final scratch = File('${Directory.systemTemp.path}/'
      'moonswing-fd-$pid-${_counter++}');
  RandomAccessFile? file;
  try {
    file = scratch.openSync(mode: FileMode.write);
    final number = _descriptorOf(scratch.path);
    if (number == null) throw StateError('cannot find the scratch descriptor');
    if (!dup2Fd(fd, number)) throw StateError('dup2 failed');
    final adopted = AdoptedFd._(file);
    file = null;
    return adopted;
  } finally {
    file?.closeSync();
    closeFd(fd);
    try {
      scratch.deleteSync();
    } catch (_) {}
  }
}

int? _descriptorOf(String path) {
  for (final entry in Directory('/proc/self/fd').listSync(followLinks: false)) {
    try {
      if (Link(entry.path).targetSync() == path) {
        return int.tryParse(entry.uri.pathSegments.last);
      }
    } catch (_) {
      // Closed between the listing and the readlink.
    }
  }
  return null;
}
