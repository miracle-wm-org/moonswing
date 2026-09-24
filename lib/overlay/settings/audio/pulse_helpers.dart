import 'package:moonswing/pulse_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<bool> isModuleLoaded(PulseClient client, String moduleName) async {
  try {
    final modules = await client.getModuleList();
    return modules.any((m) => m.name == moduleName);
  } catch (_) {
    return false;
  }
}

Future<int?> findModuleIndex(PulseClient client, String moduleName) async {
  try {
    final modules = await client.getModuleList();
    for (final m in modules) {
      if (m.name == moduleName) return m.index;
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Microphone monitor ("Hear microphone")
// ---------------------------------------------------------------------------

/// The `media.name` the monitor's loopback streams carry. It is what makes a
/// `module-loopback` recognisably this shell's: a loopback the user loaded
/// themselves has no such argument and is never touched.
const kMicMonitorTag = 'moonswing-mic-monitor';

/// Loads a `module-loopback` from [sourceName] to the default output.
///
/// No `sink=`, so the loopback plays wherever everything else plays and follows
/// the default output if it moves. Answers the module index, or null if the
/// server refused.
Future<int?> loadMicMonitor(PulseClient client, String sourceName) async {
  final idx = await client.loadModule(
    'module-loopback',
    'source=$sourceName'
        ' latency_msec=50'
        ' sink_input_properties=media.name=$kMicMonitorTag'
        ' source_output_properties=media.name=$kMicMonitorTag',
  );
  return idx < 0 ? null : idx;
}

/// Unloads every loopback this shell loaded, except [keep].
///
/// A module outlives the client that loaded it, so a shell that died with the
/// monitor on left the user hearing themselves with no switch on screen to stop
/// it. The input page sweeps on every load for that reason.
Future<void> unloadMicMonitors(PulseClient client, {int? keep}) async {
  try {
    final modules = await client.getModuleList();
    for (final m in modules) {
      if (m.name != 'module-loopback' || m.index == keep) continue;
      if (!m.argument.contains(kMicMonitorTag)) continue;
      await client.unloadModule(m.index);
    }
  } catch (_) {}
}
