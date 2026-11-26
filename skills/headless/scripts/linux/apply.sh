#!/bin/bash
# apply.sh - set the Linux machine up from its config folder with the
# distro-neutral script (remote/apply-script.sh): key-only SSH, sleep off,
# automatic updates, automatic sign-in (lingering) and Tailscale, as
# settings.json says. It prints one "changed:" line per change and none
# when run again. The password comes from the store each time, for sudo -S
# on the machine; the machine keeps no passwordless admin rule.
#
# usage: apply.sh DIR
#
# Supported: Debian, Ubuntu and Fedora. NixOS is not supported in this fork.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
shift
[ $# -eq 0 ] || die "unknown option $1"
need_key
settings_env > /dev/null || exit 1
kind="$(os_kind)"
[ "$kind" != nixos ] || die "$ADDRESS runs NixOS, which this fork of the skill does not set up; use Debian, Ubuntu or Fedora"
set -- "$CONFIG"
with_secrets "$@"
read_password
copy_remote
put_settings
say "applying the distro-neutral script on $ADDRESS ($kind)"
as_root "/usr/bin/env bash ~/.headless/remote/apply-script.sh $LOGIN" || die "the script stopped; the lines above say where"
unset PASSWORD
say "applied"
