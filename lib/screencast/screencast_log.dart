/// Log hook for the screencast stack.
///
/// These files deliberately avoid Flutter imports so the standalone spike
/// tool (`tool/screencast_spike.dart`, plain `dart compile`) can exercise the
/// capture path outside the shell. `startScreencastService` points this at
/// `debugPrint`; the spike points it at stderr; the default is silence.
void Function(String message) screencastLog = (message) {};
