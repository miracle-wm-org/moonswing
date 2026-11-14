// Which compositor this session is, read from the environment alone.
//
// Flutter-free, so `moonswing-mcp` (`lib/mcp/`) answers the question the way
// the shell does; `miracle_manager.dart` re-exports it.

/// What the environment says about whether the shell is running under Miracle
/// WM, before any socket is opened.
enum MiracleSession {
  /// `MIRACLESOCK` is set, or `XDG_CURRENT_DESKTOP` names miracle-wm.
  miracle,

  /// Some other compositor: sway, Miriway, anything that is not miracle. The
  /// shell runs on it without the features that need Miracle's IPC.
  other,

  /// Only an i3-compatible socket (`SWAYSOCK`/`I3SOCK`) and no desktop name.
  /// miracle sets both of those too, and its session script exports them to
  /// systemd without `MIRACLESOCK`, so this is settled by asking the socket.
  undetermined,
}

/// The message a Miracle-only feature shows on any other compositor.
const String kNotMiracleMessage = 'Moonswing is not running under Miracle WM.';

/// Reads [environment] for which compositor the shell is running inside.
///
/// The sway and i3 socket variables are *not* evidence of miracle on their
/// own: sway sets `SWAYSOCK` too, and its IPC answers the i3 half of the
/// protocol while ignoring miracle's extensions outright — a `GET_KEYBINDS`
/// sent to sway is logged and never answered.
MiracleSession detectMiracleSession(Map<String, String> environment) {
  String? value(String key) {
    final v = environment[key];
    return v == null || v.isEmpty ? null : v;
  }

  if (value('MIRACLESOCK') != null) return MiracleSession.miracle;
  final desktop = value('XDG_CURRENT_DESKTOP');
  if (desktop != null) {
    // miracle's session script exports `mir:miracle-wm`, the snap's portal
    // half `miracle-wm:mir`; either order, any case.
    final names = desktop.toLowerCase().split(':');
    return names.contains('miracle-wm') || names.contains('miracle')
        ? MiracleSession.miracle
        : MiracleSession.other;
  }
  if (value('SWAYSOCK') == null && value('I3SOCK') == null) {
    return MiracleSession.other;
  }
  return MiracleSession.undetermined;
}
