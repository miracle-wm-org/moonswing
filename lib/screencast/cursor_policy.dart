/// `AvailableCursorModes` bits, and the `cursor_mode` an application asks for.
const int cursorModeHidden = 1;
const int cursorModeEmbedded = 2;

/// The cursor is left out of the frames and sent beside each one as a
/// `SPA_META_Cursor`: position, hotspot and image. This is what Chromium (and
/// so every Electron recorder) asks for on Linux, whatever the page wanted —
/// it draws the cursor itself from the metadata. A backend that does not offer
/// it gets no `cursor_mode` from Chromium at all, which the portal reads as
/// hidden: a recording with no cursor in it.
const int cursorModeMetadata = 4;

/// `[screenshare] cursor`: whose call it is whether a shared stream shows the
/// pointer.
enum ScreencastCursor {
  /// What the application asked for — the portal contract.
  app,

  /// Always painted into the frames, whatever was asked: for a recorder that
  /// asks for no cursor and then cannot draw one of its own.
  always,

  /// Never in the stream, painted or as metadata.
  never;

  static ScreencastCursor? fromString(String value) =>
      switch (value.trim().toLowerCase()) {
        'app' => app,
        'always' => always,
        'never' => never,
        _ => null,
      };
}

/// The cursor mode a cast actually runs with. [requested] is the session's
/// `cursor_mode`, null when the application sent none; [available] is what the
/// backend advertised. Anything that is not exactly one advertised mode is the
/// portal's default, hidden.
int resolveCursorMode(
  ScreencastCursor policy, {
  required int? requested,
  required int available,
}) =>
    switch (policy) {
      ScreencastCursor.always => cursorModeEmbedded,
      ScreencastCursor.never => cursorModeHidden,
      ScreencastCursor.app => requested != null &&
              requested != 0 &&
              requested & (requested - 1) == 0 &&
              requested & available != 0
          ? requested
          : cursorModeHidden,
    };
