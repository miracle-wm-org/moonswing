/// A stand-in for `package:volume_controller` that registers no plugin.
///
/// The shell never calls this: it is a transitive dependency of
/// `media_kit_video`, whose Material *controls* use it for a swipe-to-change-
/// volume gesture, and the wallpaper's `Video` is built with no controls. But
/// a Flutter plugin is registered at start-up whether or not anything calls
/// it, and the real one's Linux half opens the ALSA mixer in its instance
/// initialiser and throws `std::runtime_error` when that fails — no sound
/// card, no `Master` element, or (the reported case) a staged core22
/// `libasound` that cannot load the host's PipeWire ctl module:
///
///     ALSA lib dlmisc.c:337:(snd_dlobj_cache_get0) Cannot open shared library
///     libasound_module_ctl_pipewire.so (... version `ALSA_1.2.15' not found)
///     terminate called after throwing an instance of 'std::runtime_error'
///
/// The plugin wraps that in a `try`/`catch`, which cannot work here:
/// `libflutter_linux_gtk.so` exports its own `_Unwind_RaiseException`, the
/// throw resolves to it, and it does not unwind libstdc++ frames — so the
/// exception is never caught and the shell aborts before its first frame.
///
/// `pubspec.yaml` overrides the dependency with this package, so nothing
/// native is built, linked or registered. System volume is the shell's own
/// business anyway, over PulseAudio (`lib/osd/`, `lib/quick_panel/`).
library;

import 'dart:async';

/// The surface of the real `VolumeController` that `media_kit_video` names.
class VolumeController {
  VolumeController._();

  static final VolumeController _instance = VolumeController._();

  static VolumeController get instance => _instance;

  bool showSystemUI = true;

  StreamSubscription<double>? _listener;

  /// Never reports: nothing here watches the system volume.
  StreamSubscription<double> addListener(
    Function(double)? onData, {
    bool fetchInitialVolume = true,
  }) {
    removeListener();
    return _listener = const Stream<double>.empty().listen(onData);
  }

  void removeListener() {
    _listener?.cancel();
    _listener = null;
  }

  Future<double> getVolume() async => 0;

  Future<void> setVolume(double volume) async {}

  Future<bool> isMuted() async => false;

  Future<void> setMute(bool mute) async {}
}
