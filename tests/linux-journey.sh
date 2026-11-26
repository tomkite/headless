#!/bin/bash
# tests/linux-journey.sh - the skill's Linux journey end to end against one
# Linux machine, as an agent following SKILL.md runs it: new config, first
# sign-in, apply (the distro-neutral script), verify, a second apply that
# changes nothing, and optionally restart and verify again. Then it checks
# the transcript never holds the password.
# Intent: the Linux journey runs in CI, and a grep of its whole log for the
# password finds nothing; with --restart it also proves the machine comes
# back with the user's session started by itself.
#
# usage: tests/linux-journey.sh ADDRESS LOGIN ENV_FILE CONFIG_DIR
#          [--restart] [-- NEW_CONFIG_OPTION...]
#
# ENV_FILE holds HEADLESS_PASSWORD=... (mode 600).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINUX="$ROOT/skills/headless/scripts/linux"
ADDRESS="${1:?}" LOGIN="${2:?}" ENV_FILE="${3:?}" DIR="${4:?}"
shift 4
RESTART=0
while [ $# -gt 0 ]; do
  case "$1" in
    --restart) RESTART=1; shift ;;
    --) shift; break ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$DIR")"
log="$DIR.journey.log"
: > "$log"
step() { echo "== $*" | tee -a "$log"; "$@" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }

step "$LINUX/new-config.sh" "$DIR" --address "$ADDRESS" --login "$LOGIN" \
  --password-ref "env:$ENV_FILE:HEADLESS_PASSWORD" --ssh-key "${SSH_KEY:-$HOME/.ssh/id_ed25519}" "$@"
step "$LINUX/connect.sh" "$DIR"
step "$LINUX/apply.sh" "$DIR"
step "$LINUX/verify.sh" "$DIR"
# A second apply changes nothing.
step "$LINUX/apply.sh" "$DIR"
# The last step's output: everything after the last "== " line.
last="$(awk '/^== /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$log")"
if printf '%s' "$last" | grep -q 'headless: changed:'; then echo "FAIL  the second apply changed something" | tee -a "$log"; exit 1; fi
echo "ok    the second apply changed nothing" | tee -a "$log"
if [ "$RESTART" = 1 ]; then
  step "$LINUX/restart.sh" "$DIR"
  step "$LINUX/verify.sh" "$DIR"
fi

# The password must appear nowhere in what the journey printed.
pw="$(sed -n 's/^HEADLESS_PASSWORD=//p' "$ENV_FILE")"
if grep -qF -- "$pw" "$log"; then echo "FAIL  the journey's output holds the password"; exit 1; fi
echo "ok    the journey's output never holds the password ($(wc -l < "$log" | tr -d ' ') lines checked)"
