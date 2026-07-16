import 'dart:isolate';

import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/process_reader.dart';

/// The seam between the store and the `/proc` walk.
///
/// Exists so the store can be tested without spawning an isolate, and so a
/// persistent-isolate implementation can be swapped in later without touching
/// any caller.
abstract class ProcessSampler {
  Future<List<ProcessRaw>> sample(Set<int> skipCmdlineFor);
}

/// Runs the walk in a throwaway isolate.
///
/// A 500-process walk is on the order of a thousand syscalls. Doing that
/// synchronously on the UI isolate drops a frame every poll — and it does it
/// most visibly while you are scrolling the very process list it feeds.
///
/// [Isolate.run] spawns a fresh isolate per poll, which costs a millisecond or
/// two. A persistent isolate would avoid that, at the price of the whole port
/// and lifecycle apparatus `PulseClient` carries. At a two-second cadence the
/// spawn is a rounding error, so the simpler thing wins.
class IsolateProcessSampler implements ProcessSampler {
  IsolateProcessSampler({this.procRoot = '/proc'});

  final String procRoot;

  @override
  Future<List<ProcessRaw>> sample(Set<int> skipCmdlineFor) {
    // Capture only primitives. The closure is sent to a fresh isolate, so it
    // must not close over `this` — a ProcessReader that later grew a
    // non-sendable field would start throwing at runtime, not compile time.
    final root = procRoot;
    final skip = skipCmdlineFor.toList(growable: false);
    return Isolate.run(
      () => ProcessReader(procRoot: root).sample(skipCmdlineFor: skip.toSet()),
    );
  }
}
