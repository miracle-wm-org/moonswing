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
  'forest': _forest,
  'dracula': _dracula,
  'glassy': _glassy,
};

const String _graceful = '''
# Graceful — the shell's own palette: deep maroon over near-black.
name = "Graceful"

font = "Ubuntu Sans"
font_size = 13.0

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

# Flush to the screen edge, square, no rim — the geometry the bar has always
# had. panel_border is spelled out even though nothing draws it at width 0: it
# is the colour a rim would take if one were switched on.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33F3F4F4"
panel_border_width   = 0.0

# Popups: rounded cards with a hairline rim, which is the shape the shell's
# menus have always drawn — now stated once instead of hardcoded at fifteen
# call sites. Unlike the bar a popup rounds all four corners: nothing sits
# behind it to cut a wedge out of. The rim colour is `divider`, which is what
# those menus used.
popup_radius         = 8.0
popup_border         = "#33F3F4F4"
popup_border_width   = 1.0

# A bar popup sits flush against the bar and grows out of it: no gap, and a
# square butt join, so the menu's sides continue the panel's. The join drops its
# rim and its shadow, so nothing draws a seam across it. popup_attach_radius
# above zero would flare the join outward into the bar instead — a concave
# fillet, not a rounded corner — which suits a softer theme than this one.
popup_gap            = 0.0
popup_attach_radius  = 0.0

# The card's lift. Blur is the reach past the edge and the offset pushes it
# downward, exactly as a CSS box-shadow reads; a popup grows its own window by
# that reach so the shadow is not clipped at the surface edge, and is
# repositioned by the same amount so the card stays put. An alpha of 0 here is
# the off switch.
popup_shadow_color   = "#66000000"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0

# How a popup arrives, and — reversed — how it leaves. The card is attached to
# the bar here, so it slides the short distance out of it and back in again.
popup_animation      = "slide"
''';

const String _forest = '''
# Forest — pine and moss over a near-black green, with a lit rim.
#
# The palette is one hue held throughout: every surface is a green so dark it
# reads as black until something is laid beside it, and the only saturated
# green in the theme is the accent. That is what keeps a single-hue theme from
# looking tinted — the colour is spent where it means something (the active
# workspace, a pressed control, the bright end of the bar) and withheld
# everywhere else.
#
# It is a *floating* theme, like glassy, but for the opposite reason: glassy
# needs a rim because a translucent bar has no edge of its own, while this one
# is nearly opaque and wants the rim as the one lit line in the picture. The
# bar and the popups therefore carry the same 1px sage edge and the same 10px
# corner, so a menu reads as a pane dropped out of the pane it came from.
name = "Forest"

font = "Ubuntu Sans"
font_size = 13.0

# Sea green against pale birch. The accent is dark enough that kOnAccent's
# white sits on it at better than 4:1, which is what lets it fill a button
# rather than only outline one.
accent               = "#2E8B57"
foreground           = "#E8F2EA"
surface_hover        = "#1F4433"
surface_pressed      = "#2A6B4C"
workspace_background = "#101A15"
popup_background     = "#F2121C16"
popup_foreground     = "#E8F2EA"
control_surface      = "#1A2A21"
slider_track         = "#2A6B4C"
# Secondary text is a desaturated sage rather than the accent: this theme's
# accent is a fill colour, and reusing it for muted labels would put the one
# saturated green in the palette on the least important text in the shell.
muted                = "#8AA79A"
divider              = "#33E8F2EA"
scrim                = "#88101A15"

# The bar fades sea green -> pine -> forest floor, all at panel_background's
# alpha, so the bright end sits against the screen edge and the fade cannot
# band across the middle.
panel_background     = "#EE0E1712"
panel_gradient       = true

# A 6px gap on every anchored edge, cut by a real gtk-layer-shell margin so
# nothing tiles into it and a click that lands there still reaches the desktop.
# The rim is the point of the theme: a hairline of lit sage around a dark bar.
panel_margin         = 6
panel_radius         = 10.0
panel_border         = "#594FB183"
panel_border_width   = 1.0

# The same material as the bar: same corner, same rim.
popup_radius         = 10.0
popup_border         = "#594FB183"
popup_border_width   = 1.0

# Its popups float too, for glassy's reason rather than graceful's: this bar
# is lifted off the screen by panel_margin, so a menu glued to it would be the
# only thing in the picture touching anything, and matching that margin keeps
# the two gaps equal. It would also cost the rim on the joined edge — the one
# lit line this theme is built around — which an attached popup drops so no
# seam crosses the join. popup_attach_radius is therefore unread here, and
# spelled only because every theme spells every key.
popup_gap            = 6.0
popup_attach_radius  = 0.0

# The lift is tinted with the theme's own darkest green rather than pure black,
# so a card floating over a wallpaper drops a shadow that belongs to the
# palette instead of a grey one.
popup_shadow_color   = "#73060C09"
popup_shadow_blur    = 20.0
popup_shadow_spread  = -1.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 8.0

# A floating card has no join to travel out of, so it grows into place from its
# own centre instead — the softer arrival this theme's rounder corners want.
popup_animation      = "scale"
''';

