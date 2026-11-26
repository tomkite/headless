#!/bin/bash
# remote/user.sh - the account's part of applying a Mac's config, run as
# LOGIN (not root) by apply.sh: the configured SSH keys, Siri, the Brewfile
# and the user's machine.sh, from the copied config folder
# (~/.headless/config). It changes only what differs and prints one
# "changed:" line per change; running it again changes nothing (but
# machine.sh's own output).
#
# usage: bash user.sh
set -euo pipefail
exec < /dev/null
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }
changed() { echo "headless: changed: $*"; }

[ "$(id -u)" -ne 0 ] || die "run user.sh as the account, not root"
C="$HOME/.headless/config"
S="$C/settings.json"
[ -f "$S" ] || die "no $S; apply.sh copies it first"
get() { plutil -extract "$1" raw "$S" 2> /dev/null; }
flag() { local v; v="$(get "$1")" || v="$2"; [ -n "$v" ] || v="$2"; [ "$v" = true ] || [ "$v" = 1 ]; }
[ "$(get user)" = "$(id -un)" ] || die "settings.json is for '$(get user)', not $(id -un)"

# --- Keys: every configured key may sign in as the account. ---
umask 077
mkdir -p ~/.ssh
ak=~/.ssh/authorized_keys
touch "$ak"
i=0
while k="$(get "sshKeys.$i")"; do
  if ! grep -qxF "$k" "$ak"; then
    printf '%s\n' "$k" >> "$ak"
    changed "added a key to $ak"
  fi
  i=$((i + 1))
done
umask 022

# --- Siri, for this account. ---
if flag extras.siriOff false; then
  if [ "$(defaults read com.apple.assistant.support 'Assistant Enabled' 2> /dev/null || true)" != 0 ]; then
    defaults write com.apple.assistant.support 'Assistant Enabled' -bool false
    defaults write com.apple.Siri StatusMenuVisible -bool false
    defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false
    changed "Siri off"
  fi
fi

# --- Homebrew: install what the Brewfile lists and is missing. ---
BREW=/opt/homebrew/bin/brew
if flag extras.homebrew true; then
  [ -x "$BREW" ] || die "Homebrew is not on this Mac yet; run admin.sh first"
  eval "$("$BREW" shellenv)"
  export HOMEBREW_NO_ENV_HINTS=1
  if [ -f "$C/Brewfile" ]; then
    if ! brew bundle check --no-upgrade --file="$C/Brewfile" > /dev/null 2>&1; then
      say "installing what the Brewfile lists (this can take a while)"
      brew bundle install --no-upgrade --file="$C/Brewfile" || die "brew bundle did not install everything; its output above says what failed"
      changed "Brewfile installed"
    fi
  fi
  if flag tailscale.enable false && ! brew list --formula tailscale > /dev/null 2>&1; then
    brew install tailscale
    changed "Tailscale (open-source) installed"
  fi
fi

# --- Your own additions. ---
if [ -f "$C/machine.sh" ]; then
  say "running machine.sh"
  /bin/bash "$C/machine.sh" || die "machine.sh failed; its output above says where"
fi
say "account settings applied"
