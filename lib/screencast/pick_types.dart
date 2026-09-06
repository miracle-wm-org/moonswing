// The pick request/response types, shared by the portal backend (which asks) and
// the picker UI (which answers).
//
// Deliberately Flutter-free and in their own file: everything below the UI
// imports these without pulling in Flutter, which is what lets
// `tool/screencast_spike.dart` exercise the whole stack as a plain
// `dart compile exe` binary.

/// What the portal asked the user to choose from.
class PickRequest {
  const PickRequest({
    required this.appId,
    required this.monitors,
    required this.windows,
    required this.multiple,
  });

  /// The requesting application id (empty for unsandboxed callers).
  final String appId;
  final bool monitors;
  final bool windows;
  final bool multiple;
}

sealed class PickedSource {
  const PickedSource();
}

class PickedMonitor extends PickedSource {
  const PickedMonitor(this.connector);

  /// `wl_output.name` connector — the stable identity across the pick →
  /// stream handoff (both sides live on the capture connection).
  final String connector;
}

class PickedWindow extends PickedSource {
  const PickedWindow(this.identifier, this.title);

  /// `ext_foreign_toplevel_handle_v1.identifier` — stable per toplevel.
  final String identifier;
  final String title;
}

class PickResult {
  const PickResult(this.sources);
  final List<PickedSource> sources;
}

/// How the portal backend asks a user to choose. The shell answers with the
/// layer-shell picker overlay; tests and the spike tool answer directly.
abstract class SourcePicker {
  /// Resolves with null when the user (or the portal) declines.
  Future<PickResult?> pick(PickRequest request);

  /// Cancels an in-flight [pick] — the frontend closed the Request object.
  void cancel();
}
