#!/bin/bash
# remote/admin.sh - the admin session's part on the Mac, run as root by
# admin.sh with sudo -S. Standard input holds the login's password (one
# line) after a --headless-stdin-- line. settings.json sits beside this file.
#
# It installs Apple's Command Line Tools and Homebrew (owned by LOGIN) when
# the homebrew extra is on, and, when automatic sign-in is on, turns
# FileVault off (asking the user only when macOS refuses) and stores the
# sign-in password macOS uses at start-up.
#
# usage: sudo -S bash admin.sh LOGIN
set -euo pipefail
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }

LOGIN="${1:?usage: admin.sh LOGIN}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Homebrew's signed installer package for Apple silicon, pinned by version
# and hash. Homebrew updates itself afterwards.
BREW_PKG_URL=https://github.com/Homebrew/brew/releases/download/7.0.16/Homebrew.pkg
BREW_PKG_SHA256=577808c0d0102681ff2aa196d4b27ce64d6a07e32b44cfbad2a2a490c85a4e37
BREW=/opt/homebrew/bin/brew

[ "$(id -u)" -eq 0 ] || die "run admin.sh as root"
# sudo keeps the login's HOME; root works in its own, so nothing in the
# login's home becomes root's.
export HOME=/var/root
[[ "$LOGIN" =~ ^[a-z0-9_][a-z0-9_-]*$ ]] || die "LOGIN is not a plain account name"
dscl . -read "/Users/$LOGIN" UniqueID > /dev/null 2>&1 || die "$LOGIN is not an account on this Mac"
auto_login="$(plutil -extract autoLogin raw "$HERE/settings.json")"
homebrew="$(plutil -extract extras.homebrew raw "$HERE/settings.json" 2> /dev/null || echo true)"

# Skip to the mark line (the line sudo read, if it needed one, comes first).
PASSWORD=""
while IFS= read -r line && [ "$line" != --headless-stdin-- ]; do :; done
IFS= read -r PASSWORD || true
exec < /dev/null
[ -n "$PASSWORD" ] || die "no password on standard input"

# Automatic sign-in cannot get past FileVault's unlock screen, so with it
# chosen this turns FileVault off with the login's password, and asks the
# user only when macOS refuses. fdesetup reports most refusals with exit 0,
# so its status afterwards is what counts.
fv_status() { fdesetup status 2> /dev/null || true; }
fv_ask() {
  die "ask the user: $1, or set autoLogin to false in settings.json, then run admin.sh again"
}
fv_wait() { # fv_wait TEXT SECONDS: wait while fdesetup status shows TEXT
  local start=$SECONDS
  while fv_status | grep -qF "$1"; do
    [ $((SECONDS - start)) -lt "$2" ] || die "FileVault still shows \"$1\" after $2 seconds; run admin.sh again later"
    sleep 5
  done
}
turn_filevault_off() {
  local esc out
  if fv_status | grep -qF "Encryption in progress"; then
    say "FileVault is still encrypting; waiting for it to finish first (macOS cannot turn it off before then)"
    fv_wait "Encryption in progress" 14400
  fi
  if ! fv_status | grep -qF "Decryption in progress"; then
    fdesetup list 2> /dev/null | cut -d, -f1 | grep -qxF "$LOGIN" \
      || fv_ask "$LOGIN cannot unlock FileVault on this Mac (it has no secure token), so its password cannot turn FileVault off. Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault) with an account that can"
    say "FileVault is on; turning it off with $LOGIN's password, so the Mac can sign in by itself"
    # The plist reaches fdesetup on standard input; printf is a shell
    # builtin, so the password is on no command line.
    esc="${PASSWORD//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
    out="$(printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Username</key><string>%s</string><key>Password</key><string>%s</string></dict></plist>\n' "$LOGIN" "$esc" \
      | fdesetup disable -inputplist 2>&1 || true)"
    esc=""
    case "$out" in
      *"managed preferences"*)
        fv_ask "the organization that manages this Mac does not allow turning FileVault off (macOS said: $out). Ask whoever manages it to allow that" ;;
    esac
    fv_status | grep -qE "Decryption in progress|FileVault is Off" \
      || fv_ask "macOS did not turn FileVault off (it said: ${out:-nothing}). Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault)"
    say "FileVault turned off"
  fi
  # The disk decrypts in the background, and FileVault stays on until it
  # ends; a restart before then stops at its unlock screen.
  say "waiting for FileVault to finish decrypting (a restart before then stops at its unlock screen)"
  local start=$SECONDS
  fv_wait "Decryption in progress" 14400
  [ "$(fdesetup isactive 2> /dev/null || true)" = false ] \
    || fv_ask "FileVault is still on after decrypting ($(fv_status | head -n 1)). Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault)"
  say "FileVault is off (decryption took $((SECONDS - start)) seconds)"
}

