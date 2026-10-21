/// Lucide: one stroke, no fills.
///
/// Font Awesome's solid glyphs map to their outline here — a filled folder is a
/// folder — because filling nothing is the style the user picked; the pairs that
/// carried state by fill alone (a radio dot, a checkbox) stay told apart by
/// shape. Brands are null: Lucide dropped its logos.
library;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';
import 'package:moonswing/icons/pack_glyph.dart';
import 'package:moonswing/icons/shell_glyph.dart';

/// [glyph] in Lucide, or null to fall back.
FontGlyph? lucideGlyph(ShellGlyph glyph) => switch (glyph) {
  // Actions.
  ShellGlyph.close => const FontGlyph(LucideIcons.x),
  ShellGlyph.add => const FontGlyph(LucideIcons.plus),
  ShellGlyph.remove => const FontGlyph(LucideIcons.minus),
  ShellGlyph.check => const FontGlyph(LucideIcons.check),
  ShellGlyph.checkDouble => const FontGlyph(LucideIcons.checkCheck),
  ShellGlyph.search => const FontGlyph(LucideIcons.search),
  ShellGlyph.searchDollar => const FontGlyph(LucideIcons.searchCheck),
  ShellGlyph.edit => const FontGlyph(LucideIcons.pen),
  ShellGlyph.copy => const FontGlyph(LucideIcons.copy),
  ShellGlyph.duplicate => const FontGlyph(LucideIcons.copy),
  ShellGlyph.trash => const FontGlyph(LucideIcons.trash),
  ShellGlyph.trashCan => const FontGlyph(LucideIcons.trash2),
  ShellGlyph.save => const FontGlyph(LucideIcons.save),
  ShellGlyph.refresh => const FontGlyph(LucideIcons.refreshCw),
  ShellGlyph.rotate => const FontGlyph(LucideIcons.rotateCw),
  ShellGlyph.rotateRight => const FontGlyph(LucideIcons.rotateCw),
  ShellGlyph.undo => const FontGlyph(LucideIcons.rotateCcw),
  ShellGlyph.redo => const FontGlyph(LucideIcons.rotateCw),
  ShellGlyph.repeat => const FontGlyph(LucideIcons.repeat),
  ShellGlyph.swap => const FontGlyph(LucideIcons.arrowLeftRight),
  ShellGlyph.externalLink => const FontGlyph(LucideIcons.externalLink),
  ShellGlyph.logOut => const FontGlyph(LucideIcons.logOut),
  ShellGlyph.enter => const FontGlyph(LucideIcons.cornerDownLeft),
  ShellGlyph.backspace => const FontGlyph(LucideIcons.delete),
  ShellGlyph.link => const FontGlyph(LucideIcons.link),
  ShellGlyph.pin => const FontGlyph(LucideIcons.pin),
  ShellGlyph.tag => const FontGlyph(LucideIcons.tag),
  ShellGlyph.ban => const FontGlyph(LucideIcons.ban),
  ShellGlyph.dragHandle => const FontGlyph(LucideIcons.gripVertical),
  ShellGlyph.crop => const FontGlyph(LucideIcons.crop),
  ShellGlyph.compress => const FontGlyph(LucideIcons.shrink),
  ShellGlyph.maximize => const FontGlyph(LucideIcons.appWindow),
  ShellGlyph.upload => const FontGlyph(LucideIcons.cloudUpload),
  ShellGlyph.equals => const FontGlyph(LucideIcons.equal),
  // Arrows and chevrons.
  ShellGlyph.arrowUp => const FontGlyph(LucideIcons.arrowUp),
  ShellGlyph.arrowDown => const FontGlyph(LucideIcons.arrowDown),
  ShellGlyph.arrowLeft => const FontGlyph(LucideIcons.arrowLeft),
  ShellGlyph.arrowRight => const FontGlyph(LucideIcons.arrowRight),
  ShellGlyph.chevronUp => const FontGlyph(LucideIcons.chevronUp),
  ShellGlyph.chevronDown => const FontGlyph(LucideIcons.chevronDown),
  ShellGlyph.chevronLeft => const FontGlyph(LucideIcons.chevronLeft),
  ShellGlyph.chevronRight => const FontGlyph(LucideIcons.chevronRight),
  ShellGlyph.caretUp => const FontGlyph(LucideIcons.chevronUp),
  ShellGlyph.caretDown => const FontGlyph(LucideIcons.chevronDown),
  ShellGlyph.expandLess => const FontGlyph(LucideIcons.chevronUp),
  ShellGlyph.expandMore => const FontGlyph(LucideIcons.chevronDown),
  ShellGlyph.moonRise => const FontGlyph(LucideIcons.arrowUp),
  ShellGlyph.moonSet => const FontGlyph(LucideIcons.arrowDown),
  ShellGlyph.autorenew => const FontGlyph(LucideIcons.refreshCw),
  // Status and feedback.
  ShellGlyph.warning => const FontGlyph(LucideIcons.triangleAlert),
  ShellGlyph.info => const FontGlyph(LucideIcons.info),
  ShellGlyph.help => const FontGlyph(LucideIcons.circleQuestionMark),
  ShellGlyph.question => const FontGlyph(LucideIcons.circleQuestionMark),
  ShellGlyph.circleCheck => const FontGlyph(LucideIcons.circleCheck),
  ShellGlyph.circle => const FontGlyph(LucideIcons.circle),
  ShellGlyph.circleFilled => const FontGlyph(LucideIcons.circle),
  ShellGlyph.circleDot => const FontGlyph(LucideIcons.circleDot),
  ShellGlyph.circleDotFilled => const FontGlyph(LucideIcons.circleDot),
  ShellGlyph.square => const FontGlyph(LucideIcons.square),
  ShellGlyph.squareFilled => const FontGlyph(LucideIcons.square),
  ShellGlyph.squareCheck => const FontGlyph(LucideIcons.squareCheck),
  ShellGlyph.skull => const FontGlyph(LucideIcons.skull),
  ShellGlyph.hand => const FontGlyph(LucideIcons.hand),
  ShellGlyph.smile => const FontGlyph(LucideIcons.smile),
  ShellGlyph.rocket => const FontGlyph(LucideIcons.rocket),
  ShellGlyph.magic => const FontGlyph(LucideIcons.wandSparkles),
  ShellGlyph.bullhorn => const FontGlyph(LucideIcons.megaphone),
  ShellGlyph.universalAccess => const FontGlyph(LucideIcons.accessibility),
  // Notifications and communication.
  ShellGlyph.bell => const FontGlyph(LucideIcons.bell),
  ShellGlyph.bellSlash => const FontGlyph(LucideIcons.bellOff),
  ShellGlyph.inbox => const FontGlyph(LucideIcons.inbox),
  ShellGlyph.comments => const FontGlyph(LucideIcons.messagesSquare),
  ShellGlyph.rss => const FontGlyph(LucideIcons.rss),
  ShellGlyph.newspaper => const FontGlyph(LucideIcons.newspaper),
  // Media.
  ShellGlyph.play => const FontGlyph(LucideIcons.play),
  ShellGlyph.pause => const FontGlyph(LucideIcons.pause),
  ShellGlyph.stop => const FontGlyph(LucideIcons.square),
  ShellGlyph.circlePlay => const FontGlyph(LucideIcons.circlePlay),
  ShellGlyph.skipBack => const FontGlyph(LucideIcons.skipBack),
  ShellGlyph.skipForward => const FontGlyph(LucideIcons.skipForward),
  ShellGlyph.music => const FontGlyph(LucideIcons.music),
  ShellGlyph.headphones => const FontGlyph(LucideIcons.headphones),
  ShellGlyph.film => const FontGlyph(LucideIcons.film),
  ShellGlyph.video => const FontGlyph(LucideIcons.video),
  ShellGlyph.camera => const FontGlyph(LucideIcons.camera),
  ShellGlyph.image => const FontGlyph(LucideIcons.image),
  ShellGlyph.microphone => const FontGlyph(LucideIcons.mic),
  ShellGlyph.microphoneSlash => const FontGlyph(LucideIcons.micOff),
  ShellGlyph.volumeHigh => const FontGlyph(LucideIcons.volume2),
  ShellGlyph.volumeLow => const FontGlyph(LucideIcons.volume1),
  ShellGlyph.volumeOff => const FontGlyph(LucideIcons.volume),
  ShellGlyph.volumeMuted => const FontGlyph(LucideIcons.volumeX),
  // Files.
  ShellGlyph.file => const FontGlyph(LucideIcons.file),
  ShellGlyph.fileText => const FontGlyph(LucideIcons.fileText),
  ShellGlyph.fileAudio => const FontGlyph(LucideIcons.fileAudio),
  ShellGlyph.fileVideo => const FontGlyph(LucideIcons.fileVideo),
  ShellGlyph.fileImage => const FontGlyph(LucideIcons.fileImage),
  ShellGlyph.fileCode => const FontGlyph(LucideIcons.fileCode),
  ShellGlyph.fileArchive => const FontGlyph(LucideIcons.fileArchive),
  ShellGlyph.filePdf => const FontGlyph(LucideIcons.fileText),
  ShellGlyph.folder => const FontGlyph(LucideIcons.folder),
  ShellGlyph.folderFilled => const FontGlyph(LucideIcons.folder),
  ShellGlyph.folderOpen => const FontGlyph(LucideIcons.folderOpen),
  ShellGlyph.clipboard => const FontGlyph(LucideIcons.clipboard),
  ShellGlyph.noteSticky => const FontGlyph(LucideIcons.stickyNote),
  ShellGlyph.eye => const FontGlyph(LucideIcons.eye),
  ShellGlyph.eyeSlash => const FontGlyph(LucideIcons.eyeOff),
  // Time.
  ShellGlyph.calendar => const FontGlyph(LucideIcons.calendar),
  ShellGlyph.calendarDays => const FontGlyph(LucideIcons.calendarDays),
  ShellGlyph.calendarDay => const FontGlyph(LucideIcons.calendar1),
  ShellGlyph.calendarCheck => const FontGlyph(LucideIcons.calendarCheck),
  ShellGlyph.clock => const FontGlyph(LucideIcons.clock),
  ShellGlyph.stopwatch => const FontGlyph(LucideIcons.timer),
  ShellGlyph.hourglass => const FontGlyph(LucideIcons.hourglass),
  ShellGlyph.schedule => const FontGlyph(LucideIcons.clock),
  // System and hardware.
  ShellGlyph.power => const FontGlyph(LucideIcons.power),
  ShellGlyph.lock => const FontGlyph(LucideIcons.lock),
  ShellGlyph.key => const FontGlyph(LucideIcons.keyRound),
  ShellGlyph.keyboard => const FontGlyph(LucideIcons.keyboard),
  ShellGlyph.mouse => const FontGlyph(LucideIcons.mouse),
  ShellGlyph.display => const FontGlyph(LucideIcons.monitor),
  ShellGlyph.microchip => const FontGlyph(LucideIcons.cpu),
  ShellGlyph.memory => const FontGlyph(LucideIcons.memoryStick),
  ShellGlyph.server => const FontGlyph(LucideIcons.server),
  ShellGlyph.gauge => const FontGlyph(LucideIcons.gauge),
  ShellGlyph.terminal => const FontGlyph(LucideIcons.squareTerminal),
  ShellGlyph.plug => const FontGlyph(LucideIcons.plug),
  ShellGlyph.batteryFull => const FontGlyph(LucideIcons.batteryFull),
  ShellGlyph.batteryThreeQuarters => const FontGlyph(LucideIcons.batteryFull),
  ShellGlyph.batteryHalf => const FontGlyph(LucideIcons.batteryMedium),
  ShellGlyph.batteryQuarter => const FontGlyph(LucideIcons.batteryLow),
  ShellGlyph.batteryEmpty => const FontGlyph(LucideIcons.battery),
  ShellGlyph.wifi => const FontGlyph(LucideIcons.wifi),
  ShellGlyph.ethernet => const FontGlyph(LucideIcons.ethernetPort),
  ShellGlyph.bluetooth => const FontGlyph(LucideIcons.bluetooth),
  ShellGlyph.temperatureLow => const FontGlyph(
    LucideIcons.thermometerSnowflake,
  ),
  ShellGlyph.temperatureHalf => const FontGlyph(LucideIcons.thermometer),
  ShellGlyph.temperatureHigh => const FontGlyph(LucideIcons.thermometerSun),
  // Settings and interface.
  ShellGlyph.settings => const FontGlyph(LucideIcons.settings),
  ShellGlyph.sliders => const FontGlyph(LucideIcons.slidersHorizontal),
  ShellGlyph.palette => const FontGlyph(LucideIcons.palette),
  ShellGlyph.puzzle => const FontGlyph(LucideIcons.puzzle),
  ShellGlyph.layers => const FontGlyph(LucideIcons.layers),
  ShellGlyph.shapes => const FontGlyph(LucideIcons.shapes),
  ShellGlyph.grid => const FontGlyph(LucideIcons.grid3x3),
  ShellGlyph.gridLarge => const FontGlyph(LucideIcons.layoutGrid),
  ShellGlyph.borderAll => const FontGlyph(LucideIcons.grid2x2),
  ShellGlyph.columns => const FontGlyph(LucideIcons.columns3),
  ShellGlyph.alignLeft => const FontGlyph(LucideIcons.textAlignStart),
  ShellGlyph.textHeight => const FontGlyph(LucideIcons.aLargeSmall),
  ShellGlyph.language => const FontGlyph(LucideIcons.languages),
  ShellGlyph.listUl => const FontGlyph(LucideIcons.list),
  ShellGlyph.listCheck => const FontGlyph(LucideIcons.listChecks),
  ShellGlyph.chartLine => const FontGlyph(LucideIcons.chartLine),
  ShellGlyph.user => const FontGlyph(LucideIcons.circleUser),
  ShellGlyph.userPlus => const FontGlyph(LucideIcons.userPlus),
  ShellGlyph.userGear => const FontGlyph(LucideIcons.userCog),
  ShellGlyph.sun => const FontGlyph(LucideIcons.sun),
  ShellGlyph.moon => const FontGlyph(LucideIcons.moon),
  ShellGlyph.cloudSun => const FontGlyph(LucideIcons.cloudSun),
  ShellGlyph.location => const FontGlyph(LucideIcons.mapPin),
  // Version control.
  ShellGlyph.pullRequest => const FontGlyph(LucideIcons.gitPullRequest),
  ShellGlyph.merge => const FontGlyph(LucideIcons.gitMerge),
  ShellGlyph.commit => const FontGlyph(LucideIcons.gitCommitHorizontal),
  // Today's Material callers (moon, fortune, weather location).
  ShellGlyph.tides => const FontGlyph(LucideIcons.waves),
  ShellGlyph.nightLight => const FontGlyph(LucideIcons.moonStar),
  ShellGlyph.stargazing => const FontGlyph(LucideIcons.star),
  ShellGlyph.eclipse => const FontGlyph(LucideIcons.moon),
  ShellGlyph.distance => const FontGlyph(LucideIcons.ruler),
  ShellGlyph.placeMarker => const FontGlyph(LucideIcons.mapPin),
  ShellGlyph.myLocation => const FontGlyph(LucideIcons.locateFixed),
  // Brands.
  ShellGlyph.github => null,
  ShellGlyph.linux => null,
  ShellGlyph.googleDrive => null,
};

/// Names one glyph in each of the six weighted Lucide families, so that a
/// release build tree-shakes them to almost nothing.
///
/// The package declares those families beside the regular one the shell draws
/// from, and the icon tree-shaker subsets only a font some `const` `IconData`
/// names: one nobody names ships whole, at half a megabyte each. Material
/// Symbols does the same for its three styles (`Symbols` in that package). The
/// pragma keeps the compiler from dropping a function nothing calls; the locals
/// are `var` for the reason Material Symbols gives — a `const` one is folded
/// away before the shaker sees it.
@pragma('vm:entry-point')
void forceLucideWeightTreeShaking() {
  // ignore: unused_local_variable
  var w100 = LucideIcons100.minus;
  // ignore: unused_local_variable
  var w200 = LucideIcons200.minus;
  // ignore: unused_local_variable
  var w300 = LucideIcons300.minus;
  // ignore: unused_local_variable
  var w400 = LucideIcons400.minus;
  // ignore: unused_local_variable
  var w500 = LucideIcons500.minus;
  // ignore: unused_local_variable
  var w600 = LucideIcons600.minus;
}
