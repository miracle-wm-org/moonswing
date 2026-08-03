/// The themes that ship with the shell.
///
/// They are embedded here rather than installed to a share directory because
/// nothing in the shell resolves paths relative to the bundle — the wallpapers
/// that *are* installed by the Makefile are found only via a hardcoded
/// `$HOME/.local/share`, which breaks under a custom `PREFIX`. Seeding from a
/// constant sidesteps that entirely and works identically in `flutter run`, a
/// `make install`, and the snap.
///
/// `ThemeStore` rewrites any entry whose file differs at start-up and treats
/// membership in [kBuiltInThemes] as the read-only test, so this map is the
/// single source of truth for "shipped" — a fix here reaches an existing
/// install, and a user who wants their own palette duplicates instead.
library;

/// Slug -> the full TOML text of that theme file.
///
/// Every key a theme understands is spelled out in every entry: a shipped
/// theme must never inherit a [ThemeConfig] default, or changing a default
/// would silently restyle it.
const Map<String, String> kBuiltInThemes = {
  'graceful': _graceful,
  'dracula': _dracula,
  'glassy': _glassy,
};

const String _graceful = '''
# Graceful — the shell's own palette: deep maroon over near-black.
name = "Graceful"

font = "Ubuntu Sans"
blur = 24.0

accent               = "#853953"
foreground           = "#F3F4F4"
surface_hover        = "#853953"
surface_pressed      = "#612D53"
workspace_background = "#2C2C2C"
popup_background     = "#2C2C2C"
popup_foreground     = "#F3F4F4"
control_surface      = "#39393D"
slider_track         = "#612D53"
muted                = "#853953"
divider              = "#33F3F4F4"
scrim                = "#882C2C2C"

# The bar: a maroon-to-black fade at 93% opacity, which is what the shell has
# always drawn. panel_background's alpha sets the opacity of every stop.
panel_background     = "#EE2C2C2C"
panel_gradient       = true
''';

const String _dracula = '''
# Dracula — the canonical palette (https://draculatheme.com).
#
# Roles: purple is the accent, current-line (#44475A) carries hovers and card
# surfaces, comment (#6272A4) is both the pressed state and secondary text.
# The bar therefore fades purple -> slate -> near-black.
name = "Dracula"

font = "Ubuntu Sans"
blur = 24.0

accent               = "#BD93F9"
foreground           = "#F8F8F2"
surface_hover        = "#44475A"
surface_pressed      = "#6272A4"
workspace_background = "#282A36"
popup_background     = "#282A36"
popup_foreground     = "#F8F8F2"
control_surface      = "#44475A"
slider_track         = "#6272A4"
muted                = "#6272A4"
divider              = "#33F8F8F2"
scrim                = "#88282A36"

panel_background     = "#EE282A36"
panel_gradient       = true
''';

const String _glassy = '''
# Glassy — translucent surfaces that let the wallpaper through.
#
# The effect comes from alpha, not from blur: a layer-shell surface is
# transparent and the compositor owns everything beneath it, so Flutter cannot
# blur the desktop. Surfaces are white-alpha rather than opaque greys so they
# tint whatever is behind them instead of covering it.
#
# popup_background keeps a high alpha on purpose — a popup has to stay legible
# over a light wallpaper, where a fully translucent card would not.
name = "Glassy"

font = "Ubuntu Sans"
blur = 32.0

accent               = "#7FB6FF"
foreground           = "#F5F7FA"
surface_hover        = "#33FFFFFF"
surface_pressed      = "#4DFFFFFF"
workspace_background = "#33101318"
popup_background     = "#B0141821"
popup_foreground     = "#F5F7FA"
control_surface      = "#26FFFFFF"
slider_track         = "#40FFFFFF"
muted                = "#99EAF0F8"
divider              = "#26FFFFFF"
scrim                = "#66101318"

# No gradient: a sheet of glass, not a coloured fade. A gradient here would
# put the accent against the screen edge at the bar's own opacity, which is
# the one place this theme wants nothing but the wallpaper.
panel_background     = "#40121722"
panel_gradient       = false
''';