# Apple's Command Line Tools give Homebrew git and a compiler. This is how
# Homebrew's own installer gets them without a dialog at the screen.
install_clt() {
  local flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  say "installing Apple's Command Line Tools (several minutes)..."
  touch "$flag"
  label="$(softwareupdate -l 2> /dev/null | grep -B1 -E 'Command Line Tools' | awk -F'*' '/^ *\*/ { print $2 }' \
    | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n 1)"
  [ -n "$label" ] || { rm -f "$flag"; die "Software Update offers no Command Line Tools; install them at the Mac with: xcode-select --install"; }
  softwareupdate -i "$label" > /dev/null || { rm -f "$flag"; die "installing $label failed"; }
  rm -f "$flag"
  xcode-select --switch /Library/Developer/CommandLineTools
}

install_homebrew() {
  local tmp pkg plist=/var/tmp/.homebrew_pkg_user.plist
  say "installing Homebrew for $LOGIN..."
  tmp="$(mktemp -d)"
  pkg="$tmp/Homebrew.pkg"
  curl -fsSL --retry 3 -o "$pkg" "$BREW_PKG_URL"
  echo "$BREW_PKG_SHA256  $pkg" | shasum -a 256 -c - > /dev/null || { rm -rf "$tmp"; die "the Homebrew package's hash does not match"; }
  # The package makes /opt/homebrew belong to the account this file names
  # (root-only, no ACL), not to whoever is at the screen.
  rm -f "$plist"
  defaults write /var/tmp/.homebrew_pkg_user HOMEBREW_PKG_USER "$LOGIN"
  chown root:wheel "$plist"
  chmod 600 "$plist"
  chmod -N "$plist" 2> /dev/null || true
  installer -pkg "$pkg" -target / > /dev/null || { rm -rf "$tmp" "$plist"; die "the Homebrew package did not install"; }
  rm -rf "$tmp" "$plist"
}

if [ "$homebrew" = true ]; then
  xcode-select -p > /dev/null 2>&1 && [ -x "$(xcode-select -p)/usr/bin/git" ] || install_clt
  say "Command Line Tools at $(xcode-select -p)"
  [ -x "$BREW" ] || install_homebrew
  owner="$(stat -f %Su /opt/homebrew)"
  [ "$owner" = "$LOGIN" ] || die "/opt/homebrew belongs to $owner, not $LOGIN; run apply.sh as $owner, or hand it over at the Mac with: sudo chown -R $LOGIN /opt/homebrew"
  say "$(sudo -u "$LOGIN" -H "$BREW" --version | head -n 1), owned by $LOGIN"
fi

if [ "$auto_login" = true ] && [ "$(fdesetup isactive 2> /dev/null || true)" = true ]; then
  turn_filevault_off
fi

if [ "$auto_login" = true ]; then
  # macOS keeps the automatic sign-in password as /etc/kcpassword: the
  # password XORed with Apple's fixed key, root-only. sysadminctl -autologin
  # would take the password on its command line, so this writes it from
  # standard input instead.
  printf '%s' "$PASSWORD" | /usr/bin/perl -e '
    local $/; my $pw = <STDIN>; length $pw or die "empty password\n";
    my @key = (0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F);
    my $n = (int(length($pw) / 12) + 1) * 12;
    my $out = "";
    for my $i (0 .. $n - 1) {
      my $c = $i < length($pw) ? ord(substr($pw, $i, 1)) : 0;
      $out .= chr($c ^ $key[$i % @key]);
    }
    umask 077;
    open(my $fh, ">", "/etc/kcpassword.new") or die "kcpassword: $!\n";
    binmode $fh; print $fh $out; close $fh or die "kcpassword: $!\n";
  '
  chown root:wheel /etc/kcpassword.new
  chmod 0600 /etc/kcpassword.new
  mv -f /etc/kcpassword.new /etc/kcpassword
  defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string "$LOGIN"
  say "automatic sign-in stored for $LOGIN; it takes effect at the next start"
fi
unset PASSWORD
