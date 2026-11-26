#!/bin/bash
# remote/apply.sh - the system part of applying a Mac's config, run as root
# by apply.sh with sudo -S. It reads the copied config folder
# (~LOGIN/.headless/config/settings.json) and changes only what differs,
# printing one "changed:" line per change; running it again changes
# nothing. The account's own part (keys, Siri, brew bundle, machine.sh) is
# user.sh, which apply.sh runs before this.
#
# usage: sudo -S bash apply.sh LOGIN
set -euo pipefail
exec < /dev/null
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }
warn() { echo "headless: warning: $*" >&2; }
changed() { echo "headless: changed: $*"; }

LOGIN="${1:?usage: apply.sh LOGIN}"
[ "$(id -u)" -eq 0 ] || die "run apply.sh as root"
export HOME=/var/root
[[ "$LOGIN" =~ ^[a-z0-9_][a-z0-9_-]*$ ]] || die "LOGIN is not a plain account name"
home="$(dscl . -read "/Users/$LOGIN" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')"
[ -n "$home" ] || die "$LOGIN is not an account on this Mac"
S="$home/.headless/config/settings.json"
[ -f "$S" ] || die "no $S; apply.sh copies it first"
get() { plutil -extract "$1" raw "$S" 2> /dev/null; }
flag() { local v; v="$(get "$1")" || v="$2"; [ -n "$v" ] || v="$2"; [ "$v" = true ] || [ "$v" = 1 ]; }

[ "$(get user)" = "$LOGIN" ] || die "settings.json is for '$(get user)', not $LOGIN"
host="$(get hostName || true)"
[[ "$host" =~ ^([A-Za-z0-9][A-Za-z0-9-]{0,62})?$ ]] || die "hostName is not a plain name"

# --- SSH: key only. sshd takes the first value it reads, and macOS's own
# drop-in is 100-macos.conf, so this one is named to come first. macOS
# starts sshd for each connection, so the next sign-in uses it. ---
dropin=/etc/ssh/sshd_config.d/000-headless.conf
want="# Written by the headless skill.
ClientAliveInterval 60
ClientAliveCountMax 3"
if flag keyOnlySsh true; then
  [ -s "$home/.ssh/authorized_keys" ] || die "$LOGIN has no SSH key to sign in with; run connect.sh first"
  want="$want
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no"
fi
if [ "$(cat "$dropin" 2> /dev/null || true)" != "$want" ]; then
  old="$(mktemp)"
  had=0
  [ ! -e "$dropin" ] || { cp -p "$dropin" "$old"; had=1; }
  printf '%s\n' "$want" > "$dropin"
  chmod 0644 "$dropin"
  if ! /usr/sbin/sshd -t; then
    if [ "$had" = 1 ]; then cp -p "$old" "$dropin"; else rm -f "$dropin"; fi
    rm -f "$old"
    die "sshd refused the new settings; nothing changed"
  fi
  rm -f "$old"
  changed "SSH settings in $dropin"
fi

# --- Host name: computer, local (Bonjour) and host name. ---
if [ -n "$host" ]; then
  for k in ComputerName LocalHostName HostName; do
    if [ "$(scutil --get "$k" 2> /dev/null || true)" != "$host" ]; then
      scutil --set "$k" "$host"
      changed "$k $host"
    fi
  done
fi

# --- Power. -c is "on power adapter": on battery the Mac keeps macOS's own
# settings and sleeps as usual. Some Macs lack a setting; pmset -g cap
# lists the ones this Mac has. ---
cap="$(pmset -g cap)"
has() { printf '%s\n' "$cap" | grep -qw "$1"; }
# ac KEY: the value of KEY in the power adapter profile.
ac() {
  pmset -g custom | awk -v k="$1" '
    /^AC Power:/ { on = 1; next } /^[A-Za-z].*:$/ { on = 0 }
    on && $1 == k { print $2; exit }'
}
setpm() { # setpm FLAG KEY VALUE WHAT
  local cur
  if [ "$1" = -c ]; then
    cur="$(ac "$2")"
  else
    # -a sets every profile (battery and adapter); any that differs counts.
    cur="$(pmset -g custom | awk -v k="$2" -v w="$3" '$1 == k && $2 != w { print $2; exit }')"
    [ -n "$cur" ] || cur="$3"
  fi
  if [ "$cur" != "$3" ]; then
    pmset "$1" "$2" "$3"
    changed "$4"
  fi
}
if flag extras.neverSleepOnPower true; then
  setpm -c sleep 0 "never sleeps on the power adapter"
  setpm -c disksleep 0 "disks never sleep on the power adapter"
  [ "$(ac displaysleep)" != 0 ] || setpm -c displaysleep 10 "display sleeps after 10 minutes on the power adapter"
