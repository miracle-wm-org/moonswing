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
// ---------------------------------------------------------------------------

class _GetServerInfoReq {
  const _GetServerInfoReq(this.id);
  final int id;
}

class _GetSinkListReq {
  const _GetSinkListReq(this.id);
  final int id;
}

class _GetSourceListReq {
  const _GetSourceListReq(this.id);
  final int id;
}

class _SetSinkVolumeReq {
  const _SetSinkVolumeReq(this.id, this.name, this.vol);
  final int id;
  final String name;
  final double vol;
}

class _SetSinkVolumeBalanceReq {
  const _SetSinkVolumeBalanceReq(
      this.id, this.name, this.vol, this.balance, this.channelCount);
  final int id;
  final String name;
  final double vol;
  final double balance;
  final int channelCount;
}

class _SetSinkMuteReq {
  const _SetSinkMuteReq(this.id, this.name, this.mute);
  final int id;
  final String name;
  final bool mute;
}

class _SetDefaultSinkReq {
  const _SetDefaultSinkReq(this.id, this.name);
  final int id;
  final String name;
}

class _SetSourceVolumeReq {
  const _SetSourceVolumeReq(this.id, this.name, this.vol);
  final int id;
  final String name;
  final double vol;
}

class _SetSourceMuteReq {
  const _SetSourceMuteReq(this.id, this.name, this.mute);
  final int id;
  final String name;
  final bool mute;
}

class _SetDefaultSourceReq {
  const _SetDefaultSourceReq(this.id, this.name);
  final int id;
  final String name;
}

class _GetSinkInputListReq {
  const _GetSinkInputListReq(this.id);
  final int id;
}

class _SetSinkInputVolumeReq {
  const _SetSinkInputVolumeReq(this.id, this.idx, this.vol);
  final int id;
  final int idx;
  final double vol;
}

class _SetSinkInputMuteReq {
  const _SetSinkInputMuteReq(this.id, this.idx, this.mute);
  final int id;
  final int idx;
  final bool mute;
}

class _MoveSinkInputReq {
  const _MoveSinkInputReq(this.id, this.inputIdx, this.sinkName);
  final int id;
  final int inputIdx;
  final String sinkName;
}

class _GetCardListReq {
  const _GetCardListReq(this.id);
  final int id;
}

class _SetCardProfileReq {
  const _SetCardProfileReq(this.id, this.cardName, this.profileName);
  final int id;
  final String cardName;
  final String profileName;
}

class _GetModuleListReq {
  const _GetModuleListReq(this.id);
  final int id;
}

class _LoadModuleReq {
  const _LoadModuleReq(this.id, this.name, this.args);
  final int id;
  final String name;
  final String args;
}

class _UnloadModuleReq {
  const _UnloadModuleReq(this.id, this.index);
  final int id;
  final int index;
}

class _StartLevelMeterReq {
  const _StartLevelMeterReq(this.id, this.sourceName);
  final int id;
  final String sourceName;
}

class _StopLevelMeterReq {
  const _StopLevelMeterReq(this.id);
  final int id;
}

class _DisposeReq {
  const _DisposeReq();
}

// --- responses ---

class _ReadyRes {
  const _ReadyRes(this.loopAddress);

  /// Address of the isolate's `pa_mainloop`, so the main isolate can break the
  /// poll when it posts a request. See [PulseClient._post] for what that is
  /// and is not worth.
  final int loopAddress;
}

class _DoneRes {
  const _DoneRes(this.id);
  final int id;
}

class _ServerInfoRes {
  const _ServerInfoRes(this.id, this.info);
  final int id;
  final PaServerInfo info;
}

class _SinkListRes {
  const _SinkListRes(this.id, this.list);
  final int id;
  final List<PaSink> list;
}

class _SourceListRes {
  const _SourceListRes(this.id, this.list);
  final int id;
  final List<PaSource> list;
}

class _SinkInputListRes {
  const _SinkInputListRes(this.id, this.list);
  final int id;
  final List<PaSinkInput> list;
}

class _CardListRes {
  const _CardListRes(this.id, this.list);
  final int id;
  final List<PaCard> list;
}

class _ModuleListRes {
  const _ModuleListRes(this.id, this.list);
  final int id;
  final List<PaModule> list;
}

class _LoadModuleRes {
  const _LoadModuleRes(this.id, this.moduleIndex);
  final int id;
  final int moduleIndex;
}

class _LevelRes {
  const _LevelRes(this.level);
  final double level;
}

class _SinkChangedRes {
  const _SinkChangedRes(this.sink);
  final PaSink sink;
}

class _SinkRemovedRes {
  const _SinkRemovedRes(this.index);
  final int index;
}

