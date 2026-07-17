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

  static String _v(String? value) => value ?? '—';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SystemCard(
          title: 'Hardware',
          children: [
            StatLine(label: 'Processor', value: _v(_info.cpuModel)),
            StatLine(label: 'Cores', value: _v(_info.cpuCores)),
            StatLine(label: 'Memory', value: _v(_info.totalMemory)),
            StatLine(label: 'Swap', value: _v(_info.totalSwap)),
            StatLine(label: 'Graphics', value: _v(_info.gpu)),
          ],
        ),
        const SizedBox(height: 12),
        SystemCard(
          title: 'Software',
          children: [
            StatLine(label: 'Operating system', value: _v(_info.osName)),
            StatLine(label: 'Kernel', value: _v(_info.kernel)),
            StatLine(label: 'Architecture', value: _v(_info.architecture)),
          ],
        ),
        const SizedBox(height: 12),
        SystemCard(
          title: 'Environment',
          children: [
            StatLine(label: 'Desktop', value: _v(_info.desktop)),
            StatLine(label: 'Session', value: _v(_info.sessionType)),
            StatLine(label: 'Shell', value: _v(_info.shell)),
            StatLine(label: 'Hostname', value: _v(_info.hostname)),
            StatLine(label: 'Uptime', value: _v(_info.uptime)),
            StatLine(label: 'Booted', value: _v(_info.bootTime)),
          ],
        ),
      ],
    );
  }
}
