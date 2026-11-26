#!/bin/bash
# connect.sh - the first sign-in to a Linux machine: pin its host key in the
# config folder, sign in once with the password from the store, add your
# public key to the admin account, and check that key sign-in works. A
# machine that runs NixOS is refused: this fork does not set it up.
#
# usage: connect.sh DIR
#
# It is safe to run again: a pinned host key must still match, and a key
# that already works needs no password at all.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
FIRST_SIGN_IN_ARGS=("$@")
first_sign_in "is the SSH server on and reachable?"

facts="$(on '. /etc/os-release; printf "%s|%s|%s|%s\n" "$(uname -s)" "$(uname -m)" "$ID" "$PRETTY_NAME"; id -Gn')"
IFS='|' read -r os arch id pretty <<< "$(printf '%s\n' "$facts" | head -n 1)"
[ "$os" = Linux ] || die "$ADDRESS is not Linux ($os); use the skill's part for that system"
printf '%s\n' "$facts" | tail -n 1 | tr ' ' '\n' | grep -qxE 'wheel|sudo' \
  || die "$LOGIN is in neither the wheel nor the sudo group on $ADDRESS, so it cannot be its administrator"
[ "$id" != nixos ] || die "$ADDRESS runs $pretty, and this fork of the skill does not set up NixOS; use Debian, Ubuntu or Fedora"
say "$ADDRESS runs $pretty on $arch, and $LOGIN is an administrator"
say "next: apply.sh applies the distro-neutral script"