class _SourceChangedRes {
  const _SourceChangedRes(this.source);
  final PaSource source;
}

class _SourceRemovedRes {
  const _SourceRemovedRes(this.index);
  final int index;
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
  final Pointer<pa_context> ctx;

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
    final ctx = _pa.pa_context_new(api, 'PulseClient'.toNativeUtf8().cast());
    _pa.pa_context_connect(
        ctx, nullptr, pa_context_flags.PA_CONTEXT_NOAUTOSPAWN, nullptr);

    _inst = _PaIsolate._(port, loop, api, ctx);

    _pa.pa_context_set_state_callback(
        ctx, Pointer.fromFunction(_onCtxState), nullptr);

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

  static void _handleMsg(dynamic msg) {
    switch (msg) {
      case _DisposeReq():
        _dispose();
      case _GetServerInfoReq(:final id):
        _getServerInfo(id);
      case _GetSinkListReq(:final id):
        _getSinkList(id);
      case _GetSourceListReq(:final id):
        _getSourceList(id);
      case _SetSinkVolumeReq(:final id, :final name, :final vol):
        _setSinkVolume(id, name, vol);
      case _SetSinkVolumeBalanceReq(
          :final id,
          :final name,
          :final vol,
          :final balance,
          :final channelCount
        ):
        _setSinkVolumeBalance(id, name, vol, balance, channelCount);
      case _SetSinkMuteReq(:final id, :final name, :final mute):
        _setSinkMute(id, name, mute);
      case _SetDefaultSinkReq(:final id, :final name):
        _setDefaultSink(id, name);
      case _SetSourceVolumeReq(:final id, :final name, :final vol):
        _setSourceVolume(id, name, vol);
      case _SetSourceMuteReq(:final id, :final name, :final mute):
        _setSourceMute(id, name, mute);
      case _SetDefaultSourceReq(:final id, :final name):
        _setDefaultSource(id, name);
      case _GetSinkInputListReq(:final id):
        _getSinkInputList(id);
      case _SetSinkInputVolumeReq(:final id, :final idx, :final vol):
        _setSinkInputVolume(id, idx, vol);
      case _SetSinkInputMuteReq(:final id, :final idx, :final mute):
        _setSinkInputMute(id, idx, mute);
      case _MoveSinkInputReq(:final id, :final inputIdx, :final sinkName):
        _moveSinkInput(id, inputIdx, sinkName);
      case _GetCardListReq(:final id):
        _getCardList(id);
      case _SetCardProfileReq(:final id, :final cardName, :final profileName):
        _setCardProfile(id, cardName, profileName);
      case _GetModuleListReq(:final id):
        _getModuleList(id);
      case _LoadModuleReq(:final id, :final name, :final args):
        _loadModule(id, name, args);
      case _UnloadModuleReq(:final id, :final index):
        _unloadModule(id, index);
      case _StartLevelMeterReq(:final id, :final sourceName):
        _startLevelMeter(id, sourceName);
      case _StopLevelMeterReq(:final id):
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
      _inst!.port.send(_ReadyRes(_inst!.loop.address));
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
        // no-op for now
        break;
      case PA_SUBSCRIPTION_EVENT_SINK:
        if (eventType == PA_SUBSCRIPTION_EVENT_REMOVE) {
          _inst!.port.send(_SinkRemovedRes(idx));
        } else {
          op = _pa.pa_context_get_sink_info_by_index(
              c, idx, Pointer.fromFunction(_onSinkInfoChanged), nullptr);
        }
      case PA_SUBSCRIPTION_EVENT_SOURCE:
        if (eventType == PA_SUBSCRIPTION_EVENT_REMOVE) {
          _inst!.port.send(_SourceRemovedRes(idx));
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
    _inst!.ops[op] = () {
      // Unlike every other list query this one does not pre-seed `accum`, so a
      // cancelled operation reaches here with nothing to send. Answer anyway —
      // the main isolate is awaiting this id and would otherwise wait forever.
      _inst!.port.send(_inst!.accum.remove(id) ??
          _ServerInfoRes(
            id,
            const PaServerInfo(defaultSinkName: '', defaultSourceName: ''),
          ));
      calloc.free(pId);
    };
  }

  static void _onServerInfo(
      Pointer<pa_context> c, Pointer<pa_server_info> info, Pointer<Void> ud) {
    final id = ud.cast<Int>().value;
    final s = info.ref;
    _inst!.accum[id] = _ServerInfoRes(
      id,
      PaServerInfo(
        defaultSinkName: s.default_sink_name.cast<Utf8>().toDartString(),
        defaultSourceName: s.default_source_name.cast<Utf8>().toDartString(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sink list
  // ---------------------------------------------------------------------------

  static void _getSinkList(int id) {
    final pId = calloc<Int>()..value = id;
    _inst!.accum[id] = <PaSink>[];
    final op = _pa.pa_context_get_sink_info_list(
        _inst!.ctx, Pointer.fromFunction(_onSinkListInfo), pId.cast());
    _inst!.ops[op] = () {
      final list = _inst!.accum.remove(id) as List<PaSink>;
      _inst!.port.send(_SinkListRes(id, list));
      calloc.free(pId);
    };
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
    _inst!.port.send(_SinkChangedRes(sink));
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
    _inst!.ops[op] = () {
      final list = _inst!.accum.remove(id) as List<PaSource>;
      _inst!.port.send(_SourceListRes(id, list));
      calloc.free(pId);
    };
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
    _inst!.port.send(_SourceChangedRes(source));
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
    });
  }

  static void _setDefaultSink(int id, String name) {
    using((Arena a) {
      final op = _pa.pa_context_set_default_sink(
          _inst!.ctx, name.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
    });
  }

  static void _setDefaultSource(int id, String name) {
    using((Arena a) {
      final op = _pa.pa_context_set_default_source(
          _inst!.ctx, name.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
    _inst!.ops[op] = () {
      final list = _inst!.accum.remove(id) as List<PaSinkInput>;
      _inst!.port.send(_SinkInputListRes(id, list));
      calloc.free(pId);
    };
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
      if (mediaPtr.address != 0)
        mediaName = mediaPtr.cast<Utf8>().toDartString();
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
    });
  }

  static void _setSinkInputMute(int id, int idx, bool mute) {
    final op = _pa.pa_context_set_sink_input_mute(
        _inst!.ctx, idx, mute ? 1 : 0, nullptr, nullptr);
    _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
  }

  static void _moveSinkInput(int id, int inputIdx, String sinkName) {
    using((Arena a) {
      final op = _pa.pa_context_move_sink_input_by_name(_inst!.ctx, inputIdx,
          sinkName.toNativeUtf8(allocator: a).cast(), nullptr, nullptr);
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
    _inst!.ops[op] = () {
      final list = _inst!.accum.remove(id) as List<PaCard>;
      _inst!.port.send(_CardListRes(id, list));
      calloc.free(pId);
    };
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
      _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
    _inst!.ops[op] = () {
      final list = _inst!.accum.remove(id) as List<PaModule>;
      _inst!.port.send(_ModuleListRes(id, list));
      calloc.free(pId);
    };
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
      _inst!.ops[op] = () {
        final idx = _inst!.accum.remove(id) as int;
        _inst!.port.send(_LoadModuleRes(id, idx));
        calloc.free(pId);
      };
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
    _inst!.ops[op] = () => _inst!.port.send(_DoneRes(id));
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
        _inst!.port.send(_DoneRes(id));
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
        _inst!.port.send(_DoneRes(id));
        return;
      }

      _inst!.levelStream = stream;
      _inst!.port.send(_DoneRes(id));
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

    _inst!.port.send(_LevelRes(level.clamp(0.0, 1.0)));
  }

  static void _stopLevelMeter(int id) {
    final stream = _inst?.levelStream;
    if (stream != null && stream.address != 0) {
      _pa.pa_stream_disconnect(stream);
      _pa.pa_stream_unref(stream);
      _inst!.levelStream = nullptr;
    }
    _inst?.port.send(_DoneRes(id));
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
      if (msg is _ReadyRes) {
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
    _sendPort.send(const _DisposeReq());
    _recv.close();
    _instance = null;
  }

  // --- event streams ---

  Stream<PaSink> get onSinkChanged => _broadcast
      .where((m) => m is _SinkChangedRes)
      .cast<_SinkChangedRes>()
      .map((m) => m.sink);

  Stream<int> get onSinkRemoved => _broadcast
      .where((m) => m is _SinkRemovedRes)
      .cast<_SinkRemovedRes>()
      .map((m) => m.index);

  Stream<PaSource> get onSourceChanged => _broadcast
      .where((m) => m is _SourceChangedRes)
      .cast<_SourceChangedRes>()
      .map((m) => m.source);

  Stream<int> get onSourceRemoved => _broadcast
      .where((m) => m is _SourceRemovedRes)
      .cast<_SourceRemovedRes>()
      .map((m) => m.index);

  Stream<double> get _levelStream => _broadcast
      .where((m) => m is _LevelRes)
      .cast<_LevelRes>()
      .map((m) => m.level);

  // --- helpers ---

  void _assertReady() {
    if (!_initCompleter.isCompleted) {
      throw StateError('PulseClient not initialized');
    }
  }

  // --- server info ---

  Future<PaServerInfo> getServerInfo() {
    _assertReady();
    final id = _id;
    _post(_GetServerInfoReq(id));
    return _broadcast
        .firstWhere((m) => m is _ServerInfoRes && m.id == id)
        .then((m) => (m as _ServerInfoRes).info);
  }

  // --- sinks ---

  Future<List<PaSink>> getSinkList() {
    _assertReady();
    final id = _id;
    _post(_GetSinkListReq(id));
    return _broadcast
        .firstWhere((m) => m is _SinkListRes && m.id == id)
        .then((m) => (m as _SinkListRes).list);
  }

  Future<void> setSinkVolume(String name, double vol) {
    _assertReady();
    final id = _id;
    _post(_SetSinkVolumeReq(id, name, vol));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setSinkVolumeBalance(
      String name, double vol, double balance, int channelCount) {
    _assertReady();
    final id = _id;
    _post(_SetSinkVolumeBalanceReq(id, name, vol, balance, channelCount));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setSinkMute(String name, bool mute) {
    _assertReady();
    final id = _id;
    _post(_SetSinkMuteReq(id, name, mute));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setDefaultSink(String name) {
    _assertReady();
    final id = _id;
    _post(_SetDefaultSinkReq(id, name));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  // --- sources ---

  Future<List<PaSource>> getSourceList() {
    _assertReady();
    final id = _id;
    _post(_GetSourceListReq(id));
    return _broadcast
        .firstWhere((m) => m is _SourceListRes && m.id == id)
        .then((m) => (m as _SourceListRes).list);
  }

  Future<void> setSourceVolume(String name, double vol) {
    _assertReady();
    final id = _id;
    _post(_SetSourceVolumeReq(id, name, vol));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setSourceMute(String name, bool mute) {
    _assertReady();
    final id = _id;
    _post(_SetSourceMuteReq(id, name, mute));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setDefaultSource(String name) {
    _assertReady();
    final id = _id;
    _post(_SetDefaultSourceReq(id, name));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  // --- sink inputs (per-app) ---

  Future<List<PaSinkInput>> getSinkInputList() {
    _assertReady();
    final id = _id;
    _post(_GetSinkInputListReq(id));
    return _broadcast
        .firstWhere((m) => m is _SinkInputListRes && m.id == id)
        .then((m) => (m as _SinkInputListRes).list);
  }

  Future<void> setSinkInputVolume(int idx, double vol) {
    _assertReady();
    final id = _id;
    _post(_SetSinkInputVolumeReq(id, idx, vol));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> setSinkInputMute(int idx, bool mute) {
    _assertReady();
    final id = _id;
    _post(_SetSinkInputMuteReq(id, idx, mute));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  Future<void> moveSinkInput(int inputIdx, String sinkName) {
    _assertReady();
    final id = _id;
    _post(_MoveSinkInputReq(id, inputIdx, sinkName));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  // --- cards & profiles ---

  Future<List<PaCard>> getCardList() {
    _assertReady();
    final id = _id;
    _post(_GetCardListReq(id));
    return _broadcast
        .firstWhere((m) => m is _CardListRes && m.id == id)
        .then((m) => (m as _CardListRes).list);
  }

  Future<void> setCardProfile(String cardName, String profileName) {
    _assertReady();
    final id = _id;
    _post(_SetCardProfileReq(id, cardName, profileName));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  // --- modules ---

  Future<List<PaModule>> getModuleList() {
    _assertReady();
    final id = _id;
    _post(_GetModuleListReq(id));
    return _broadcast
        .firstWhere((m) => m is _ModuleListRes && m.id == id)
        .then((m) => (m as _ModuleListRes).list);
  }

  Future<int> loadModule(String name, String args) {
    _assertReady();
    final id = _id;
    _post(_LoadModuleReq(id, name, args));
    return _broadcast
        .firstWhere((m) => m is _LoadModuleRes && m.id == id)
        .then((m) => (m as _LoadModuleRes).moduleIndex);
  }

  Future<void> unloadModule(int index) {
    _assertReady();
    final id = _id;
    _post(_UnloadModuleReq(id, index));
    return _broadcast
        .firstWhere((m) => m is _DoneRes && m.id == id)
        .then((_) {});
  }

  // --- level metering ---

  Stream<double> startLevelMeter(String sourceName) {
    _assertReady();
    final id = _id;
    _post(_StartLevelMeterReq(id, sourceName));
    // Wait for the _DoneRes before streaming, but return the stream immediately.
    // Levels arrive as _LevelRes events on the broadcast stream.
    return _levelStream;
  }

  void stopLevelMeter() {
    if (!_initCompleter.isCompleted) return;
    final id = _id;
    _post(_StopLevelMeterReq(id));
  }
}
