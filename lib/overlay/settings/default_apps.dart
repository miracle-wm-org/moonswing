// Settings → Default Apps: which application opens links, folders and every
// other kind of file.
//
// A view over the user's XDG `mimeapps.list` through GIO — see
// `lib/default_apps/default_app_associations.dart` — so a choice made here is
// the one `xdg-open`, every GTK and Qt application and this shell's own desktop
// grid all follow. Two halves: the "Defaults" rows, each standing for a family
// of types (a browser is `https:` links *and* saved web pages), and the full
// list of every type an installed application declares, for anything the rows
// do not cover.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart' show AppIconImage;
import 'package:moonswing/default_apps/default_app_model.dart';
import 'package:moonswing/default_apps/default_apps_store.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// How wide an application picker is, so the rows' dropdowns line up in one
/// column however long each row's label is.
const double kDefaultAppPickerWidth = 240;

/// The app icon beside a picker.
const int _kIconSize = 20;

class DefaultAppsSettingsPage extends StatefulWidget {
  const DefaultAppsSettingsPage({super.key, DefaultAppsStore? store})
    : _store = store;

  /// Injected by widget tests, so nothing here touches the user's real
  /// associations.
  final DefaultAppsStore? _store;

  @override
  State<DefaultAppsSettingsPage> createState() =>
      _DefaultAppsSettingsPageState();
}

class _DefaultAppsSettingsPageState extends State<DefaultAppsSettingsPage> {
  late final DefaultAppsStore _store =
      widget._store ?? DefaultAppsStore.instance;

