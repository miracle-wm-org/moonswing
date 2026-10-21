/// Every interface icon the shell draws, named by what it means rather than by
/// the font that draws it.
///
/// A call site names a member (`ShellIcon(ShellGlyph.close, size: 12)`) and the
/// theme's `icon_pack` decides what that looks like; the tables are
/// `lib/icons/packs/`, one exhaustive `switch` each, so a member added here does
/// not compile until every pack has answered it.
///
/// One member per glyph the shell drew before packs existed, deliberately: the
/// Font Awesome table is then a rename, and the default look cannot move. Where
/// two members look alike (`trash` and `trashCan`, `rotate` and `refresh`) that
/// is because two call sites chose two Font Awesome glyphs, and folding them is
/// a decision about those call sites, not about this table.
///
/// Pure Dart, so `test/icon_pack_test.dart` walks it without a font.
library;

enum ShellGlyph {
  // Things a button does.
  close,
  add,
  remove,
  check,
  checkDouble,
  search,
  searchDollar,
  edit,
  copy,
  duplicate,
  trash,
  trashCan,
  save,
  refresh,
  rotate,
  rotateRight,
  undo,
  redo,
  repeat,
  swap,
  externalLink,
  logOut,
  enter,
  backspace,
  link,
  pin,
  tag,
  ban,
  dragHandle,
  crop,
  compress,
  maximize,
  upload,
  equals,

  // Directions, and the disclosure chevrons.
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  chevronUp,
  chevronDown,
  chevronLeft,
  chevronRight,
  caretUp,
  caretDown,
  expandLess,
  expandMore,
  moonRise,
  moonSet,
  autorenew,

  // States, results and warnings.
  warning,
  info,
  help,
  question,
  circleCheck,
  circle,
  circleFilled,
  circleDot,
  circleDotFilled,
  square,
  squareFilled,
  squareCheck,
  skull,
  hand,
  smile,
  rocket,
  magic,
  bullhorn,
  universalAccess,

  // Notifications, feeds and messages.
  bell,
  bellSlash,
  inbox,
  comments,
  rss,
  newspaper,

  // Playback, capture and sound.
  play,
  pause,
  stop,
  circlePlay,
  skipBack,
  skipForward,
  music,
  headphones,
  film,
  video,
  camera,
  image,
  microphone,
  microphoneSlash,
  volumeHigh,
  volumeLow,
  volumeOff,
  volumeMuted,

  // Files, folders and what is in them.
  file,
  fileText,
  fileAudio,
  fileVideo,
  fileImage,
  fileCode,
  fileArchive,
  filePdf,
  folder,
  folderFilled,
  folderOpen,
  clipboard,
  noteSticky,
  eye,
  eyeSlash,

  // Calendars, clocks and timers.
  calendar,
  calendarDays,
  calendarDay,
  calendarCheck,
  clock,
  stopwatch,
  hourglass,
  schedule,

  // The machine: power, input, displays, sensors and networks.
  power,
  lock,
  key,
  keyboard,
  mouse,
  display,
  microchip,
  memory,
  server,
  gauge,
  terminal,
  plug,
  batteryFull,
  batteryThreeQuarters,
  batteryHalf,
  batteryQuarter,
  batteryEmpty,
  wifi,
  ethernet,
  bluetooth,
  temperatureLow,
  temperatureHalf,
  temperatureHigh,

  // Settings, layout and the shell's own chrome.
  settings,
  sliders,
  palette,
  puzzle,
  layers,
  shapes,
  grid,
  gridLarge,
  borderAll,
  columns,
  alignLeft,
  textHeight,
  language,
  listUl,
  listCheck,
  chartLine,
  user,
  userPlus,
  userGear,
  sun,
  moon,
  cloudSun,
  location,

  // GitHub's subjects.
  pullRequest,
  merge,
  commit,

  // The moon, fortune and weather cards' glyphs, which were Material Symbols
  // before there was a choice — and so still are under Font Awesome.
  tides,
  nightLight,
  stargazing,
  eclipse,
  distance,
  placeMarker,
  myLocation,

  // Logos. Packs that have none fall back to Font Awesome's.
  github,
  linux,
  googleDrive;

  /// Whether this is a logo rather than a symbol. A pack may draw a brand its
  /// own way (Remix has a GitHub mark); most have none and fall back.
  bool get isBrand => switch (this) {
    ShellGlyph.github || ShellGlyph.linux || ShellGlyph.googleDrive => true,
    _ => false,
  };
}
