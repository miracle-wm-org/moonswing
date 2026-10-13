/// Log hook for the input-capture stack.
///
/// Flutter-free for the same reason as `screencastLog`: `main.dart` points this
/// at `debugPrint`, `tool/screencast_spike.dart` at stderr, and the default is
/// silence.
void Function(String message) inputCaptureLog = (_) {};
