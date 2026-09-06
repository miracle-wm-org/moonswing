// Diagnostics for the polkit agent, in the shape `lib/pulse_log.dart` and the
// screencast layer use: a top-level hook that does nothing until `main()` points
// it at `debugPrint`.
//
// Its own file rather than a member of `polkit_agent.dart` because the layers
// underneath — the helper process in particular — have things worth reporting and
// must not import the D-Bus object to say them. Nothing here ever logs a prompt,
// a response or a cookie.
library;

void Function(String message) polkitLog = (_) {};
