// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:graceful_shell/pulse_log.dart';
import 'package:pulseaudio/src/generated_bindings.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class PaSink {
  const PaSink({
    required this.index,
    required this.name,
    required this.description,
    required this.mute,
    required this.volume,
    required this.channelCount,
    required this.balance,
  });
  final int index;
  final String name;
  final String description;
  final bool mute;
  final double volume;
  final int channelCount;
  final double balance;
}

class PaSource {
  const PaSource({
    required this.index,
    required this.name,
    required this.description,
    required this.mute,
    required this.volume,
  });
  final int index;
  final String name;
  final String description;
  final bool mute;
  final double volume;
}

class PaServerInfo {
  const PaServerInfo({
    required this.defaultSinkName,
    required this.defaultSourceName,
  });
  final String defaultSinkName;
  final String defaultSourceName;
}

class PaSinkInput {
  const PaSinkInput({
    required this.index,
    required this.sinkIndex,
    required this.appName,
    required this.mediaName,
    required this.mute,
    required this.volume,
    required this.corked,
    required this.channelCount,
  });
  final int index;
  final int sinkIndex;
  final String appName;
  final String mediaName;
  final bool mute;
  final double volume;
  final bool corked;
  final int channelCount;
}

class PaCardProfile {
  const PaCardProfile({
    required this.name,
    required this.description,
    required this.available,
  });
  final String name;
  final String description;
  final bool available;
}

class PaCard {
  const PaCard({
    required this.index,
    required this.name,
    required this.description,
    required this.profiles,
    required this.activeProfileName,
    required this.isBluez,
  });
  final int index;
  final String name;
  final String description;
  final List<PaCardProfile> profiles;
  final String activeProfileName;
  final bool isBluez;
}

class PaModule {
  const PaModule({required this.index, required this.name});
  final int index;
  final String name;
}

// ---------------------------------------------------------------------------
// Isolate messages
//
// Requests cross the SendPort as one generic envelope: an id, a kind, and a
// positional args list of sendable primitives. The isolate answers with a
// [_Reply] carrying the same id and an optional payload (null for
// fire-and-await-done requests). Adding a request is one [_ReqKind] member,
// one [_PaIsolate._handleMsg] case unpacking the args into the handler, and a
// one-line public method on [PulseClient].
//
// Everything the isolate pushes *unrequested* — the ready handshake, device
// change notifications, level-meter frames — keeps its own event class below:
// those carry no requesting id, so they are events, not replies.
// ---------------------------------------------------------------------------

enum _ReqKind {
  getServerInfo,
  getSinkList,
  getSourceList,
  setSinkVolume,
  setSinkVolumeBalance,
  setSinkMute,
  setDefaultSink,
  setSourceVolume,
  setSourceMute,
  setDefaultSource,
  getSinkInputList,
  setSinkInputVolume,
  setSinkInputMute,
  moveSinkInput,
  getCardList,
  setCardProfile,
  getModuleList,
  loadModule,
  unloadModule,
  startLevelMeter,
  stopLevelMeter,
  dispose,
}

class _Request {
  const _Request(this.id, this.kind, [this.args = const []]);
  final int id;
  final _ReqKind kind;
  final List<Object?> args;
}

class _Reply {
  const _Reply(this.id, [this.payload]);
  final int id;
  final Object? payload;
}

// --- events (pushed from the isolate; not answers to any request) ---

class _ReadyEvent {
  const _ReadyEvent(this.loopAddress);

  /// Address of the isolate's `pa_mainloop`, so the main isolate can break the
  /// poll when it posts a request. See [PulseClient._post] for what that is
  /// and is not worth.
  final int loopAddress;
}

class _LevelEvent {
  const _LevelEvent(this.level);
  final double level;
}

class _SinkChangedEvent {
  const _SinkChangedEvent(this.sink);
  final PaSink sink;
}

class _SinkRemovedEvent {
  const _SinkRemovedEvent(this.index);
  final int index;
}

class _SourceChangedEvent {
  const _SourceChangedEvent(this.source);
  final PaSource source;
}

class _SourceRemovedEvent {
  const _SourceRemovedEvent(this.index);
  final int index;
}

/// The default sink and/or source moved.
///
/// PulseAudio reports a default-device change on the **server** facility and
/// nowhere else: neither the device being left nor the one being adopted emits
/// a sink/source event of its own. So for any consumer that resolved a device
/// name once and filters events against it — which is every consumer here —
/// this is the only notice it will ever get that the name it is holding has
/// stopped being the default one.
class _ServerChangedEvent {
  const _ServerChangedEvent(this.info);
  final PaServerInfo info;
}

/// The isolate's context has connected again after the server went away.
///
/// This is its own event rather than a [_ServerChangedEvent] because every
/// consumer filters that stream on the default device having *moved* —
/// `OsdAudioTracker.defaultsMoved`, `SoundControlState`'s name compare — and a
/// `pipewire-pulse` restart normally brings the same device name back. Reusing
/// it would therefore be a silent no-op that leaves a stale reading on screen
/// for the rest of the session, and loosening those filters would cost the
/// redundant-reseed guard they exist for.
///
/// Nothing read before this survives it: the sink and source indices are the
/// new server's, and the level meter's `pa_stream` belonged to the context that
/// died. A consumer answers it by re-running the seeding it does at start-up.
class _ConnectedEvent {
  const _ConnectedEvent();
}

// ---------------------------------------------------------------------------
// PA isolate — runs libpulse in a dedicated Dart isolate
// ---------------------------------------------------------------------------

late PulseAudioBindings _pa;

class _PaIsolate {
  _PaIsolate._(
    this.port,
    this.loop,
    this.api,
    this.ctx,
  );

  static _PaIsolate? _inst;

  final SendPort port;
  final Pointer<pa_mainloop> loop;
  final Pointer<pa_mainloop_api> api;

  // Not final: a context cannot be reconnected, only replaced, so [_reconnect]
  // frees this one and puts the new one here. The mainloop and its api above
  // outlive every context — `PulseClient._loop` holds the loop's address for
  // `pa_mainloop_wakeup`, so it must never move.
  Pointer<pa_context> ctx;

  // Pending PA operations → completion callbacks
  final ops = <Pointer<pa_operation>, void Function()>{};

  // Accumulator for list results keyed by requestId
  final accum = <int, dynamic>{};

  // Channel count cache for sink inputs (index → channels)
  final sinkInputChannels = <int, int>{};

  // Channel count caches for sinks and sources (name → channels), filled as
  // their infos arrive. A volume set must be as wide as the device: writing 2
  // channels to a mono or surround device sets the wrong width.
  final sinkChannels = <String, int>{};
  final sourceChannels = <String, int>{};

  // Level metering stream
  Pointer<pa_stream> levelStream = nullptr;

