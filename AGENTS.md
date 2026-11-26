# Project agent memory

headless: this file is the always-loaded memory for agents working in this repo.
It is kept short on purpose - every line here is paid on every session.

## Learnings

- This fork (tomkite/headless) uses no Nix: Macs are set up natively (macOS tools + Homebrew/Brewfile, `scripts/mac/remote/{user,apply}.sh`), Linux only via the distro-neutral script; NixOS is refused. Don't reintroduce nix-darwin/NixOS paths when syncing from upstream kunchenguid/headless.
- `gh pr create` in this fork must pass `--repo tomkite/headless --base main`, or it targets upstream. PRs are squash-merged. The no-mistakes gate is skipped on forks (`if: github.repository == ...`), so its red/skip state is not a blocker here.
- Mac CI runs with `--extra-off homebrew`: the GitHub runner's Homebrew belongs to its `runner` account, so the Brewfile and weekly `brewAutoUpgrade` launchd job are proven only on real hardware (a MacBook Air on macOS 27 passed the full journey, restart included).
- The Homebrew `.pkg` in `scripts/mac/remote/admin.sh` is pinned by version and SHA-256 (`gh api repos/Homebrew/brew/releases/latest` gives both); bump them together.
- The global gitleaks hook flags an email in an SSH public key's comment; strip the comment from `sshKeys` in a config folder's `settings.json` rather than allowlisting it.
- With FileVault on (the Mac default here), `restart.sh` only completes after someone unlocks the Mac at its screen; key sign-in fails until then.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
