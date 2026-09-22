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
