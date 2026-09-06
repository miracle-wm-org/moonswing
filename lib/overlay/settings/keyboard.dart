// Settings → Keyboard: the ordered input sources, and what locale1 is applying.
//
// The one page in this shell that edits the *machine* rather than the shell,
// which is why the footer says so: `SetX11Keyboard` writes
// `/etc/default/keyboard` for every account and the console, and its polkit
// action is `auth_admin_keep` on any box without Ubuntu's gnome-control-center
// rule.

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/keyboard/keyboard_store.dart';
import 'package:graceful_shell/keyboard/locale1_client.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/keyboard/input_source_picker.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_config.dart';
import 'package:graceful_shell/theme/tokens.dart';

class KeyboardSettingsPage extends StatefulWidget {
  const KeyboardSettingsPage({super.key, KeyboardStore? store})
    : _store = store;

  /// Injected by widget tests, so nothing here touches the system bus.
  final KeyboardStore? _store;

  @override
  State<KeyboardSettingsPage> createState() => _KeyboardSettingsPageState();
}

class _KeyboardSettingsPageState extends State<KeyboardSettingsPage> {
  late final KeyboardStore _store = widget._store ?? KeyboardStore.instance;

  @override
  void initState() {
    super.initState();
    // Naturally scoped: `_buildCategoryContent` is a switch returning a
    // different widget per sidebar category, so leaving the page disposes it.
    // No `active` flag is needed, unlike the `IndexedStack`-hosted System and
    // Calendar tabs.
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme),
          Container(height: 1, color: theme.divider),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeConfig theme) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
    child: Text(
      'Keyboard',
      style: TextStyle(
        fontSize: ShellFontSizes.title,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _body(ThemeConfig theme) {
    // Only the very first read shows a loader. A *failed* read still renders
    // the page: the source list is graceful's own config and stays editable
    // whatever locale1 is doing.
    if (_store.status == KeyboardStatus.loading && _store.systemState == null) {
      return const Center(child: LoadingIndicator(size: 22));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_store.error.isNotEmpty) ...[
            _banner(theme),
            const SizedBox(height: 16),
          ],
          _sourcesSection(theme),
          const SizedBox(height: 20),
          _activeSection(theme),
          const SizedBox(height: 20),
          const SettingsHint(
            'Changing the layout applies to the whole system — it is written to '
            '/etc/default/keyboard for every account and the console — and needs '
            'administrator approval through the polkit action '
            'org.freedesktop.locale1.set-keyboard.',
          ),
        ],
      ),
    );
  }

  Widget _banner(ThemeConfig theme) {
    final busy = _store.pending != null;
    final unavailable = _store.errorKind == Locale1FailureKind.unavailable;
    return SettingsBanner(
      title: unavailable
          ? 'Keyboard layout service unavailable'
          : 'Could not change the layout',
      message: unavailable
          ? _store.error
          : '${_store.error} This uses the polkit action '
                'org.freedesktop.locale1.set-keyboard, which is auth_admin_keep '
                'by default: an authentication agent has to be running in this '
                'session, and the account has to be able to authenticate as an '
                'administrator.',
      action: SettingsActionButton(
        label: 'Retry',
        compact: true,
        loading: busy,
        enabled: !busy,
        onTap: () => _store.retry(),
      ),
    );
  }

  Widget _sourcesSection(ThemeConfig theme) {
    final busy = _store.pending != null;
    final activeIndex = _store.activeIndex;
    return SettingsSection(
      label: 'Input Sources',
      // The adder goes on the heading row, not under the list: an adder below
      // a collection walks down the pane every time it is used.
      trailing: InputSourcePicker(
        catalog: _store.catalog,
        existing: _store.sources,
        onSelected: _store.addSource,
      ),
      children: [
        if (_store.sources.isEmpty)
          const SettingsHint(
            'No input sources yet. Add one to switch between layouts.',
          )
        else
          for (var i = 0; i < _store.sources.length; i++)
            _sourceRow(theme, i, activeIndex, busy),
      ],
    );
  }

  Widget _sourceRow(ThemeConfig theme, int i, int activeIndex, bool busy) {
    final source = _store.sources[i];
    final code = i < _store.shortCodes.length ? _store.shortCodes[i] : '';
    final active = i == activeIndex;
    return SettingsListRow(
      trailing: active
          ? const SettingsBadge('Active')
          : SettingsActionButton(
              label: 'Use',
              compact: true,
              loading: _store.pending == source,
              enabled: !busy,
              onTap: () => _store.activate(source),
            ),
      onMoveUp: () => _store.moveBy(i, -1),
      onMoveDown: () => _store.moveBy(i, 1),
      onRemove: () => _store.removeAt(i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _store.describe(source),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            code.isEmpty ? source.id : '$code · ${source.id}',
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeSection(ThemeConfig theme) {
    final state = _store.systemState;
    final unlisted = _store.unlistedActive;
    String value(String raw) => raw.isEmpty ? '—' : raw;
    return SettingsSection(
      label: 'Active layout',
      children: [
        SettingsRow(
          label: 'Layout',
          control: _readOnly(theme, state == null ? 'Unknown' : value(state.layout)),
        ),
        SettingsRow(
          label: 'Variant',
          control: _readOnly(theme, state == null ? 'Unknown' : value(state.variant)),
        ),
        SettingsRow(
          label: 'Model',
          control: _readOnly(theme, state == null ? 'Unknown' : value(state.model)),
        ),
        SettingsRow(
          label: 'Options',
          control: _readOnly(theme, state == null ? 'Unknown' : value(state.options)),
        ),
        if (unlisted != null) ...[
          const SizedBox(height: 8),
          // The machine is in a layout the user has not listed — somebody ran
          // `localectl`, or it shipped this way. Offered rather than
          // silently corrected: re-applying source #1 would change the
          // machine's keyboard because the user opened a settings page.
          SettingsRow(
            label: 'Not in your list',
            control: SettingsActionButton(
              label: 'Add to input sources',
              compact: true,
              onTap: () => _store.addSource(unlisted),
            ),
          ),
          SettingsHint('${_store.describe(unlisted)} (${unlisted.id})'),
        ],
      ],
    );
  }

  Widget _readOnly(ThemeConfig theme, String text) => Align(
    alignment: Alignment.centerRight,
    child: Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.secondary,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.75),
      ),
    ),
  );
}
