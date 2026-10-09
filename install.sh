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
# POSIX sh on purpose — this is piped into whatever /bin/sh the machine has.

set -eu

REPO=${MOONSWING_REPO:-miracle-wm-org/moonswing}
TAG=${MOONSWING_TAG:-nightly}
API="https://api.github.com/repos/$REPO/releases/tags/$TAG"

die() {
    echo "moonswing install: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
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

# An install from before the rename is a separate snap, not an older revision
# of this one, so snapd leaves it in place. Say so rather than remove it unasked.
if snap list graceful-shell >/dev/null 2>&1; then
    cat <<'EOF'

The `graceful-shell` snap (this project's former name) is still installed
alongside. It is an old build; remove it with:

    sudo snap remove graceful-shell
EOF
fi

cat <<'EOF'

Installed. Start it with:

    moonswing

Screen sharing and the lock screen work out of the box. To remove:

    sudo snap remove moonswing
EOF
