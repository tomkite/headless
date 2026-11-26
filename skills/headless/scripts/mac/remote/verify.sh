#!/bin/bash
# remote/verify.sh - compare the Mac with /etc/headless/settings.json, as
# the login, without root. One "ok", "FAIL", "n/a" or "info" line per
# setting.
set -uo pipefail
S=/etc/headless/settings.json
ok() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; }
info() { echo "info  $1"; }
is() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (found '$1', want '$2')"; fi; }
get() { plutil -extract "$1" raw "$S" 2> /dev/null; }
on_() { [ "$(get "$1")" = true ]; }

if [ ! -f "$S" ]; then fail "headless settings applied (no $S; run apply.sh)"; exit 0; fi
ok "macOS $(sw_vers -productVersion), no Nix needed"

user="$(get user)"
is "$(id -un)" "$user" "signed in as the configured user"
host="$(get hostName)"
[ -z "$host" ] || is "$(scutil --get LocalHostName 2> /dev/null)" "$host" "host name"

if on_ keyOnlySsh; then
  grep -qx 'PasswordAuthentication no' /etc/ssh/sshd_config.d/000-headless.conf 2> /dev/null \
    && ok "sshd key-only drop-in" || fail "sshd key-only drop-in"
fi
if sudo -n true 2> /dev/null; then fail "sudo asks for the password (a passwordless rule exists)"; else ok "sudo asks for the password"; fi

fv="$(fdesetup isactive 2> /dev/null || true)"
if on_ autoLogin; then
  is "$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2> /dev/null)" "$user" "automatic sign-in user"
  [ -e /etc/kcpassword ] && ok "automatic sign-in password stored" || fail "automatic sign-in password stored (run admin.sh)"
  [ "$(stat -f '%Su %Lp' /etc/kcpassword 2> /dev/null)" = "root 600" ] && ok "automatic sign-in password root-only" || fail "automatic sign-in password root-only"
  is "$fv" false "FileVault off (needed for automatic sign-in)"
else
  [ ! -e /etc/kcpassword ] && ok "no automatic sign-in password stored" || fail "no automatic sign-in password stored"
  if [ "$fv" = true ]; then
    info "FileVault on: after a restart someone unlocks it at the Mac before key sign-in works"
  else
    info "FileVault off"
  fi
fi

ac() {
  pmset -g custom | awk -v k="$1" '
    /^AC Power:/ { on = 1; next } /^[A-Za-z].*:$/ { on = 0 }
    on && $1 == k { print $2; exit }'
}
cap="$(pmset -g cap)"
has() { printf '%s\n' "$cap" | grep -qw "$1"; }
na() { echo "n/a   $1 (this Mac has no such power setting)"; }
if on_ extras.neverSleepOnPower; then
  is "$(ac sleep)" 0 "never sleeps on the power adapter"
  is "$(ac disksleep)" 0 "disks never sleep on the power adapter"
  pmset -g batt 2> /dev/null | grep -q InternalBattery \
    && info "on battery, and with the lid closed and no display attached, macOS still sleeps"
fi
if on_ extras.wakeOnLan; then
  if has womp; then is "$(ac womp)" 1 "wake for network access on the power adapter"; else na "wake for network access"; fi
fi
if on_ extras.powerNapOff && has powernap; then
  pn="$(pmset -g custom | awk '$1 == "powernap" && $2 != 0 { print $2; exit }')"
  is "${pn:-0}" 0 "Power Nap off"
fi
if on_ extras.startAfterPowerLoss; then
  if has autorestart; then is "$(pmset -g | awk '$1 == "autorestart" { print $2 }')" 1 "starts up after a power cut"; else na "start-up after power loss"; fi
fi
if on_ extras.spotlightOff; then
  mdutil -s / 2> /dev/null | grep -q 'Indexing disabled' && ok "Spotlight indexing off" || fail "Spotlight indexing off"
fi
on_ extras.siriOff && is "$(defaults read com.apple.assistant.support 'Assistant Enabled' 2> /dev/null)" 0 "Siri off"

BREW=/opt/homebrew/bin/brew
if on_ extras.homebrew; then
  if [ -x "$BREW" ]; then
    ok "$("$BREW" --version 2> /dev/null | head -n 1)"
    is "$(stat -f %Su /opt/homebrew)" "$user" "Homebrew owned by $user"
    if [ -f ~/.headless/config/Brewfile ]; then
      HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" bundle check --no-upgrade --file ~/.headless/config/Brewfile > /dev/null 2>&1 \
        && ok "everything in the Brewfile is installed" || fail "everything in the Brewfile is installed (run apply.sh)"
    fi
    if on_ extras.brewAutoUpgrade || [ -z "$(get extras.brewAutoUpgrade)" ]; then
      if launchctl print system/com.headless.brew-upkeep > /dev/null 2>&1; then
        ok "Homebrew upkeep scheduled (every Sunday at 03:00)"
        last="$(grep '^== brew upkeep end' ~/Library/Logs/headless-brew-upkeep.log 2> /dev/null | tail -n 1)"
        if [ -n "$last" ]; then info "Homebrew upkeep last run: ${last#== brew upkeep end }"; else info "Homebrew upkeep last run: not yet"; fi
      else
        fail "Homebrew upkeep scheduled (run apply.sh)"
      fi
    fi
  else
    fail "Homebrew installed (run admin.sh)"
  fi
fi

TS_APP=/Applications/Tailscale.app
if on_ tailscale.app; then
  if [ -d "$TS_APP" ]; then
    ok "Tailscale app installed ($(defaults read "$TS_APP/Contents/Info" CFBundleShortVersionString 2> /dev/null); it updates itself)"
    if pgrep -qf "$TS_APP/Contents/MacOS/Tailscale"; then ok "Tailscale app running"; else fail "Tailscale app running (open it at the Mac, or run apply.sh while signed in)"; fi
    st="$("$TS_APP/Contents/MacOS/Tailscale" status --json 2> /dev/null | plutil -extract BackendState raw - 2> /dev/null)"
    if [ "$st" = Running ]; then
      ok "Tailscale connected as $("$TS_APP/Contents/MacOS/Tailscale" ip -4 2> /dev/null | head -n 1)"
    else
      fail "Tailscale connected (state '${st:-unknown}'; sign in from the app at the Mac)"
    fi
  else
    fail "Tailscale app installed (run apply.sh)"
  fi
elif on_ tailscale.enable; then
  st="$(/opt/homebrew/bin/tailscale status --json 2> /dev/null | plutil -extract BackendState raw - 2> /dev/null)"
  is "$st" Running "Tailscale connected"
elif [ -d "$TS_APP" ]; then
  info "the Tailscale app is installed and left as it is"
fi
exit 0