  // ---------------------------------------------------------------------------
  // Entry point (spawned in a new Dart isolate)
  // ---------------------------------------------------------------------------

  static void entry(SendPort port) {
    _pa = PulseAudioBindings(DynamicLibrary.open('libpulse.so.0'));

    final loop = _pa.pa_mainloop_new();
    final api = _pa.pa_mainloop_get_api(loop);
    final ctx = _newContext(api);

    _inst = _PaIsolate._(port, loop, api, ctx);

    final recv = ReceivePort();
    port.send(recv.sendPort);
    recv.listen(_handleMsg);

    final exitRecv = ReceivePort();
    exitRecv.listen((_) {
      _dispose();
      exitRecv.close();
    });
    Isolate.current.addOnExitListener(exitRecv.sendPort);

    _loop();
  }

  /// Creates a context on [api], arms its state callback and connects it.
  ///
  /// Both the first connect and every [_reconnect] go through here, so the
  /// three calls cannot drift apart — a rebuilt context with no state callback
  /// is one whose next failure is never noticed. `pa_context_new` copies the
  /// name, so the buffer is freed straight back.
  ///
  /// The callback is armed **before** the connect, which is the opposite of
  /// what this used to do: `pa_context_connect` sets the new state from inside
  /// itself and invokes the callback synchronously, so arming it afterwards
  /// loses a connect that failed on the spot — a machine whose audio server is
  /// not running when the shell starts — and the retry is then never scheduled.
  /// The consequence is that [_onCtxState] can run before `entry` has assigned
  /// `_inst`, which is safe only because the branch that touches it is READY,
  /// and READY cannot arrive before the mainloop has been dispatched.
  static Pointer<pa_context> _newContext(Pointer<pa_mainloop_api> api) {
    final pName = 'PulseClient'.toNativeUtf8();
    final ctx = _pa.pa_context_new(api, pName.cast());
    calloc.free(pName);
    _pa.pa_context_set_state_callback(
        ctx, Pointer.fromFunction(_onCtxState), nullptr);
    if (_pa.pa_context_connect(
            ctx, nullptr, pa_context_flags.PA_CONTEXT_NOAUTOSPAWN, nullptr) <
        0) {
      // A connect that is refused outright delivers no state change, so the
      // failure has to be recorded here or the retry would never be armed.
      pulseLog('pa_context_connect refused');
      _noteContextLost();
    }
    return ctx;
  }

  // ---------------------------------------------------------------------------
  // Main loop driver
  // ---------------------------------------------------------------------------

  /// How long one [_loop] turn may block inside `ppoll` waiting for something
  /// to happen. Only ever spent when the mainloop is completely idle.
  static const int _idleSliceUs = 50 * 1000;

  /// How long one [_loop] turn may keep *working* before handing the isolate
  /// back to the Dart event loop, so a burst of events (a level meter, a volume
  /// key held down) cannot starve [_handleMsg].
  static const int _activityBudgetUs = 10 * 1000;

  /// How long a cycle that follows real work may block. Long enough for a
  /// request/reply round trip to the server to land in the same turn, short
  /// enough that the tail after a burst is not felt.
  static const int _drainWaitUs = 2 * 1000;

  /// Set once the mainloop reports quit or a hard error. Past that point the
  /// driver must never call `pa_mainloop_prepare` again: it asserts on its own
  /// state and `abort()`s the process instead of returning an error.
  static bool _dead = false;

  /// Set when the context reports FAILED or TERMINATED; cleared by
  /// [_reconnect]. Deliberately *not* [_dead], which means the mainloop itself
  /// is unusable and is the one state nothing recovers from — a context dying
  /// under a `systemctl --user restart pipewire-pulse` leaves the mainloop
  /// perfectly healthy.
  static bool _lostContext = false;

  /// Set from [_reconnect] and cleared on the next READY, where it is what
  /// separates a reconnection (which every consumer has to re-seed from) from
  /// the first connection (which they seed from anyway).
  static bool _reconnecting = false;

  /// How long to wait before the next connect attempt, doubling per failure,
  /// and the clock it is measured against. A server restart is two or three
  /// seconds of nothing listening on the socket, so the first attempt has to be
  /// prompt and the tail has to back off rather than reconnect-storm a machine
  /// whose audio stack is simply not coming back.
  static int _reconnectDelayMs = 0;
  static final Stopwatch _sinceContextLost = Stopwatch();

  static const int _reconnectFirstDelayMs = 250;
  static const int _reconnectMaxDelayMs = 5000;

  /// Records a lost context and arms the next attempt. Idempotent: several
  /// failures before the retry runs are one loss.
  static void _noteContextLost() {
    if (_lostContext) return;
    _lostContext = true;
    _reconnectDelayMs = _reconnectDelayMs == 0
        ? _reconnectFirstDelayMs
        : math.min(_reconnectDelayMs * 2, _reconnectMaxDelayMs);
    _sinceContextLost
      ..reset()
      ..start();
    pulseLog('context lost; reconnecting in ${_reconnectDelayMs}ms');
  }

  /// Replaces the dead context with a fresh one on the surviving mainloop.
  ///
  /// Called from the top of a [_loop] turn rather than from [_onCtxState],
  /// because libpulse does not allow a context to be freed from inside its own
  /// state callback.
  static void _reconnect(_PaIsolate inst) {
    if (_sinceContextLost.elapsedMilliseconds < _reconnectDelayMs) return;
    _lostContext = false;
    _reconnecting = true;

    final old = inst.ctx;
    // Detached first: `pa_context_disconnect` can deliver TERMINATED
    // synchronously, and a state callback firing for the context being torn
    // down here would arm a second reconnect on the way out.
    _pa.pa_context_set_state_callback(old, nullptr, nullptr);

    // Every request in flight is owed an answer. `ops` holds the completions
    // the main isolate's `firstWhere`s are waiting on, and the operations
    // themselves belong to the context about to be freed — so each completion
    // runs (sending whatever accumulated, which for an unanswered query is the
    // empty list its call site pre-seeded) before the context goes. Dropping
    // them instead leaves one future pending per in-flight request for the life
    // of the process, which is [_reapOps]'s cancelled-operation rule.
    for (final op in inst.ops.keys.toList()) {
      inst.ops.remove(op)!();
      _pa.pa_operation_unref(op);
    }
    inst.accum.clear();
    inst.sinkChannels.clear();
    inst.sourceChannels.clear();
    inst.sinkInputChannels.clear();

    // The stream belonged to the context and does not survive it. It is only
    // unreffed, never disconnected: `pa_stream_disconnect` wants a stream in
    // READY, which this one has not been since the server went away. Its one
    // consumer restarts the meter off `onReconnected`.
    if (inst.levelStream.address != 0) {
      _pa.pa_stream_unref(inst.levelStream);
      inst.levelStream = nullptr;
    }

    _pa.pa_context_disconnect(old);
    _pa.pa_context_unref(old);

    pulseLog('reconnecting');
    inst.ctx = _newContext(inst.api);
  }

