import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.config.showDate) ...[
          Text(_dateString,
              style: const TextStyle(fontSize: 16, color: Color(0xFFFFFFFF))),
          const SizedBox(width: 8),
        ],
        Text(_timeString,
            style: const TextStyle(fontSize: 16, color: Color(0xFFFFFFFF))),
      ],
    );
  }
}
