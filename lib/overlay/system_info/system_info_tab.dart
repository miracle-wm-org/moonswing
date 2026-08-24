import 'package:flutter/widgets.dart';
import 'package:graceful_shell/overlay/system/stat_tile.dart';
import 'package:graceful_shell/system/system_info.dart';

/// The **System Info** overlay tab: a read-only summary of the machine's
/// hardware, software, and desktop environment.
///
/// The data is static for a session, so — unlike the live System monitor tab —
/// this reads once in [initState] and never polls, and holds no lease on any
/// store. Until the read resolves, every value shows the em-dash placeholder.
class SystemInfoTab extends StatefulWidget {
  const SystemInfoTab({super.key});

  @override
  State<SystemInfoTab> createState() => _SystemInfoTabState();
}

class _SystemInfoTabState extends State<SystemInfoTab> {
  SystemInfo _info = const SystemInfo();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await SystemInfoReader().read();
    if (!mounted) return;
    setState(() => _info = info);
  }

  /// Width of the label column in every pair on this page.
  ///
  /// One value for all three sections, rather than per-section intrinsics, so
  /// the values line up down the whole page and the eye tracks a single
  /// column. Sized for the longest label here ("Operating system").
  static const double _labelWidth = 150;

  /// One pair. The label column is spelled once, here, so no section can drift
  /// out of the shared column — and the em-dash placeholder for a field this
  /// machine did not report comes with it.
  static StatLine _row(String label, String? value) => StatLine(
        label: label,
        labelWidth: _labelWidth,
        value: value ?? '—',
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        SystemCard(
          title: 'Hardware',
          children: [
            _row('Processor', _info.cpuModel),
            _row('Cores', _info.cpuCores),
            _row('Memory', _info.totalMemory),
            _row('Swap', _info.totalSwap),
            _row('Graphics', _info.gpu),
          ],
        ),
        const SizedBox(height: 24),
        SystemCard(
          title: 'Software',
          children: [
            _row('Operating system', _info.osName),
            _row('Kernel', _info.kernel),
            _row('Architecture', _info.architecture),
          ],
        ),
        const SizedBox(height: 24),
        SystemCard(
          title: 'Environment',
          children: [
            _row('Desktop', _info.desktop),
            _row('Session', _info.sessionType),
            _row('Shell', _info.shell),
            _row('Hostname', _info.hostname),
            _row('Uptime', _info.uptime),
            _row('Booted', _info.bootTime),
          ],
        ),
      ],
    );
  }
}
