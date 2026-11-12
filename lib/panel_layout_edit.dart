// Editing a bar's module layout from the bar itself: removing a module from its
// right-click menu, adding one to the part of the bar that was right-clicked,
// and dropping one that was dragged to a new place in its section.
//
// The list arithmetic is pure, so it can be tested without a bar; the writes go
// through [ConfigStore], which the running shell follows live — a bar rebuilds
// its sections from `[panels.<name>.layout]` as the store notifies, so nothing
// here asks a panel to do anything.

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/module.dart';

/// The three sections of a bar, by their `[panels.<name>.layout]` key. On a
/// side bar `left` is the top, `center` the middle and `right` the bottom.
const List<String> kPanelSlots = ['left', 'center', 'right'];

/// [slot]'s modules in [layout].
List<String> slotModules(LayoutConfig layout, String slot) => switch (slot) {
  'left' => layout.left,
  'center' => layout.center,
  'right' => layout.right,
  _ => const [],
};

/// How a section is named to a person: by where it is on the screen, so a
/// side bar's `left` reads as its top.
String panelSlotLabel(String slot, {required bool vertical}) => switch (slot) {
  'left' => vertical ? 'Top' : 'Left',
  'center' => vertical ? 'Middle' : 'Center',
  'right' => vertical ? 'Bottom' : 'Right',
  _ => slot,
};

/// Which section a right-click at [along] on a bar [length] long belongs to:
/// the bar is read as thirds, which is where its three sections are aligned.
String panelSlotAt(double along, double length) {
  if (length <= 0) return 'left';
  final third = length / 3;
  if (along < third) return 'left';
  if (along < 2 * third) return 'center';
  return 'right';
}

/// [modules] without the module at [index] — but only if that is still [key].
/// A menu opened on one layout can be answered after another has landed (the
/// settings page was edited underneath it), and a stale index must not take
/// out a different module; the list is then returned unchanged.
List<String> withModuleRemoved(List<String> modules, int index, String key) {
  if (index < 0 || index >= modules.length || modules[index] != key) {
    return modules;
  }
  return [...modules]..removeAt(index);
}

/// [modules] with [key] inserted at [index], clamped to the list.
List<String> withModuleInserted(List<String> modules, int index, String key) =>
    [...modules]..insert(index.clamp(0, modules.length), key);

/// [modules] with the entries at [shown] — the indices a bar actually built,
/// ascending — put into [order], where `order[i]` is the position in [shown]
/// of the module that now goes i-th. Entries not in [shown] (a Miracle-only
/// module dropped on another compositor) keep their places.
List<String> withShownReordered(
  List<String> modules,
  List<int> shown,
  List<int> order,
) {
  assert(shown.length == order.length);
  final out = [...modules];
  for (var i = 0; i < shown.length; i++) {
    out[shown[i]] = modules[shown[order[i]]];
  }
  return out;
}

/// The modules a bar could be given: every registered one not already in
/// [layout], less those that need Miracle when [miracleUnsupported] — the bar
/// would only drop them. In the order they are offered: by [titleOf].
List<String> addableModules(
  LayoutConfig layout, {
  required bool miracleUnsupported,
  required String Function(String key) titleOf,
  Iterable<String>? registered,
}) {
  final present = layout.enabledModules;
  final keys = [
    for (final key in registered ?? Module.registeredKeys)
      if (!present.contains(key) &&
          !(miracleUnsupported &&
              (Module.lookup(key)?.requiresMiracle ?? false)))
        key,
  ];
  keys.sort(
    (a, b) => titleOf(a).toLowerCase().compareTo(titleOf(b).toLowerCase()),
  );
  return keys;
}

/// The layout `[panels.<panel>]` holds in [store], as the bar reads it — the
/// defaults when the panel has no `layout` table.
LayoutConfig storedPanelLayout(ConfigStore store, String panel) =>
    LayoutConfig.fromMap(
      store.get<Map<String, dynamic>>(['panels', panel, 'layout']),
    );

/// Writes [modules] as [panel]'s [slot].
///
/// A panel with no `layout` table is showing the defaults for all three
/// sections, so writing one section alone would empty the other two; the whole
/// table is written then, the other two as they were shown.
void writePanelSlot(
  ConfigStore store,
  String panel,
  String slot,
  List<String> modules,
) {
  final path = ['panels', panel, 'layout'];
  if (store.get<Map<String, dynamic>>(path) != null) {
    store.set([...path, slot], [...modules]);
    return;
  }
  final shown = storedPanelLayout(store, panel);
  store.set(path, <String, dynamic>{
    for (final s in kPanelSlots)
      s: s == slot ? [...modules] : [...slotModules(shown, s)],
  });
}

/// Takes the module at [index] of [panel]'s [slot] out of the bar, if it is
/// still [key] there.
void removePanelModule(
  ConfigStore store, {
  required String panel,
  required String slot,
  required int index,
  required String key,
}) {
  final modules = slotModules(storedPanelLayout(store, panel), slot);
  final edited = withModuleRemoved(modules, index, key);
  if (identical(edited, modules)) return;
  writePanelSlot(store, panel, slot, edited);
}

/// Puts [key] into [panel]'s [slot] at [index], or at its end when null.
void insertPanelModule(
  ConfigStore store, {
  required String panel,
  required String slot,
  required String key,
  int? index,
}) {
  final modules = slotModules(storedPanelLayout(store, panel), slot);
  writePanelSlot(
    store,
    panel,
    slot,
    withModuleInserted(modules, index ?? modules.length, key),
  );
}

/// Writes the order a drag left [panel]'s [slot] in: [shown] and [order] as
/// [withShownReordered] takes them, against the [built] list the bar laid out.
/// Nothing is written if the stored list is no longer [built] — the drag was
/// of a layout that has since been replaced — or if nothing moved.
void reorderPanelSlot(
  ConfigStore store, {
  required String panel,
  required String slot,
  required List<String> built,
  required List<int> shown,
  required List<int> order,
}) {
  final modules = slotModules(storedPanelLayout(store, panel), slot);
  if (!_sameList(modules, built)) return;
  final edited = withShownReordered(modules, shown, order);
  if (_sameList(edited, modules)) return;
  writePanelSlot(store, panel, slot, edited);
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