fi
if flag extras.wakeOnLan true; then
  if has womp; then setpm -c womp 1 "wake for network access on the power adapter"; else warn "this Mac has no wake for network access setting"; fi
fi
if flag extras.powerNapOff true && has powernap; then
  setpm -a powernap 0 "Power Nap off"
fi
if flag extras.startAfterPowerLoss false; then
  if has autorestart; then setpm -a autorestart 1 "starts up after a power cut"; else warn "this Mac has no start-up after power loss setting"; fi
fi

# --- Spotlight. ---
if flag extras.spotlightOff false && ! mdutil -s / 2> /dev/null | grep -q 'Indexing disabled'; then
  if mdutil -a -i off > /dev/null; then changed "Spotlight indexing off"; else warn "Spotlight indexing could not be turned off"; fi
fi

# --- Homebrew upkeep: a launchd job, run as the account (not root), that
# updates, upgrades and cleans up Homebrew every Sunday at 03:00. launchd
# runs a time missed while the Mac slept at the next wake. ---
upkeep=/Library/LaunchDaemons/com.headless.brew-upkeep.plist
upkeep_label=com.headless.brew-upkeep
if flag extras.homebrew true && flag extras.brewAutoUpgrade true; then
  [ -x /opt/homebrew/bin/brew ] || die "Homebrew is not on this Mac yet; run admin.sh first"
  log="$home/Library/Logs/headless-brew-upkeep.log"
  # shellcheck disable=SC2016 # runs later, in the job's own shell
  job='echo "== brew upkeep start $(date "+%F %T")"; eval "$(/opt/homebrew/bin/brew shellenv)"; rc=0; brew update || rc=$?; brew upgrade || rc=$?; brew cleanup --prune=30 || rc=$?; echo "== brew upkeep end $(date "+%F %T") exit $rc"; exit $rc'
  want_plist="$(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$upkeep_label</string>
  <key>UserName</key><string>$LOGIN</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>-c</string><string>$job</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$home</string>
    <key>HOMEBREW_NO_ENV_HINTS</key><string>1</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST
)"
  if [ "$(cat "$upkeep" 2> /dev/null || true)" != "$want_plist" ]; then
    printf '%s\n' "$want_plist" > "$upkeep.new"
    plutil -lint "$upkeep.new" > /dev/null || { rm -f "$upkeep.new"; die "the Homebrew upkeep job did not make a valid plist"; }
    chown root:wheel "$upkeep.new"
    chmod 0644 "$upkeep.new"
    launchctl bootout "system/$upkeep_label" 2> /dev/null || true
    mv -f "$upkeep.new" "$upkeep"
    changed "Homebrew upkeep every Sunday at 03:00 (log: $log)"
  fi
  launchctl print "system/$upkeep_label" > /dev/null 2>&1 || launchctl bootstrap system "$upkeep" \
    || die "launchd did not load $upkeep"
elif [ -e "$upkeep" ]; then
  launchctl bootout "system/$upkeep_label" 2> /dev/null || true
  rm -f "$upkeep"
  changed "Homebrew upkeep job removed"
fi

# --- Automatic sign-in. admin.sh stores the password; this only removes
# it when automatic sign-in is off. ---
if flag autoLogin false; then
  [ -e /etc/kcpassword ] || warn "automatic sign-in has no stored password; run admin.sh"
  [ "$(fdesetup isactive 2> /dev/null || true)" != true ] || warn "FileVault is on, so automatic sign-in cannot work; run admin.sh"
else
  if [ -e /etc/kcpassword ]; then
    rm -f /etc/kcpassword
    changed "automatic sign-in password removed"
  fi
  if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser > /dev/null 2>&1; then
    defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser
    changed "automatic sign-in off"
  fi
fi

# --- Tailscale: the open-source daemon from Homebrew (user.sh installs the
# formula), run by launchd before anyone signs in. ---
if flag tailscale.enable false; then
  [ ! -d /Applications/Tailscale.app ] || die "the Tailscale app is on this Mac; leave it as it is and set tailscale.enable to false"
  [ -x /opt/homebrew/bin/tailscaled ] || die "tailscaled is not installed; is the homebrew extra on?"
  if ! launchctl print system/com.tailscale.tailscaled > /dev/null 2>&1; then
    /opt/homebrew/bin/tailscaled install-system-daemon
    changed "Tailscale daemon installed"
  fi
fi

# --- What this Mac should be, for verify.sh and restart.sh to read. ---
install -d -m 0755 /etc/headless
if ! cmp -s "$S" /etc/headless/settings.json; then
  install -m 0644 "$S" /etc/headless/settings.json
  changed "/etc/headless/settings.json"
fi
say "system settings applied"
