#!/bin/sh
#
# Install the latest Graceful Shell nightly snap.
#
#   curl -fsSL https://raw.githubusercontent.com/miracle-wm-org/graceful-shell/main/install.sh | sh
#
# Downloads the newest `graceful-shell_*.snap` asset from the rolling `nightly`
# release and installs it with `--classic --dangerous`. Re-running it is how you
# update: snapd replaces the installed revision in place.
#
# POSIX sh on purpose — this is piped into whatever /bin/sh the machine has.

set -eu

REPO=${GRACEFUL_REPO:-miracle-wm-org/graceful-shell}
TAG=${GRACEFUL_TAG:-nightly}
API="https://api.github.com/repos/$REPO/releases/tags/$TAG"

die() {
    echo "graceful-shell install: $*" >&2
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

if [ -n "$TOKEN" ]; then
    # browser_download_url is unauthenticated and 404s on a private repo; the
    # asset's API url serves the bytes with Accept: application/octet-stream.
    url=$(printf '%s' "$release" \
        | grep -o 'https://api\.github\.com/repos/[^"]*/releases/assets/[0-9]*' \
        | head -n 1)
    set -- -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream"
    snapname=$(printf '%s' "$release" \
        | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*\.snap"' \
        | head -n 1 \
        | cut -d '"' -f 4)
else
    url=$(printf '%s' "$release" \
        | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.snap"' \
        | head -n 1 \
        | cut -d '"' -f 4)
    snapname=${url##*/}
fi
[ -n "$url" ] || die "the $TAG release has no .snap asset."
[ -n "$snapname" ] || snapname="graceful-shell.snap"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/graceful-shell.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "==> Downloading $snapname"
curl -fL --progress-bar "$@" -o "$tmp/$snapname" "$url" || die "download failed."

# --classic: the shell needs unconfined access to the Wayland compositor.
# --dangerous: the file is downloaded, not store-signed.
echo "==> Installing $snapname"
$SUDO snap install "$tmp/$snapname" --classic --dangerous || die "snap install failed."

cat <<'EOF'

Installed. Start it with:

    graceful-shell

Screen sharing and the lock screen work out of the box. To remove:

    sudo snap remove graceful-shell
EOF
