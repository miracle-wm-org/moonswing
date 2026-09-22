import 'package:flutter/widgets.dart';
import 'package:moonswing/overlay/system/stat_tile.dart';
import 'package:moonswing/system/input_devices.dart';
import 'package:moonswing/system/system_info.dart';

/// The **System Info** overlay tab: a read-only summary of the machine's
/// hardware, its input devices, its software, and the desktop environment.
///
/// The data is static for a session, so — unlike the live System monitor tab —
/// this reads once in [initState] and never polls, and holds no lease. Until the
/// read resolves, every value shows the em-dash placeholder.
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
  /// One value for all four sections, rather than per-section intrinsics, so the
  /// values line up down the whole page. Sized for the longest label here.
  static const double _labelWidth = 150;

  /// One pair. The label column is spelled once, here, so no section can drift
  /// out of the shared column — and the em-dash placeholder for a field this
  /// machine did not report comes with it.
  static StatLine _row(String label, String? value) => StatLine(
        label: label,
        labelWidth: _labelWidth,
        value: value ?? '—',
      );

  /// One row per device, each under its own kind, in the order
  /// [InputDeviceReader.read] settled on.
  ///
  /// The kind is repeated on every row rather than heading a group of them,
  /// because the page's whole shape is a label column against a value column: a
  /// device whose label cell were left blank would read as a continuation of the
  /// value above it. An empty list gets the page's em-dash placeholder under a
  /// single "Devices" label.
  static List<Widget> _inputRows(List<InputDevice> devices) {
    if (devices.isEmpty) return [_row('Devices', null)];
    return [for (final device in devices) _row(device.kind.label, device.name)];
  }

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
          title: 'Input devices',
          children: _inputRows(_info.inputDevices),
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
