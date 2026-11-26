#!/bin/bash
# apply.sh - copy the config folder to the Mac and apply it there, natively
# (no Nix): first the account's part (remote/user.sh: keys, Siri, the
# Brewfile, machine.sh), then the system part as root (remote/apply.sh:
# key-only SSH, host name, power, Spotlight, automatic sign-in, Tailscale).
# Each prints one "changed:" line per change and none when run again. The
# password comes from the store each time, for sudo -S on the Mac; the Mac
# keeps no passwordless admin rule.
#
# usage: apply.sh DIR
#
# Run admin.sh first.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
shift
[ $# -eq 0 ] || die "unknown option $1"
need_key
# The open-source Tailscale daemon must not run beside the Tailscale app.
if on 'plutil -extract tailscale.enable raw -' < "$CONFIG/settings.json" 2> /dev/null | grep -qx true \
  && on 'test -d /Applications/Tailscale.app'; then
  die "the Tailscale app is on $ADDRESS; leave it as it is and set \"tailscale\": { \"enable\": false } in settings.json"
fi
set -- "$CONFIG"
with_secrets "$@"
read_password

say "copying $CONFIG to $ADDRESS"
copy_remote
tar_c -C "$CONFIG" --exclude .git --exclude known_hosts . \
  | on 'rm -rf ~/.headless/config && mkdir -p -m 0700 ~/.headless/config && tar -xf - -C ~/.headless/config'

say "applying the account's settings on $ADDRESS"
on '/bin/bash ~/.headless/remote/user.sh' || die "the account's part stopped; the lines above say where"
say "applying the system settings on $ADDRESS"
as_root "/bin/bash ~/.headless/remote/apply.sh $LOGIN" || die "the system part stopped; the lines above say where"
unset PASSWORD
say "applied"
