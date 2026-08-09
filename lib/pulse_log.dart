import 'dart:io';

/// Log hook for the PulseAudio client.
///
/// Unlike `screencastLog`, this is not a hook `main()` installs: half of what
/// is worth logging happens inside the client's own isolate, and a top-level
/// assignment does not cross an isolate boundary. Gating on the environment
/// instead turns both halves on together — `GRACEFUL_PULSE_LOG=1`.
final bool pulseLogEnabled =
    (Platform.environment['GRACEFUL_PULSE_LOG'] ?? '').isNotEmpty;

/// Writes straight to stdout rather than through `debugPrint`, which throttles
/// and would drop exactly the bursts this exists to observe — and which the PA
/// isolate has no Flutter binding for anyway.
void pulseLog(String message) {
  if (!pulseLogEnabled) return;
  stdout.writeln('pulse: $message');
}
