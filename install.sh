#!/bin/bash
# BlarneyKey installer. One line:
#
#   curl -fsSL https://raw.githubusercontent.com/AirDoogle/blarneykey/main/install.sh | bash
#
# Fetches the source, downloads the speech model, builds the app and installs it.
#
# It builds on your machine rather than downloading a prebuilt binary, which means macOS
# never treats it as untrusted software from the internet — there is no Gatekeeper warning
# to click through, and nothing here disables any security check. The trade is that you
# need the Xcode command line tools; the script checks for them.
set -euo pipefail

REPO_URL="https://github.com/AirDoogle/blarneykey.git"
SRC="${BLARNEYKEY_SRC:-$HOME/Developer/blarneykey}"
APP="/Applications/BlarneyKey.app"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m!! %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- checks

step "Checking this Mac"

[ "$(uname -s)" = "Darwin" ] || die "BlarneyKey is macOS only."
[ "$(uname -m)" = "arm64" ] \
  || die "BlarneyKey needs an Apple Silicon Mac — the speech model runs on the Neural Engine."

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 15 ] \
  || die "BlarneyKey needs macOS 15 or later. You are on $(sw_vers -productVersion)."

command -v brew >/dev/null 2>&1 \
  || die "Homebrew is required. Install it from https://brew.sh and run this again."

if ! xcode-select -p >/dev/null 2>&1; then
  die "The Xcode command line tools are required to build BlarneyKey.
   Run this, let it finish, then run this installer again:

     xcode-select --install"
fi

command -v swift >/dev/null 2>&1 || die "swift not found, though the command line tools are installed."
echo "    macOS $(sw_vers -productVersion), Apple Silicon, Swift $(swift --version 2>/dev/null | head -1 | sed 's/.*version //;s/ .*//')"

# ---------------------------------------------------------------- source

step "Fetching the source"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" pull --ff-only
  echo "    updated $SRC"
elif [ -d "$SRC" ] && [ -n "$(ls -A "$SRC" 2>/dev/null)" ]; then
  # Something is already there that is not a checkout. Do not clobber it.
  die "$SRC exists and is not a BlarneyKey checkout.
   Move it, or choose somewhere else:

     BLARNEYKEY_SRC=~/somewhere-else bash install.sh"
else
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 "$REPO_URL" "$SRC"
  echo "    cloned to $SRC"
fi

# ---------------------------------------------------------------- engine, model, build

step "Installing the speech engine and model"
# setup.sh installs whisperkit-cli, downloads the model from Hugging Face, assembles it,
# tests the engine, then builds and installs the app.
bash "$SRC/setup.sh"

# ---------------------------------------------------------------- finish

[ -d "$APP" ] || die "The build finished but $APP is missing."

step "Opening BlarneyKey"
open "$APP"

cat <<'DONE'

    BlarneyKey is installed and running in your menu bar.

    One thing left, and only you can do it:

      System Settings -> Privacy & Security -> Accessibility
      Add BlarneyKey and turn it on.

    Without that, BlarneyKey can hear you but cannot type into other apps.
    It shows a banner until the permission is granted, with a button that
    opens the right pane for you.

    Then hold Right Command, say something, and let go.

DONE
