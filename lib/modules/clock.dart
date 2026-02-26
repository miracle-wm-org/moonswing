import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class ClockConfig {
  final bool showDate;

  const ClockConfig({this.showDate = true});

  factory ClockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClockConfig();
    return ClockConfig(
      showDate: map['show_date'] as bool? ?? true,
    );
  }
}

class Clock extends StatefulWidget {
  const Clock({super.key, required this.config});

  final ClockConfig config;

  @override
  ClockState createState() => ClockState();
}

class ClockState extends State<Clock> {
  late String _timeString;
  late String _dateString;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timeString = _formatTime(now);
    _dateString = _formatDate(now);
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final msUntilNextSecond = 1000 - now.millisecond;
    _timer = Timer(Duration(milliseconds: msUntilNextSecond), () {
      _updateTime();
      _scheduleNextTick();
    });
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _timeString = _formatTime(now);
      _dateString = _formatDate(now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${_months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = ThemeScope.of(context).foreground;
    final style = TextStyle(fontSize: 16, color: foreground);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.config.showDate) ...[
          Text(_dateString, style: style),
          const SizedBox(width: 8),
        ],
        Text(_timeString, style: style),
      ],
    );
  }
}

class ClockModule extends Module {
  ClockConfig _config = const ClockConfig();

  @override
  String get configKey => 'clock';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = ClockConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Clock(config: _config);
}
