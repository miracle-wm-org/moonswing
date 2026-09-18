import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/background.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/lock/pam_authenticator.dart';
import 'package:graceful_shell/lock/user_identity.dart';

/// The lock screen drawn on an `ext-session-lock-v1` surface.
///
/// Starts as just a clock and the account name over the wallpaper. The password
/// field is revealed by the unlock button, Enter, or any other key — and
/// revealing it blurs the wallpaper behind it, so the state of the screen reads
/// at a glance from across the room.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.config,
    required this.onUnlocked,
  });

  final LockConfig config;

  /// Called once PAM has accepted the password. The shell root unlocks the
  /// session and tears these windows down.
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  final FocusNode _screenFocus = FocusNode(debugLabel: 'lock-screen');
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'lock-password');
  final TextEditingController _password = TextEditingController();

  late final UserIdentity _user;
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _promptVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = UserIdentity.current();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      // Only repaint when a displayed field actually changes.
      if (now.minute == _now.minute && now.day == _now.day) return;
      setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _screenFocus.dispose();
    _fieldFocus.dispose();
    _password.dispose();
    super.dispose();
  }

  // A modifier on its own should not count as "any key" — otherwise merely
  // resting a hand on Shift pops the password field open.
  static bool _isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock ||
        key == LogicalKeyboardKey.numLock ||
        key == LogicalKeyboardKey.scrollLock ||
        key == LogicalKeyboardKey.fn;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (!_promptVisible) return KeyEventResult.ignored;
      // First Escape drops focus out of the field, second dismisses it.
      if (_fieldFocus.hasFocus) {
        _fieldFocus.unfocus();
        _screenFocus.requestFocus();
      } else {
        _hidePrompt();
      }
      return KeyEventResult.handled;
    }

    if (_isModifier(key)) return KeyEventResult.ignored;

    if (!_promptVisible) {
      // Carry a printable first keystroke into the field so the character the
      // user typed is not swallowed by the reveal.
      final character = event.character;
      final seed = (character != null &&
              character.isNotEmpty &&
              character.codeUnitAt(0) >= 0x20)
          ? character
          : null;
      _showPrompt(seed: seed);
      return KeyEventResult.handled;
    }

    // Prompt is up but focus fell out of the field (after one Escape) — typing
    // should put it back.
    if (!_fieldFocus.hasFocus) {
      _fieldFocus.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showPrompt({String? seed}) {
    if (_promptVisible) {
      _fieldFocus.requestFocus();
      return;
    }
    setState(() {
      _promptVisible = true;
      _error = null;
      if (seed != null) {
        _password.text = seed;
        _password.selection =
            TextSelection.collapsed(offset: _password.text.length);
      }
    });
    // The field does not exist until this frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  void _hidePrompt() {
    _fieldFocus.unfocus();
    setState(() {
      _promptVisible = false;
      _error = null;
      _password.clear();
    });
    _screenFocus.requestFocus();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await PamAuthenticator.authenticate(password);
    if (!mounted) return;

    if (result == PamResult.success) {
      // Leave the field as-is; the window is about to be destroyed.
      widget.onUnlocked();
      return;
    }

    setState(() {
      _busy = false;
      _error = result == PamResult.unavailable
          ? 'Authentication is unavailable'
          : 'Incorrect password';
      _password.clear();
    });
    _fieldFocus.requestFocus();
  }

  /// The wallpaper to draw, falling back to the shipped default and then to a
  /// plain dark fill.
  String? get _backgroundPath {
    final configured = widget.config.background;
    if (configured != null &&
        configured.isNotEmpty &&
        File(configured).existsSync()) {
      return configured;
    }
    return shippedDataFile('lock-wallpaper.jpg');
  }

  String get _timeText =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  String get _dateText =>
      '${_weekdays[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}';

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final path = _backgroundPath;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontFamily: theme.fontFamily,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
        ),
        child: Focus(
          focusNode: _screenFocus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            // A click anywhere is as good a wake gesture as a keystroke.
            onTap: _showPrompt,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(path),
                // Deepen the scrim once the prompt is up so the form stays
                // legible over a busy wallpaper.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: Color.fromRGBO(0, 0, 0, _promptVisible ? 0.55 : 0.3),
                ),
                // Scrollable so the card can never overflow: the surface is
                // briefly whatever size GTK picked before the compositor's
                // lock-surface configure arrives, and a lock screen must not
                // throw layout errors in that window.
                Center(
                  child: SingleChildScrollView(
                    child: _buildContent(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground(String? path) {
    final Widget background = path == null
        ? const ColoredBox(color: Color(0xFF1A1A1A))
        : MediaBackground(path: path, fit: boxFitFor(widget.config.fit));

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: _promptVisible ? widget.config.blurSigma : 0,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, sigma, child) {
        // A zero-sigma blur still costs a saveLayer, so skip the filter
        // entirely until it would be visible.
        if (sigma < 0.05) return child!;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      },
      child: background,
    );
  }

  Widget _buildContent(ThemeConfig theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _timeText,
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w200,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _dateText,
          style: const TextStyle(fontSize: 20, color: Color(0xCCFFFFFF)),
        ),
        const SizedBox(height: 56),
        if (widget.config.showUsername) ...[
          Text(
            _user.displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _promptVisible
              ? _buildPrompt(theme)
              : _LockButton(
                  key: const ValueKey('unlock'),
                  label: 'Unlock',
                  accent: theme.accent,
                  onTap: _showPrompt,
                ),
        ),
      ],
    );
  }

  Widget _buildPrompt(ThemeConfig theme) {
    return Column(
      key: const ValueKey('prompt'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 280,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _error != null
                    ? const Color(0xFFE06C75)
                    : theme.accent.withValues(alpha: 0.8),
              ),
            ),
            child: EditableText(
              controller: _password,
              focusNode: _fieldFocus,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFFFFFFFF),
              ),
              cursorColor: theme.accentText,
              backgroundCursorColor: const Color(0x44FFFFFF),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              readOnly: _busy,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: _error == null
              ? null
              : Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE06C75),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        _LockButton(
          label: _busy ? 'Checking…' : 'Unlock',
          accent: theme.accent,
          onTap: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class _LockButton extends StatelessWidget {
  const _LockButton({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = accent.withValues(alpha: enabled ? 0.9 : 0.4);
    return HoverRegion(
      enabled: enabled,
      onTap: onTap ?? () {},
      builder: (context, hovered) => AnimatedContainer(
        duration: ShellDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
        decoration: BoxDecoration(
          color: hovered && enabled
              ? Color.lerp(base, const Color(0xFFFFFFFF), 0.18)
              : base,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

