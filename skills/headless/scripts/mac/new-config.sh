#!/bin/bash
# new-config.sh - make a Mac's config folder on this computer from the
# skill's default config (assets/mac), or update the settings of one.
#
# usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF
#          [--ssh-key PATH] [--host-name NAME] [--auto-login]
#          [--tailscale | --tailscale-app] [--tailscale-key-ref REF] [--tailscale-login-server URL]
#          [--extra-off NAME]... [--extra-on NAME]... [--keep-password-ssh]
#
# DIR becomes a git folder holding Brewfile (the software Homebrew keeps),
# machine.sh (your own additions, run as the account), settings.json (what
# the Mac should be) and headless.env (how to reach the machine and where
# the password lives; no secret). An existing DIR keeps its Brewfile and
# machine.sh; settings.json and headless.env are written again from the
# options given.
#
# The defaults suit a laptop that is still carried around: automatic
# sign-in off (so FileVault stays on), and these extras on: homebrew,
# brewAutoUpgrade, neverSleepOnPower, wakeOnLan, powerNapOff. These start
# off and turn on with --extra-on: startAfterPowerLoss, spotlightOff,
# siriOff.
#
# Tailscale: --tailscale runs the open-source daemon from Homebrew;
# --tailscale-app manages Tailscale's own app instead (installed from
# Tailscale's signed package if missing, kept running, checked by verify.sh;
# it updates itself). Pick at most one.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
EXTRAS=(homebrew brewAutoUpgrade neverSleepOnPower wakeOnLan powerNapOff startAfterPowerLoss spotlightOff siriOff)
EXTRAS_OFF="startAfterPowerLoss spotlightOff siriOff"
AUTO_LOGIN_DEFAULT=false
TAILSCALE_APP_SUPPORTED=1
TEMPLATE="$SCRIPTS/../assets/mac"
TEMPLATE_FILES="Brewfile machine.sh"
new_config "$@"