  // Outcome of one prepare/poll/dispatch cycle.
  static const int _cycleIdle = 0; // nothing was ready
  static const int _cycleWorked = 1; // libpulse dispatched something
  static const int _cycleWoken = 2; // poll returned, nothing to dispatch
  static const int _cycleDead = 3; // quit requested, or an error

  /// One full turn of the libpulse state machine.
  ///
  /// `pa_mainloop_prepare` asserts `state == STATE_PASSIVE` and `abort()`s
  /// otherwise, and only `pa_mainloop_dispatch` puts the loop back into that
  /// state — so once `prepare` has succeeded, `dispatch` is not optional, even
  /// when `poll` failed. The one value that may skip it is `-2`, "quit
  /// requested", which parks the loop in STATE_QUIT for good.
  static int _cycle(_PaIsolate inst, int timeoutUs) {
    if (_pa.pa_mainloop_prepare(inst.loop, timeoutUs) < 0) return _cycleDead;
    // -2 is the one poll result that parks the loop in STATE_QUIT; every other
    // negative leaves it in STATE_POLLED, where dispatch is still required.
    final polled = _pa.pa_mainloop_poll(inst.loop);
    if (polled == -2) return _cycleDead;
    final dispatched = _pa.pa_mainloop_dispatch(inst.loop);
    if (dispatched < 0 || polled < 0) return _cycleDead;
    if (dispatched > 0) return _cycleWorked;
    // `polled > 0` with nothing dispatched is the wakeup pipe. It sits in the
    // pollfd set but has no `pa_io_event`, so it can never be counted as a
    // dispatched source — which means this is the *only* place a wakeup is
    // visible. `_post` wrote it, so a request is already sitting in this
    // isolate's message queue and the event loop is where to be next.
    if (polled > 0) return _cycleWoken;
    // Nothing at all: a bare timeout, or a `ppoll` the Dart VM's thread
    // interrupter cut short. libpulse maps EINTR onto "returned, nothing was
    // ready" and does not retry, so retrying is this driver's job.
    return _cycleIdle;
  }

  /// Registers [op]'s completion, or runs it now if libpulse refused the call.
  ///
  /// Every `pa_context_*` request answers null once the context is no longer
  /// `PA_CONTEXT_IS_GOOD` — which is what a `pipewire-pulse` restart makes it —
  /// and `pa_operation_get_state(NULL)` is an assert inside libpulse, so a null
  /// key in [ops] does not merely lose the request: it takes the whole shell
  /// down with SIGABRT on the next [_reapOps]. That is the crash a server
  /// restart used to produce, and it is why `_onSubscribe` and
  /// `_startLevelMeter` already test the same return.
  ///
  /// Answering on the spot is [_reapOps]'s `PA_OPERATION_CANCELLED` contract
  /// applied one step earlier: [done] sends whatever accumulated — for a
  /// refused request, the empty list its call site pre-seeded — so the
  /// `firstWhere` the main isolate is awaiting still completes rather than
  /// hanging for the life of the process, and whatever that call site
  /// allocated is still freed.
  static void _register(Pointer<pa_operation> op, void Function() done) {
    if (op.address == 0) {
      pulseLog('request refused (context not ready); answering empty');
      done();
      return;
    }
    _inst!.ops[op] = done;
  }

  /// Answers every operation that has stopped running.
  ///
  /// A `PA_OPERATION_CANCELLED` operation is answered too, not dropped: the
  /// registered callback is what completes the `firstWhere` the main isolate is
  /// awaiting, and silently forgetting it leaves that future pending for the
  /// life of the process — and, when this reaping lived inside its own `while
  /// (ops.isNotEmpty)` branch, wedged the isolate's event loop with it.
  static void _reapOps(_PaIsolate inst) {
    if (inst.ops.isEmpty) return;
    for (final op in inst.ops.keys.toList()) {
      final state = _pa.pa_operation_get_state(op);
      if (state == pa_operation_state.PA_OPERATION_RUNNING) continue;
      if (state == pa_operation_state.PA_OPERATION_CANCELLED) {
        pulseLog('operation cancelled; answering with what accumulated');
      }
      inst.ops.remove(op)!();
      _pa.pa_operation_unref(op);
    }
  }

  /// Drives libpulse for a bounded slice, then re-arms through the Dart event
  /// loop so [_handleMsg] gets a turn.
  ///
  /// The rule is expressed on the pair (poll result, dispatched count):
  ///
  /// * dispatched > 0 — real work. **Keep cycling.** Delivering one external
  ///   volume change takes several cycles back to back (read the subscription
  ///   event, flush the `get_sink_info_by_index` its callback issued, read that
  ///   reply); returning to the Dart event loop in between is what used to
  ///   strand it, and is why a change made *through* this client — which had a
  ///   `pa_operation` in flight and so ran a different, continuous driver —
  ///   was the only kind that ever reached the OSD.
  /// * poll > 0, dispatched == 0 — the wakeup pipe. **Yield now**, a request is
  ///   queued.
  /// * both zero — idle, or EINTR. **Retry in place** for the rest of the
  ///   slice. This is the anti-spin case: re-arming through `Timer.run` on
  ///   every signal-interrupted poll turned an idle 20 Hz loop into an ~820 Hz
  ///   spin, 7 of the shell's 9% idle CPU.
  static void _loop() {
    final inst = _inst;
    if (inst == null || _dead) return;

    // Before driving the mainloop, not after: a turn spent polling a context
    // that is gone is a turn the reconnect is not attempted in.
    if (_lostContext) _reconnect(inst);

    final turn = Stopwatch()..start();
    var worked = false;
    var done = false;

    while (!done) {
      final elapsed = turn.elapsedMicroseconds;
      final int timeoutUs;
      if (worked) {
        final remaining = _activityBudgetUs - elapsed;
        if (remaining <= 0) break;
        timeoutUs = remaining < _drainWaitUs ? remaining : _drainWaitUs;
      } else {
        final remaining = _idleSliceUs - elapsed;
        if (remaining <= 0) break;
        timeoutUs = remaining;
      }

      switch (_cycle(inst, timeoutUs)) {
        case _cycleDead:
          _dead = true;
          pulseLog('mainloop quit or failed; driver stopped');
          return;
        case _cycleWorked:
          worked = true;
        case _cycleWoken:
          done = true;
        case _cycleIdle:
          // Nothing more to drain, so the burst is over.
          if (worked) done = true;
      }
      _reapOps(inst);
    }

    _reapOps(inst);
    Timer.run(_loop);
  }

  // ---------------------------------------------------------------------------
  // Message dispatch
  // ---------------------------------------------------------------------------

