#!/bin/sh
#
# Install the latest Moonswing nightly snap.
#
#   curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh
#
# Downloads the `moonswing_*.snap` asset from the rolling `nightly`
# release and installs it with `--classic --dangerous`. Re-running it is how you
# update: snapd replaces the installed revision in place.
#
# Options (after `sh -s --` when piped):
#
#   --miracle-autostart   also add moonswing to miracle-wm's `startup_apps`,
#                         restarted on death and run in a systemd scope.
#                         Same as MOONSWING_MIRACLE_AUTOSTART=1.
#
# POSIX sh on purpose — this is piped into whatever /bin/sh the machine has.

set -eu

REPO=${MOONSWING_REPO:-miracle-wm-org/moonswing}
TAG=${MOONSWING_TAG:-nightly}
API="https://api.github.com/repos/$REPO/releases/tags/$TAG"

die() {
    echo "moonswing install: $*" >&2
    exit 1
}

warn() {
    echo "moonswing install: $*" >&2
}

usage() {
    cat <<'EOF'
Usage: install.sh [--miracle-autostart]

  --miracle-autostart  Start moonswing with miracle-wm: add it to the
                       startup_apps of ~/.config/miracle-wm/config.yaml,
                       creating the file if there is none. Left untouched
                       if moonswing is already listed there.

Piped from curl, pass options after `sh -s --`:

  curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/moonswing/main/install.sh | sh -s -- --miracle-autostart
EOF
}

MIRACLE_AUTOSTART=${MOONSWING_MIRACLE_AUTOSTART:-0}
AUTOSTART_ADDED=0
for arg in "$@"; do
    case $arg in
        --miracle-autostart) MIRACLE_AUTOSTART=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option '$arg'." ;;
    esac
done

need() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

# The entry --miracle-autostart adds. The absolute path because miracle-wm
# execs the command itself, on the compositor's PATH, which need not carry
# /snap/bin; a command that is not found (exit 127) is never restarted.
AUTOSTART_COMMAND=/snap/bin/moonswing

# Print the startup_apps entry, each line prefixed with the indent in $1.
autostart_entry() {
    printf '%s- command: %s\n' "$1" "$AUTOSTART_COMMAND"
    printf '%s  restart_on_death: true\n' "$1"
    printf '%s  in_systemd_scope: true\n' "$1"
}