  /// The full list's filter. A notifier rather than page state, so a keystroke
  /// rebuilds the list and not the "Defaults" rows above it.
  final ValueNotifier<String> _query = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    // Scoped like the keyboard page's lease: leaving the category disposes the
    // page.
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    _query.dispose();
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
          Expanded(child: _body(context, theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeConfig theme) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
    child: Text(
      'Default Apps',
      style: TextStyle(
        fontSize: ShellFontSizes.title,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _body(BuildContext context, ThemeConfig theme) {
    if (_store.status == DefaultAppsStatus.loading) {
      return const Center(child: LoadingIndicator(size: 22));
    }
    final types = _store.types;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              // Always present, so a banner coming and going never shifts the
              // slivers under it — which would re-inflate the filter field and
              // drop the focus of somebody typing into it.
              SliverToBoxAdapter(child: _banner()),
              if (_store.status == DefaultAppsStatus.ready) ...[
                SliverToBoxAdapter(child: _defaultsSection(theme)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(child: _allTypesHeading(types)),
                if (types != null)
                  _AllTypesList(store: _store, types: types, query: _query),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _banner() {
    if (_store.error.isEmpty && _store.errorTitle.isEmpty) {
      return const SizedBox.shrink();
    }
    final failed = _store.status == DefaultAppsStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SettingsBanner(
        title: _store.errorTitle,
        message: _store.error,
        action: failed
            ? SettingsActionButton(
                label: 'Retry',
                compact: true,
                onTap: _store.retry,
              )
            : SettingsIconButton(
                icon: FontAwesomeIcons.xmark,
                tooltip: 'Dismiss',
                onTap: _store.clearError,
              ),
      ),
    );
  }

  Widget _defaultsSection(ThemeConfig theme) {
    final path = _store.userListPath;
    return SettingsSection(
      label: 'Defaults',
      info:
          'Saved to ${path.isEmpty ? 'mimeapps.list' : path}, the list every '
          'desktop following the XDG specification reads: xdg-open, GTK and '
          'Qt applications, and this shell\'s own desktop all open files with '
          'what is chosen here.',
      children: [
        for (final category in _store.categories)
          _categoryRow(category, _store.categoryChoice(category)),
      ],
    );
  }

  Widget _categoryRow(DefaultAppCategory category, DefaultAppChoice? choice) {
    return SettingsRow.field(
      SettingsCatalog.defaultApp(category),
      control: DefaultAppPicker(
        choice: choice,
        onSelected: (app) => _store.setCategoryDefault(category, app),
        onReset: () => _store.resetCategory(category),
      ),
    );
  }

  Widget _allTypesHeading(List<ContentTypeInfo>? types) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeading(
          label: 'All file types',
          info:
              'Every kind of file an installed application says it can open, '
              'each with its own default. Choosing here changes that one type '
              'alone.',
          // Behind a button rather than read on arrival: listing every type
          // enumerates every installed application, and the rows above are
          // what most visits are for.
          trailing: types == null
              ? SettingsActionButton(
                  label: 'Show all file types',
                  compact: true,
                  onTap: _store.showAllTypes,
                )
              : null,
        ),
        if (types != null) ...[
          const SizedBox(height: 8),
          SettingsTextField(
            hint: 'Filter by name or type, e.g. "png" or "text/markdown"',
            onChanged: (value) => _query.value = value,
            leading: Builder(
              builder: (context) => FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                size: 12,
                color: ThemeScope.of(
                  context,
                ).popupForeground.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// The full list, filtered by [query], as a lazy fixed-extent sliver.
///
/// Fixed extent because a desktop declares several hundred types and the rows
/// are uniform; lazy because each row reads its handlers from GIO the first time
/// it is built (see [DefaultAppsStore.typeChoice]), which only rows scrolled to
/// should pay for.
class _AllTypesList extends StatefulWidget {
  const _AllTypesList({
    required this.store,
    required this.types,
    required this.query,
  });

  final DefaultAppsStore store;
  final List<ContentTypeInfo> types;
  final ValueListenable<String> query;

  @override
  State<_AllTypesList> createState() => _AllTypesListState();
}

class _AllTypesListState extends State<_AllTypesList> {
  List<ContentTypeInfo>? _filteredFrom;
  String _filteredFor = '';
  List<ContentTypeInfo> _filtered = const [];

  /// [filterContentTypes], memoised on its two inputs — the page rebuilds on
  /// every store notification, and a write is not a reason to rescan the list.
  List<ContentTypeInfo> _filter(String query) {
    if (!identical(_filteredFrom, widget.types) || _filteredFor != query) {
      _filteredFrom = widget.types;
      _filteredFor = query;
      _filtered = filterContentTypes(widget.types, query);
    }
    return _filtered;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.query,
      builder: (context, query, _) {
        final filtered = _filter(query);
        if (filtered.isEmpty) {
          return SliverToBoxAdapter(
            child: SettingsHint(
              widget.types.isEmpty
                  ? 'No installed application declares any file types.'
                  : 'No file type matches "${query.trim()}".',
            ),
          );
        }
        return SliverFixedExtentList.builder(
          itemExtent: defaultAppTypeRowExtent(
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) =>
              _TypeRow(store: widget.store, info: filtered[index]),
        );
      },
    );
  }
}

/// The height of one row in the full list.
///
/// A fixed extent has to hold the taller of the row's two halves — the two
/// lines of description and type, and the dropdown trigger — at the font size
/// the theme sets, or a larger `font_size` clips every row. Line heights here
/// are the 1.2 of the theme fonts' metrics, rounded up to leave slack rather
/// than to measure exactly.
double defaultAppTypeRowExtent(TextScaler scaler) {
  const lineHeight = 1.25;
  final labels =
      (scaler.scale(ShellFontSizes.body) +
              scaler.scale(ShellFontSizes.caption)) *
          lineHeight +
      2;
  // The trigger: one body line, 8px padding above and below, and its border.
  final trigger = scaler.scale(ShellFontSizes.body) * lineHeight + 18;
  final content = labels > trigger ? labels : trigger;
  // [SettingsListRow]'s padding (6 + 6), its border (1 + 1) and the gap under
  // it (4).
  return (content + 18).ceilToDouble();
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.store, required this.info});

  final DefaultAppsStore store;
  final ContentTypeInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final choice = store.typeChoice(info.type);
    return SettingsListRow(
      trailing: DefaultAppPicker(
        choice: choice,
        onSelected: (app) => store.setTypeDefault(info.type, app),
        onReset: () => store.resetType(info.type),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
          // A type with no description is already named by its type.
          if (info.description != info.type) ...[
            const SizedBox(height: 2),
            Text(
              info.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A reset button, the current application's icon, and a dropdown of the
/// applications that could take its place.
///
/// Shared by both halves of the pane, so a "Defaults" row and a row of the full
/// list are one control. The reset slot is held by a spacer when there is
/// nothing to reset, which keeps every dropdown in one column.
class DefaultAppPicker extends StatelessWidget {
  const DefaultAppPicker({
    super.key,
    required this.choice,
    required this.onSelected,
    required this.onReset,
  });

  /// Null while the store's first read is in flight.
  final DefaultAppChoice? choice;
  final ValueChanged<HandlerApp> onSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final choice = this.choice;
    final current = choice?.current;
    final options = choice?.options ?? const <HandlerApp>[];
    final Widget picker;
    if (choice == null) {
      picker = const SizedBox.shrink();
    } else if (options.isEmpty) {
      picker = Text(
        'No application installed',
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground.withValues(alpha: 0.5),
        ),
      );
    } else {
      picker = SettingsDropdown<String>(
        items: [
          for (final app in options)
            SettingsDropdownItem(value: app.id, label: app.name),
        ],
        selected: current?.id,
        onSelected: (id) {
          if (id == current?.id) return;
          for (final app in options) {
            if (app.id == id) {
              onSelected(app);
              return;
            }
          }
        },
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (choice?.userSet ?? false)
          SettingsIconButton(
            icon: FontAwesomeIcons.arrowRotateLeft,
            tooltip: 'Use the system default',
            onTap: onReset,
          )
        else
          const SizedBox.square(dimension: ShellSizes.iconButton),
        const SizedBox(width: 6),
        SizedBox.square(
          dimension: _kIconSize.toDouble(),
          child: current == null
              ? null
              : AppIconImage(
                  iconName: current.iconName,
                  name: current.name,
                  size: _kIconSize,
                  foreground: theme.popupForeground,
                ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: kDefaultAppPickerWidth,
          child: Align(alignment: Alignment.centerRight, child: picker),
        ),
      ],
    );
  }
}