  /// Unpacks a [_Request] envelope into its handler. This table is the one
  /// place the positional args list is interpreted, so each case is where a
  /// kind's arg order and types are defined.
  static void _handleMsg(dynamic msg) {
    if (msg is! _Request) return;
    final id = msg.id;
    final a = msg.args;
    switch (msg.kind) {
      case _ReqKind.dispose:
        _dispose();
      case _ReqKind.getServerInfo:
        _getServerInfo(id);
      case _ReqKind.getSinkList:
        _getSinkList(id);
      case _ReqKind.getSourceList:
        _getSourceList(id);
      case _ReqKind.setSinkVolume:
        _setSinkVolume(id, a[0] as String, a[1] as double);
      case _ReqKind.setSinkVolumeBalance:
        _setSinkVolumeBalance(
            id, a[0] as String, a[1] as double, a[2] as double, a[3] as int);
      case _ReqKind.setSinkMute:
        _setSinkMute(id, a[0] as String, a[1] as bool);
      case _ReqKind.setDefaultSink:
        _setDefaultSink(id, a[0] as String);
      case _ReqKind.setSourceVolume:
        _setSourceVolume(id, a[0] as String, a[1] as double);
      case _ReqKind.setSourceMute:
        _setSourceMute(id, a[0] as String, a[1] as bool);
      case _ReqKind.setDefaultSource:
        _setDefaultSource(id, a[0] as String);
      case _ReqKind.getSinkInputList:
        _getSinkInputList(id);
      case _ReqKind.setSinkInputVolume:
        _setSinkInputVolume(id, a[0] as int, a[1] as double);
      case _ReqKind.setSinkInputMute:
        _setSinkInputMute(id, a[0] as int, a[1] as bool);
      case _ReqKind.moveSinkInput:
        _moveSinkInput(id, a[0] as int, a[1] as String);
      case _ReqKind.getCardList:
        _getCardList(id);
      case _ReqKind.setCardProfile:
        _setCardProfile(id, a[0] as String, a[1] as String);
      case _ReqKind.getModuleList:
        _getModuleList(id);
      case _ReqKind.loadModule:
        _loadModule(id, a[0] as String, a[1] as String);
      case _ReqKind.unloadModule:
        _unloadModule(id, a[0] as int);
      case _ReqKind.startLevelMeter:
        _startLevelMeter(id, a[0] as String);
      case _ReqKind.stopLevelMeter:
        _stopLevelMeter(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Context state callback
  // ---------------------------------------------------------------------------

  static void _onCtxState(Pointer<pa_context> c, Pointer<Void> ud) {
    final state = _pa.pa_context_get_state(c);
    if (state == pa_context_state.PA_CONTEXT_READY) {
      _pa.pa_context_set_subscribe_callback(
          c, Pointer.fromFunction(_onSubscribe), nullptr);
      _pa.pa_context_subscribe(
          c, pa_subscription_mask.PA_SUBSCRIPTION_MASK_ALL, nullptr, nullptr);
      // The backoff is per outage, so a connection that lasted starts the next
      // one over rather than inheriting however long the last one took.
      _reconnectDelayMs = 0;
      _inst!.port.send(_ReadyEvent(_inst!.loop.address));
      if (_reconnecting) {
        _reconnecting = false;
        pulseLog('reconnected');
        // After the subscription is re-armed, never before: a consumer that
        // re-seeded on this event and then missed the events that followed
        // would be exactly as stale as one that never heard it.
        _inst!.port.send(const _ConnectedEvent());
      }
      return;
    }
    // FAILED is the server going away — `pipewire-pulse` restarting under us,
    // or a socket that was never there — and TERMINATED is it closing the
    // connection cleanly. Both are recoverable and neither is acted on here:
    // libpulse forbids freeing a context from inside its own state callback, so
    // this only records, and [_reconnect] runs on the next [_loop] turn.
    if (state == pa_context_state.PA_CONTEXT_FAILED ||
        state == pa_context_state.PA_CONTEXT_TERMINATED) {
      _noteContextLost();
    }
  }

  // ---------------------------------------------------------------------------
  // Subscription callback — fires on device changes
  // ---------------------------------------------------------------------------

  static void _onSubscribe(
      Pointer<pa_context> c, int type, int idx, Pointer<Void> ud) {
    final facility = type & PA_SUBSCRIPTION_EVENT_FACILITY_MASK;
    final eventType = type & PA_SUBSCRIPTION_EVENT_TYPE_MASK;
    pulseLog('subscribe: facility=0x${facility.toRadixString(16)} '
        'event=0x${eventType.toRadixString(16)} index=$idx');

    Pointer<pa_operation> op = nullptr;

    switch (facility) {
      case PA_SUBSCRIPTION_EVENT_SERVER:
        // The default sink or source may have moved. The event carries no
        // payload, so re-read the server info; like the sink/source fetches
        // below this one is not routed through `ops` — the info callback
        // pushes the event itself.
        op = _pa.pa_context_get_server_info(
            c, Pointer.fromFunction(_onServerInfoChanged), nullptr);
      case PA_SUBSCRIPTION_EVENT_SINK:
        if (eventType == PA_SUBSCRIPTION_EVENT_REMOVE) {
          _inst!.port.send(_SinkRemovedEvent(idx));
        } else {
          op = _pa.pa_context_get_sink_info_by_index(
              c, idx, Pointer.fromFunction(_onSinkInfoChanged), nullptr);
        }
      case PA_SUBSCRIPTION_EVENT_SOURCE:
        if (eventType == PA_SUBSCRIPTION_EVENT_REMOVE) {
          _inst!.port.send(_SourceRemovedEvent(idx));
        } else {
          op = _pa.pa_context_get_source_info_by_index(
              c, idx, Pointer.fromFunction(_onSourceInfoChanged), nullptr);
        }
    }

    if (op.address != nullptr.address) _pa.pa_operation_unref(op);
  }

  // ---------------------------------------------------------------------------
  // Server info
  // ---------------------------------------------------------------------------

  static void _getServerInfo(int id) {
    final pId = calloc<Int>()..value = id;
    final op = _pa.pa_context_get_server_info(
        _inst!.ctx, Pointer.fromFunction(_onServerInfo), pId.cast());
    _register(op, () {
      // Unlike every other list query this one does not pre-seed `accum`, so a
      // cancelled operation reaches here with nothing to send. Answer anyway —
      // the main isolate is awaiting this id and would otherwise wait forever.
      _inst!.port.send(_Reply(
          id,
          _inst!.accum.remove(id) ??
              const PaServerInfo(defaultSinkName: '', defaultSourceName: '')));
      calloc.free(pId);
    });
  }

  static void _onServerInfo(
      Pointer<pa_context> c, Pointer<pa_server_info> info, Pointer<Void> ud) {
    // A failed query calls back with a null info, which is the case
    // `_getServerInfo`'s completion already answers for — leave `accum` empty
    // and let it send the empty default rather than dereferencing this.
    if (info.address == 0) return;
    final id = ud.cast<Int>().value;
    _inst!.accum[id] = _serverInfoFromNative(info);
  }

  /// Unsolicited twin of [_onServerInfo]: no request id in `ud`, and the
  /// result is pushed as an event rather than accumulated for a [_Reply].
  static void _onServerInfoChanged(
      Pointer<pa_context> c, Pointer<pa_server_info> info, Pointer<Void> ud) {
    if (info.address == 0) return;
    final resolved = _serverInfoFromNative(info);
    pulseLog('server changed: sink=${resolved.defaultSinkName} '
        'source=${resolved.defaultSourceName}');
    _inst!.port.send(_ServerChangedEvent(resolved));
  }

  /// A server with no default device at all reports it as a null pointer, not
  /// as an empty string — which is exactly the state a server event arrives in
  /// when the last sink has just been unplugged. Dereferencing it here would
  /// take down the isolate, and with it every volume reading in the shell.
  static PaServerInfo _serverInfoFromNative(Pointer<pa_server_info> info) {
    final s = info.ref;
    return PaServerInfo(
      defaultSinkName: _stringOrEmpty(s.default_sink_name),
      defaultSourceName: _stringOrEmpty(s.default_source_name),
    );
  }

  // Typed on `NativeType` rather than on the field's own pointer type: which
  // of `Pointer<Char>` / `Pointer<Int8>` ffigen emitted for `const char *`
  // is a detail of the generated bindings, and nothing here needs to know.
  static String _stringOrEmpty(Pointer<NativeType> p) =>
      p.address == 0 ? '' : p.cast<Utf8>().toDartString();

  // ---------------------------------------------------------------------------
  // Sink list
  // ---------------------------------------------------------------------------

  static void _getSinkList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaSink>[];
    final op = _pa.pa_context_get_sink_info_list(
        _inst!.ctx, Pointer.fromFunction(_onSinkListInfo), pId.cast());
    _register(op, () {
      final list = _inst!.accum.remove(id) as List<PaSink>;
      _inst!.port.send(_Reply(id, list));
      calloc.free(pId);
    });
  }

  static void _onSinkListInfo(Pointer<pa_context> c, Pointer<pa_sink_info> info,
      int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final id = ud.cast<Int>().value;
    (_inst!.accum[id] as List<PaSink>).add(_sinkFromNative(info.ref));
  }

  static void _onSinkInfoChanged(Pointer<pa_context> c,
      Pointer<pa_sink_info> info, int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final sink = _sinkFromNative(info.ref);
    pulseLog('sink changed: ${sink.name} vol=${sink.volume} mute=${sink.mute}');
    _inst!.port.send(_SinkChangedEvent(sink));
  }

  static PaSink _sinkFromNative(pa_sink_info s) {
    final pVol = calloc<pa_cvolume>()..ref = s.volume;
    final pMap = calloc<pa_channel_map>()..ref = s.channel_map;
    final avgVol = _pa.pa_cvolume_avg(pVol) / PA_VOLUME_NORM;
    final ch = s.channel_map.channels;
    final balance =
        ch >= 2 ? _pa.pa_cvolume_get_balance(pVol, pMap).clamp(-1.0, 1.0) : 0.0;
    calloc.free(pVol);
    calloc.free(pMap);
    final name = s.name.cast<Utf8>().toDartString();
    _inst!.sinkChannels[name] = ch;
    return PaSink(
      index: s.index,
      name: name,
      description: s.description.cast<Utf8>().toDartString(),
      mute: s.mute == 1,
      volume: avgVol,
      channelCount: ch,
      balance: balance,
    );
  }

  // ---------------------------------------------------------------------------
  // Source list
  // ---------------------------------------------------------------------------

  static void _getSourceList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaSource>[];
    final op = _pa.pa_context_get_source_info_list(
        _inst!.ctx, Pointer.fromFunction(_onSourceListInfo), pId.cast());
    _register(op, () {
      final list = _inst!.accum.remove(id) as List<PaSource>;
      _inst!.port.send(_Reply(id, list));
      calloc.free(pId);
    });
  }

  static void _onSourceListInfo(Pointer<pa_context> c,
      Pointer<pa_source_info> info, int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final id = ud.cast<Int>().value;
    (_inst!.accum[id] as List<PaSource>).add(_sourceFromNative(info.ref));
  }

  static void _onSourceInfoChanged(Pointer<pa_context> c,
      Pointer<pa_source_info> info, int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final source = _sourceFromNative(info.ref);
    pulseLog(
        'source changed: ${source.name} vol=${source.volume} mute=${source.mute}');
    _inst!.port.send(_SourceChangedEvent(source));
  }

  static PaSource _sourceFromNative(pa_source_info s) {
    final pVol = calloc<pa_cvolume>()..ref = s.volume;
    final avgVol = _pa.pa_cvolume_avg(pVol) / PA_VOLUME_NORM;
    calloc.free(pVol);
    final name = s.name.cast<Utf8>().toDartString();
    _inst!.sourceChannels[name] = s.channel_map.channels;
    return PaSource(
      index: s.index,
      name: name,
      description: s.description.cast<Utf8>().toDartString(),
      mute: s.mute == 1,
      volume: avgVol,
    );
  }

  // ---------------------------------------------------------------------------
  // Sink volume / mute / default
  // ---------------------------------------------------------------------------

  static void _setSinkVolume(int id, String name, double vol) {
    using((Arena a) {
      // As wide as the device: 2 hardcoded here set the wrong width on mono
      // and surround sinks. The cache is filled by every sink-info parse.
      final ch = _inst!.sinkChannels[name] ?? 2;
      final pVol = a<pa_cvolume>();
      _pa.pa_cvolume_init(pVol);
      _pa.pa_cvolume_set(pVol, ch, (vol * PA_VOLUME_NORM).ceil());
      final op = _pa.pa_context_set_sink_volume_by_name(_inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(), pVol, nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setSinkVolumeBalance(
      int id, String name, double vol, double balance, int channelCount) {
    using((Arena a) {
      final ch = channelCount > 0 ? channelCount : 2;
      final pVol = a<pa_cvolume>();
      final pMap = a<pa_channel_map>();
      _pa.pa_cvolume_init(pVol);
      _pa.pa_channel_map_init_auto(
          pMap, ch, pa_channel_map_def.PA_CHANNEL_MAP_DEFAULT);
      _pa.pa_cvolume_set(pVol, ch, (vol * PA_VOLUME_NORM).ceil());
      _pa.pa_cvolume_set_balance(pVol, pMap, balance);
      final op = _pa.pa_context_set_sink_volume_by_name(_inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(), pVol, nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setSinkMute(int id, String name, bool mute) {
    using((Arena a) {
      final op = _pa.pa_context_set_sink_mute_by_name(
          _inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(),
          mute ? 1 : 0,
          nullptr,
          nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setDefaultSink(int id, String name) {
    using((Arena a) {
      final op = _pa.pa_context_set_default_sink(
          _inst!.ctx, name.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  // ---------------------------------------------------------------------------
  // Source volume / mute / default
  // ---------------------------------------------------------------------------

  static void _setSourceVolume(int id, String name, double vol) {
    using((Arena a) {
      final ch = _inst!.sourceChannels[name] ?? 2;
      final pVol = a<pa_cvolume>();
      _pa.pa_cvolume_init(pVol);
      _pa.pa_cvolume_set(pVol, ch, (vol * PA_VOLUME_NORM).ceil());
      final op = _pa.pa_context_set_source_volume_by_name(_inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(), pVol, nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setSourceMute(int id, String name, bool mute) {
    using((Arena a) {
      final op = _pa.pa_context_set_source_mute_by_name(
          _inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(),
          mute ? 1 : 0,
          nullptr,
          nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setDefaultSource(int id, String name) {
    using((Arena a) {
      final op = _pa.pa_context_set_default_source(
          _inst!.ctx, name.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  // ---------------------------------------------------------------------------
  // Sink inputs (per-app streams)
  // ---------------------------------------------------------------------------

  static void _getSinkInputList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaSinkInput>[];
    final op = _pa.pa_context_get_sink_input_info_list(
        _inst!.ctx, Pointer.fromFunction(_onSinkInputInfo), pId.cast());
    _register(op, () {
      final list = _inst!.accum.remove(id) as List<PaSinkInput>;
      _inst!.port.send(_Reply(id, list));
      calloc.free(pId);
    });
  }

  static void _onSinkInputInfo(Pointer<pa_context> c,
      Pointer<pa_sink_input_info> info, int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final id = ud.cast<Int>().value;
    final s = info.ref;

    final pVol = calloc<pa_cvolume>()..ref = s.volume;
    final avgVol = _pa.pa_cvolume_avg(pVol) / PA_VOLUME_NORM;
    calloc.free(pVol);

    final ch = s.channel_map.channels;
    _inst!.sinkInputChannels[s.index] = ch;

    String appName = '';
    String mediaName = '';
    if (s.proplist.address != 0) {
      final appPtr = _pa.pa_proplist_gets(
          s.proplist, 'application.name'.toNativeUtf8().cast());
      if (appPtr.address != 0) appName = appPtr.cast<Utf8>().toDartString();
      final mediaPtr =
          _pa.pa_proplist_gets(s.proplist, 'media.name'.toNativeUtf8().cast());
      if (mediaPtr.address != 0) {
        mediaName = mediaPtr.cast<Utf8>().toDartString();
      }
    }
    if (appName.isEmpty) {
      appName =
          s.name.address != 0 ? s.name.cast<Utf8>().toDartString() : 'Unknown';
    }
    if (mediaName.isEmpty) mediaName = appName;

    (_inst!.accum[id] as List<PaSinkInput>).add(PaSinkInput(
      index: s.index,
      sinkIndex: s.sink,
      appName: appName,
      mediaName: mediaName,
      mute: s.mute == 1,
      volume: avgVol.clamp(0.0, 2.0),
      corked: s.corked == 1,
      channelCount: ch,
    ));
  }

  static void _setSinkInputVolume(int id, int idx, double vol) {
    using((Arena a) {
      final ch = _inst!.sinkInputChannels[idx] ?? 2;
      final pVol = a<pa_cvolume>();
      _pa.pa_cvolume_init(pVol);
      _pa.pa_cvolume_set(pVol, ch, (vol * PA_VOLUME_NORM).ceil());
      final op = _pa.pa_context_set_sink_input_volume(
          _inst!.ctx, idx, pVol, nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  static void _setSinkInputMute(int id, int idx, bool mute) {
    final op = _pa.pa_context_set_sink_input_mute(
        _inst!.ctx, idx, mute ? 1 : 0, nullptr, nullptr);
    _register(op, () => _inst!.port.send(_Reply(id)));
  }

  static void _moveSinkInput(int id, int inputIdx, String sinkName) {
    using((Arena a) {
      final op = _pa.pa_context_move_sink_input_by_name(_inst!.ctx, inputIdx,
          sinkName.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  // ---------------------------------------------------------------------------
  // Cards & profiles
  // ---------------------------------------------------------------------------

  static void _getCardList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaCard>[];
    final op = _pa.pa_context_get_card_info_list(
        _inst!.ctx, Pointer.fromFunction(_onCardInfo), pId.cast());
    _register(op, () {
      final list = _inst!.accum.remove(id) as List<PaCard>;
      _inst!.port.send(_Reply(id, list));
      calloc.free(pId);
    });
  }

  static void _onCardInfo(Pointer<pa_context> c, Pointer<pa_card_info> info,
      int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final id = ud.cast<Int>().value;
    final s = info.ref;

    final name = s.name.cast<Utf8>().toDartString();

    String description = name;
    if (s.proplist.address != 0) {
      final ptr = _pa.pa_proplist_gets(
          s.proplist, 'device.description'.toNativeUtf8().cast());
      if (ptr.address != 0) description = ptr.cast<Utf8>().toDartString();
    }

    String activeProfileName = '';
    if (s.active_profile2.address != 0) {
      final ap = s.active_profile2.ref;
      if (ap.name.address != 0) {
        activeProfileName = ap.name.cast<Utf8>().toDartString();
      }
    }

    final profiles = <PaCardProfile>[];
    final n = s.n_profiles;
    if (s.profiles2.address != 0) {
      for (int k = 0; k < n; k++) {
        final pp = (s.profiles2 + k).value;
        if (pp.address == 0) continue;
        final p = pp.ref;
        final pName =
            p.name.address != 0 ? p.name.cast<Utf8>().toDartString() : '';
        final pDesc = p.description.address != 0
            ? p.description.cast<Utf8>().toDartString()
            : pName;
        profiles.add(PaCardProfile(
          name: pName,
          description: pDesc,
          available: p.available != 0,
        ));
      }
    }

    (_inst!.accum[id] as List<PaCard>).add(PaCard(
      index: s.index,
      name: name,
      description: description,
      profiles: profiles,
      activeProfileName: activeProfileName,
      isBluez: name.startsWith('bluez_card.'),
    ));
  }

  static void _setCardProfile(int id, String cardName, String profileName) {
    using((Arena a) {
      final op = _pa.pa_context_set_card_profile_by_name(
          _inst!.ctx,
          cardName.toNativeUtf8(allocator: a).cast(),
          profileName.toNativeUtf8(allocator: a).cast(),
          nullptr,
          nullptr);
      _register(op, () => _inst!.port.send(_Reply(id)));
    });
  }

  // ---------------------------------------------------------------------------
  // Modules
  // ---------------------------------------------------------------------------

  static void _getModuleList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaModule>[];
    final op = _pa.pa_context_get_module_info_list(
        _inst!.ctx, Pointer.fromFunction(_onModuleInfo), pId.cast());
    _register(op, () {
      final list = _inst!.accum.remove(id) as List<PaModule>;
      _inst!.port.send(_Reply(id, list));
      calloc.free(pId);
    });
  }

  static void _onModuleInfo(Pointer<pa_context> c, Pointer<pa_module_info> info,
      int eol, Pointer<Void> ud) {
    if (eol > 0 || info.address == 0) return;
    final id = ud.cast<Int>().value;
    final s = info.ref;
    final mName = s.name.address != 0 ? s.name.cast<Utf8>().toDartString() : '';
    (_inst!.accum[id] as List<PaModule>)
        .add(PaModule(index: s.index, name: mName));
  }

  static void _loadModule(int id, String name, String args) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = -1; // will be overwritten by _onModuleIndex
    using((Arena a) {
      final op = _pa.pa_context_load_module(
          _inst!.ctx,
          name.toNativeUtf8(allocator: a).cast(),
          args.toNativeUtf8(allocator: a).cast(),
          Pointer.fromFunction(_onModuleIndex),
          pId.cast());
      _register(op, () {
        final idx = _inst!.accum.remove(id) as int;
        _inst!.port.send(_Reply(id, idx));
        calloc.free(pId);
      });
    });
  }

  static void _onModuleIndex(Pointer<pa_context> c, int idx, Pointer<Void> ud) {
    final id = ud.cast<Int>().value;
    // idx is PA_INVALID_INDEX (0xFFFFFFFF) on failure
    _inst!.accum[id] = (idx == 0xFFFFFFFF) ? -1 : idx;
  }

  static void _unloadModule(int id, int index) {
    final op =
        _pa.pa_context_unload_module(_inst!.ctx, index, nullptr, nullptr);
    _register(op, () => _inst!.port.send(_Reply(id)));
  }

  // ---------------------------------------------------------------------------
  // Level metering via pa_stream
  // ---------------------------------------------------------------------------

  static void _startLevelMeter(int id, String sourceName) {
    _stopLevelMeter(id); // stop any previous meter

    using((Arena a) {
      final pSpec = a<pa_sample_spec>();
      pSpec.ref.formatAsInt = PA_SAMPLE_S16LE;
      pSpec.ref.rate = 4000;
      pSpec.ref.channels = 1;

      final stream = _pa.pa_stream_new(_inst!.ctx,
          'level-meter'.toNativeUtf8(allocator: a).cast(), pSpec, nullptr);
      if (stream.address == 0) {
        _inst!.port.send(_Reply(id));
        return;
      }

      _pa.pa_stream_set_read_callback(
          stream, Pointer.fromFunction(_onStreamRead), nullptr);

      final ret = _pa.pa_stream_connect_record(
          stream,
          sourceName.toNativeUtf8(allocator: a).cast(),
          nullptr,
          pa_stream_flags.PA_STREAM_NOFLAGS);

      if (ret < 0) {
        _pa.pa_stream_unref(stream);
        _inst!.port.send(_Reply(id));
        return;
      }

      _inst!.levelStream = stream;
      _inst!.port.send(_Reply(id));
    });
  }

  static void _onStreamRead(
      Pointer<pa_stream> stream, int nbytes, Pointer<Void> ud) {
    if (_inst == null) return;

    final ppData = calloc<Pointer<Void>>();
    final pNbytes = calloc<Size>();

    _pa.pa_stream_peek(stream, ppData, pNbytes);

    final dataPtr = ppData.value;
    final byteCount = pNbytes.value;
    final sampleCount = byteCount ~/ 2;

    double level = 0.0;
    if (dataPtr.address != 0 && sampleCount > 0) {
      final samples = dataPtr.cast<Int16>().asTypedList(sampleCount);
      double sumSq = 0.0;
      for (final s in samples) {
        sumSq += s * s;
      }
      level = math.sqrt(sumSq / sampleCount) / 32768.0;
    }

    _pa.pa_stream_drop(stream);

    calloc.free(ppData);
    calloc.free(pNbytes);

    _inst!.port.send(_LevelEvent(level.clamp(0.0, 1.0)));
  }

  static void _stopLevelMeter(int id) {
    final stream = _inst?.levelStream;
    if (stream != null && stream.address != 0) {
      _pa.pa_stream_disconnect(stream);
      _pa.pa_stream_unref(stream);
      _inst!.levelStream = nullptr;
    }
    _inst?.port.send(_Reply(id));
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  static void _dispose() {
    final inst = _inst;
    if (inst == null) return;
    _inst = null;
    if (inst.levelStream.address != 0) {
      _pa.pa_stream_disconnect(inst.levelStream);
      _pa.pa_stream_unref(inst.levelStream);
    }
    _pa.pa_context_disconnect(inst.ctx);
    _pa.pa_context_unref(inst.ctx);
    _pa.pa_mainloop_free(inst.loop);
    Isolate.current.kill(priority: Isolate.immediate);
  }
}

// ---------------------------------------------------------------------------
// PulseClient — public API, lives in the main isolate
// ---------------------------------------------------------------------------

class PulseClient {
  PulseClient._(this._recv, this._broadcast);

  static PulseClient? _instance;

  final ReceivePort _recv;
  final Stream<dynamic> _broadcast;

  late final SendPort _sendPort;
  int _nextId = 0;
  int get _id => _nextId++;

  final _initCompleter = Completer<void>();
  bool _initStarted = false;

  factory PulseClient() {
    if (_instance != null) return _instance!;
    final recv = ReceivePort();
    final broadcast = recv.asBroadcastStream();
    _instance = PulseClient._(recv, broadcast);
    return _instance!;
  }

  Future<void> initialize() async {
    if (_initCompleter.isCompleted) return;
    if (_initStarted) return _initCompleter.future;
    _initStarted = true;

    _broadcast.listen((msg) {
      if (msg is SendPort) _sendPort = msg;
      if (msg is _ReadyEvent) {
        _loop = Pointer<pa_mainloop>.fromAddress(msg.loopAddress);
        if (!_initCompleter.isCompleted) _initCompleter.complete();
      }
    });

    await Isolate.spawn(_PaIsolate.entry, _recv.sendPort);
    await _initCompleter.future;
  }

  // --- request posting ---

  /// The PA isolate spends its time blocked inside `pa_mainloop_poll`, so a
  /// message posted to it is not seen until that poll returns. Waking the
  /// mainloop right after the send is what keeps the poll slice long (cheap at
  /// idle) without making requests wait for it.
  ///
  /// Two things bound how much this buys. `pa_mainloop_wakeup` writes a byte to
  /// a pipe that has no `pa_io_event`, so the wake is invisible to
  /// `pa_mainloop_dispatch` and only the driver's own (poll > 0, dispatched ==
  /// 0) rule notices it — see `_PaIsolate._cycle`. And `pa_mainloop_prepare`
  /// drains that pipe unconditionally before every poll, so a byte written
  /// while the isolate is between turns is swallowed; that request simply waits
  /// for the message queue, which the driver reaches at the end of each turn.
  Pointer<pa_mainloop>? _loop;
  late final PulseAudioBindings? _wakeBindings = () {
    try {
      return PulseAudioBindings(DynamicLibrary.open('libpulse.so.0'));
    } catch (_) {
      return null;
    }
  }();

  void _post(Object msg) {
    _sendPort.send(msg);
    final loop = _loop;
    if (loop != null) _wakeBindings?.pa_mainloop_wakeup(loop);
  }

  void dispose() {
    // Drop the pointer before the isolate frees the mainloop, so a late _post
    // cannot wake freed memory.
    _loop = null;
    _sendPort.send(const _Request(-1, _ReqKind.dispose));
    _recv.close();
    _instance = null;
  }

  // --- event streams ---

  Stream<PaSink> get onSinkChanged => _broadcast
      .where((m) => m is _SinkChangedEvent)
      .cast<_SinkChangedEvent>()
      .map((m) => m.sink);

  Stream<int> get onSinkRemoved => _broadcast
      .where((m) => m is _SinkRemovedEvent)
      .cast<_SinkRemovedEvent>()
      .map((m) => m.index);

  Stream<PaSource> get onSourceChanged => _broadcast
      .where((m) => m is _SourceChangedEvent)
      .cast<_SourceChangedEvent>()
      .map((m) => m.source);

  Stream<int> get onSourceRemoved => _broadcast
      .where((m) => m is _SourceRemovedEvent)
      .cast<_SourceRemovedEvent>()
      .map((m) => m.index);

  /// Fires when the default sink and/or source moves — see
  /// [_ServerChangedEvent] for why nothing else reports it.
  Stream<PaServerInfo> get onServerChanged => _broadcast
      .where((m) => m is _ServerChangedEvent)
      .cast<_ServerChangedEvent>()
      .map((m) => m.info);

  /// Fires when the isolate's connection to the server has been rebuilt after
  /// it went away — a `pipewire-pulse` restart, say — and never on the first
  /// connection, which every consumer seeds from anyway.
  ///
  /// Everything read before it is stale: the sink and source indices belong to
  /// the server that died, and so did the level meter's stream. A consumer
  /// answers this by re-running its own start-up seeding. See [_ConnectedEvent]
  /// for why this is not folded into [onServerChanged].
  Stream<void> get onReconnected =>
      _broadcast.where((m) => m is _ConnectedEvent).map((_) {});

  Stream<double> get _levelStream => _broadcast
      .where((m) => m is _LevelEvent)
      .cast<_LevelEvent>()
      .map((m) => m.level);

  // --- helpers ---

  void _assertReady() {
    if (!_initCompleter.isCompleted) {
      throw StateError('PulseClient not initialized');
    }
  }

  /// Posts [kind] to the isolate and completes when its [_Reply] arrives.
  Future<void> _call(_ReqKind kind, [List<Object?> args = const []]) {
    _assertReady();
    final id = _id;
    _post(_Request(id, kind, args));
    return _broadcast
        .firstWhere((m) => m is _Reply && m.id == id)
        .then((_) {});
  }

  /// Posts [kind] to the isolate and completes with its [_Reply]'s payload.
  Future<T> _callFor<T>(_ReqKind kind, [List<Object?> args = const []]) {
    _assertReady();
    final id = _id;
    _post(_Request(id, kind, args));
    return _broadcast
        .firstWhere((m) => m is _Reply && m.id == id)
        .then((m) => (m as _Reply).payload as T);
  }

  // --- server info ---

  Future<PaServerInfo> getServerInfo() => _callFor(_ReqKind.getServerInfo);

  // --- sinks ---

  Future<List<PaSink>> getSinkList() => _callFor(_ReqKind.getSinkList);

  Future<void> setSinkVolume(String name, double vol) =>
      _call(_ReqKind.setSinkVolume, [name, vol]);

  Future<void> setSinkVolumeBalance(
          String name, double vol, double balance, int channelCount) =>
      _call(_ReqKind.setSinkVolumeBalance, [name, vol, balance, channelCount]);

  Future<void> setSinkMute(String name, bool mute) =>
      _call(_ReqKind.setSinkMute, [name, mute]);

  Future<void> setDefaultSink(String name) =>
      _call(_ReqKind.setDefaultSink, [name]);

  // --- sources ---

  Future<List<PaSource>> getSourceList() => _callFor(_ReqKind.getSourceList);

  Future<void> setSourceVolume(String name, double vol) =>
      _call(_ReqKind.setSourceVolume, [name, vol]);

  Future<void> setSourceMute(String name, bool mute) =>
      _call(_ReqKind.setSourceMute, [name, mute]);

  Future<void> setDefaultSource(String name) =>
      _call(_ReqKind.setDefaultSource, [name]);

  // --- sink inputs (per-app) ---

  Future<List<PaSinkInput>> getSinkInputList() =>
      _callFor(_ReqKind.getSinkInputList);

  Future<void> setSinkInputVolume(int idx, double vol) =>
      _call(_ReqKind.setSinkInputVolume, [idx, vol]);

  Future<void> setSinkInputMute(int idx, bool mute) =>
      _call(_ReqKind.setSinkInputMute, [idx, mute]);

  Future<void> moveSinkInput(int inputIdx, String sinkName) =>
      _call(_ReqKind.moveSinkInput, [inputIdx, sinkName]);

  // --- cards & profiles ---

  Future<List<PaCard>> getCardList() => _callFor(_ReqKind.getCardList);

  Future<void> setCardProfile(String cardName, String profileName) =>
      _call(_ReqKind.setCardProfile, [cardName, profileName]);

  // --- modules ---

  Future<List<PaModule>> getModuleList() => _callFor(_ReqKind.getModuleList);

  Future<int> loadModule(String name, String args) =>
      _callFor(_ReqKind.loadModule, [name, args]);

  Future<void> unloadModule(int index) =>
      _call(_ReqKind.unloadModule, [index]);

  // --- level metering ---

  Stream<double> startLevelMeter(String sourceName) {
    _assertReady();
    _post(_Request(_id, _ReqKind.startLevelMeter, [sourceName]));
    // The isolate answers with a _Reply nobody awaits; the stream is returned
    // immediately and levels arrive as _LevelEvent frames on the broadcast.
    return _levelStream;
  }

  void stopLevelMeter() {
    if (!_initCompleter.isCompleted) return;
    _post(_Request(_id, _ReqKind.stopLevelMeter));
  }
}