const String _dracula = '''
# Dracula — the canonical palette (https://draculatheme.com).
#
# Roles: purple is the accent, current-line (#44475A) carries hovers and card
# surfaces, comment (#6272A4) is both the pressed state and secondary text.
# The bar therefore fades purple -> slate -> near-black.
name = "Dracula"

font = "Ubuntu Sans"
font_size = 13.0

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

# Flush and square, like graceful — Dracula is a flat palette, not a floating
# one. The rim colour matches divider so switching it on reads as Dracula.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33F8F8F2"
panel_border_width   = 0.0

# The same card shape as graceful; the rim takes Dracula's own divider.
popup_radius         = 8.0
popup_border         = "#33F8F8F2"
popup_border_width   = 1.0

# Attached to the bar, as graceful is.
popup_gap            = 0.0
popup_attach_radius  = 0.0

# The same lift as graceful, tinted with Dracula's own background rather than
# pure black so it reads as part of the palette.
popup_shadow_color   = "#66191A21"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0

# Attached to the bar, so it slides out of it, as graceful does.
popup_animation      = "slide"
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
font_size = 13.0

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

# A floating pane rather than a strip: an 8px gap on every anchored edge, cut
# by a real gtk-layer-shell margin, so nothing tiles into the gap (the
# compositor folds the margin into the bar's reserved space) and clicks that
# land in it still reach the desktop. The 1px rim is what gives an edge to a
# sheet this translucent — without it the bar has no boundary at all over a
# busy wallpaper.
panel_margin         = 8
panel_radius         = 12.0
panel_border         = "#40FFFFFF"
panel_border_width   = 1.0

# Popups are the bar's material: the same 12px corner and the same rim, so a
# menu reads as a pane dropped out of the pane it came from. The rim is
# panel_border rather than the softer `divider` — a card floating over a busy
# wallpaper needs an edge, not a hairline.
popup_radius         = 12.0
popup_border         = "#40FFFFFF"
popup_border_width   = 1.0

# The one theme whose popups float. Its bar already floats — panel_margin is 8 —
# so a menu glued to that bar would be the only thing on screen touching
# anything; matching the margin keeps the two gaps equal. Attaching would also
# expose the seam a translucent card cannot avoid: popup_background is #B0 and
# panel_background is #40, so at a zero gap the two fills composite separately
# against the wallpaper and the join shows a step in tone — which a flare would
# only make wider. popup_attach_radius is therefore unread here, and spelled
# only because every theme spells every key.
popup_gap            = 8.0
popup_attach_radius  = 0.0

# The theme the shadow matters most to: a translucent card over a busy
# wallpaper has almost no edge of its own, so the lift is deeper and softer than
# the flat themes'. The negative spread pulls the shape back in a little, which
# keeps a wide blur from reading as a halo around the card.
popup_shadow_color   = "#59000000"
popup_shadow_blur    = 28.0
popup_shadow_spread  = -2.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 10.0

# Its bar floats and its popups float with it, so there is no edge to unroll
# out of: the card simply fades up, which is also the arrival that shows least
# of the seam a translucent fill draws over a moving wallpaper.
popup_animation      = "fade"
''';