# Add moonswing to miracle-wm's startup_apps. Never fatal: by the time it runs
# the snap is installed, and a config we could not edit should not read as a
# failed install — it says why and prints the entry to add by hand.
add_miracle_autostart() {
    config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
    cfg=$config_dir/miracle-wm/config.yaml
    # miracle-wm reads the legacy path only while the new one does not exist.
    if [ ! -e "$cfg" ] && [ -e "$config_dir/miracle-wm.yaml" ]; then
        cfg=$config_dir/miracle-wm.yaml
    fi

    if [ ! -e "$cfg" ]; then
        # miracle-wm seeds a missing config on its first start, so creating it
        # here only means that seed is skipped: every key left out keeps its
        # built-in default.
        echo "==> Creating $cfg with moonswing as a startup app"
        if mkdir -p "${cfg%/*}" && { echo "startup_apps:"; autostart_entry "  "; } > "$cfg"; then
            AUTOSTART_ADDED=1
            return 0
        fi
        autostart_by_hand "could not write $cfg."
        return 0
    fi

    # Any uncommented `command:` naming moonswing — this entry, a PATH lookup,
    # or a build of the user's own — means it is already started. Leave the
    # file exactly as it is.
    if grep -Eq '^[^#]*command:[[:space:]]*["'\'']?([^[:space:]"'\'']*/)?moonswing([[:space:]"'\'',}]|$)' "$cfg"; then
        echo "==> moonswing is already a startup app in $cfg; leaving it unchanged"
        AUTOSTART_ADDED=1
        return 0
    fi

    echo "==> Adding moonswing to the startup apps in $cfg"
    # One pass: no top-level startup_apps key appends one at the end; an empty
    # or null one gets the entry as its only item; a block list gets it as its
    # first item, at the indent its existing items use. A non-empty flow list
    # ([...]) is not rewritten — exit 3 — rather than risk mangling it.
    entry=$(autostart_entry "@@")
    if ! awk -v entry="$entry" '
        function emit(indent,    e) {
            e = entry
            gsub(/@@/, indent, e)
            print e
        }
        function flush(    i) {
            for (i = 1; i <= held; i++) print hold[i]
            held = 0
        }
        state == 1 {
            # Inside startup_apps, before its first line of content.
            if ($0 ~ /^[[:space:]]*(#.*)?$/) { hold[++held] = $0; next }
            if (match($0, /^[ ]*-([[:space:]]|$)/)) {
                indent = $0
                sub(/-.*/, "", indent)
            } else if ($0 ~ /^[^[:space:]]/) {
                indent = "  "   # the key was null: the next line is another key
            } else {
                exit 3
            }
            emit(indent); flush(); state = 2
            print; next
        }
        state == 0 && /^startup_apps[[:space:]]*:/ {
            value = $0
            sub(/^startup_apps[[:space:]]*:[[:space:]]*/, "", value)
            sub(/[[:space:]]*(#.*)?$/, "", value)
            if (value == "" || value == "~" || value == "null") {
                print "startup_apps:"; state = 1; next
            }
            if (value ~ /^\[[[:space:]]*\]$/) {
                print "startup_apps:"; emit("  "); state = 2; next
            }
            exit 3
        }
        { print }
        END {
            if (state == 1) { emit("  "); flush() }
            if (state == 0) { print "startup_apps:"; emit("  ") }
        }
    ' "$cfg" > "$tmp/config.yaml"; then
        autostart_by_hand "could not safely rewrite startup_apps in $cfg (an inline [...] list?)."
        return 0
    fi

    backup="$cfg.$(date +%Y%m%d%H%M%S).bak"
    # Copy the result over the file rather than moving it into place, so a
    # config that is a symlink into a dotfiles repository stays one.
    if cp -p "$cfg" "$backup" && cat "$tmp/config.yaml" > "$cfg"; then
        echo "    (the previous config is saved as $backup)"
        AUTOSTART_ADDED=1
    else
        autostart_by_hand "could not update $cfg."
    fi
}

autostart_by_hand() {
    warn "$1"
    cat >&2 <<'EOF'
Add moonswing to miracle-wm's startup_apps yourself:

startup_apps:
EOF
    autostart_entry "  " >&2
}

# The snap is built for amd64 only.
arch=$(uname -m)
[ "$arch" = "x86_64" ] || die "no nightly snap for $arch (amd64 only); build from source instead."

need curl
need snap

# `snap install` needs root. Piping into `sh` gives no tty for an interactive
# password prompt to be obvious about, so ask for the sudo ticket up front.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=
else
    need sudo
    SUDO=sudo
    echo "==> Escalating with sudo (snap install requires root)"
    sudo -v || die "sudo authentication failed."
fi

# While the repository is private the anonymous API answers 404, so honour a
# token if one is exported. GH_TOKEN/GITHUB_TOKEN are what `gh` already sets.
TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}
if [ -n "$TOKEN" ]; then
    set -- -H "Authorization: Bearer $TOKEN"
else
    set --
fi

# Fetch first, parse second: in a pipeline the exit status is the *last*
# command's, so a curl failure folded into the parse would read as "no asset".
echo "==> Looking up the $TAG release of $REPO"
release=$(curl -fsSL "$@" "$API") \
    || die "could not reach $API (private repo? export GH_TOKEN and retry)."

# Match the asset by name, never "the first .snap": the release is rolling and
# outlives renames — it carried a graceful-shell_*.snap from before the project
# was called moonswing, and taking the first asset installed that instead.
asset_re='moonswing_[^"/]*[.]snap'
if [ -n "$TOKEN" ]; then
    # browser_download_url is unauthenticated and 404s on a private repo; the
    # asset's API url serves the bytes with Accept: application/octet-stream.
    # Within an asset object "url" comes before "name", so remember the last
    # asset url seen and print it once the name matches.
    url=$(printf '%s' "$release" | tr ',' '\n' | awk -v re="\"$asset_re\"" '
        /"url"[[:space:]]*:[[:space:]]*"https:\/\/api\.github\.com\/repos\/[^"]*\/releases\/assets\/[0-9]+"/ {
            match($0, /https:[^"]*/); last = substr($0, RSTART, RLENGTH)
        }
        /"name"[[:space:]]*:/ && $0 ~ re { print last; exit }')
    set -- -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream"
    snapname=$(printf '%s' "$release" | grep -o "\"$asset_re\"" | head -n 1 | tr -d '"')
else
    url=$(printf '%s' "$release" \
        | grep -o "\"browser_download_url\"[[:space:]]*:[[:space:]]*\"[^\"]*/$asset_re\"" \
        | head -n 1 \
        | cut -d '"' -f 4)
    snapname=${url##*/}
fi
[ -n "$url" ] || die "the $TAG release has no moonswing_*.snap asset."
[ -n "$snapname" ] || snapname="moonswing.snap"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/moonswing.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "==> Downloading $snapname"
curl -fL --progress-bar "$@" -o "$tmp/$snapname" "$url" || die "download failed."

# --classic: the shell needs unconfined access to the Wayland compositor.
# --dangerous: the file is downloaded, not store-signed.
echo "==> Installing $snapname"
$SUDO snap install "$tmp/$snapname" --classic --dangerous || die "snap install failed."

if [ "$MIRACLE_AUTOSTART" = 1 ]; then
    add_miracle_autostart
fi

# An install from before the rename is a separate snap, not an older revision
# of this one, so snapd leaves it in place. Say so rather than remove it unasked.
if snap list graceful-shell >/dev/null 2>&1; then
    cat <<'EOF'

The `graceful-shell` snap (this project's former name) is still installed
alongside. It is an old build; remove it with:

    sudo snap remove graceful-shell
EOF
fi

if [ "$AUTOSTART_ADDED" = 1 ]; then
    cat <<'EOF'

Installed. miracle-wm starts it from your next login; for this session run:
EOF
else
    cat <<'EOF'

Installed. Start it with:
EOF
fi

cat <<'EOF'

    moonswing

Screen sharing and the lock screen work out of the box. To remove:

    sudo snap remove moonswing
EOF
