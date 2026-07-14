import 'dart:async';

import 'package:flutter/foundation.dart';

/// What a shown indicator is reporting on.
enum OsdKind { volume, microphone, brightness }

/// One indicator's worth of state: what changed and where it now sits on its
/// 0..1 scale.
@immutable
class OsdRequest {
  const OsdRequest({
    required this.kind,
    required this.value,
    this.muted = false,
  });

  final OsdKind kind;

  /// Current level as a fraction of the device's min..max range.
  final double value;

  /// Only meaningful for [OsdKind.volume] and [OsdKind.microphone].
  final bool muted;

  @override
  bool operator ==(Object other) =>
      other is OsdRequest &&
      other.kind == kind &&
      other.value == value &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(kind, value, muted);
}

/// The single on-screen indicator the shell shows when volume, microphone
/// volume, or screen brightness changes.
///
/// Same shape as [NotificationStore] and [TrayStore]: a singleton
/// [ChangeNotifier] that a start-up function feeds and the window watches.
///
/// There is deliberately only one [current] request. A [show] call overwrites
/// whatever was on screen, so changing brightness while the volume bar is still
/// up replaces it rather than stacking a second indicator.
class OsdStore extends ChangeNotifier {
  OsdStore._();

  static final OsdStore instance = OsdStore._();

  @visibleForTesting
  factory OsdStore.forTesting({Duration hideDelay = kOsdHideDelay}) {
    final store = OsdStore._();
    store.hideDelay = hideDelay;
    return store;
  }

  /// How long the indicator stays up after the last change.
  Duration hideDelay = kOsdHideDelay;

  Timer? _hideTimer;

  OsdRequest? _current;

  /// The indicator to render, or null when none should exist. Stays non-null
  /// through the fade-out so the window survives long enough to animate; the
  /// window content clears it via [onFadeOutComplete].
  OsdRequest? get current => _current;

  bool _visible = false;

  /// Whether the indicator should be shown. Flipping to false is the signal to
  /// the window content to play its fade-out.
  bool get visible => _visible;

  /// Shows [kind] at [value], replacing any indicator already on screen and
  /// restarting the inactivity timer.
  void show(OsdKind kind, double value, {bool muted = false}) {
    _current = OsdRequest(
      kind: kind,
      value: value.clamp(0.0, 1.0),
      muted: muted,
    );
    _visible = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(hideDelay, _beginHide);
    notifyListeners();
  }

  void _beginHide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  /// Called by the window content once its fade-out has finished, so the host
  /// can tear the window down.
  void onFadeOutComplete() {
    if (_visible || _current == null) return;
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

/// Default inactivity delay before the indicator fades out.
const Duration kOsdHideDelay = Duration(milliseconds: 1500);
