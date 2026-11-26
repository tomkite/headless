# Mac details

The Mac is set up natively: macOS's own tools (`pmset`, `scutil`,
`defaults`, an sshd drop-in) for the settings, and Homebrew for software.
There is no Nix. Every step is a plain script that changes only what
differs, so running it again changes nothing.

## Before the skill starts (at the Mac)

- **Apple silicon, a current macOS** (Homebrew needs macOS 15 or later).
  Intel Macs are not supported.
- **An administrator account with a password.** The skill signs in as this
  account, Homebrew belongs to it, and with automatic sign-in on it is the
  account that signs in by itself at start-up.
- **Remote Login on**: System Settings > General > Sharing > Remote Login.
  "Allow access for" must include the account.
- **FileVault** may stay on, and on a laptop it should. The default is
  automatic sign-in **off**, so FileVault stays on; after each restart
  someone unlocks it at the Mac (types the account's password) before key
  sign-in works. Until then SSH answers but signs in only with the
  password. With automatic sign-in chosen (a Mac that stays plugged in
  somewhere nobody sits), the admin step turns FileVault off itself
  (below).
- **Its address**: shown under System Settings > General > Sharing, such as
  `macbook-air.local`, or an IP address from the router. A Tailscale address
  works too if the Tailscale app is already on the Mac.

## settings.json

`new-config.sh` writes it; edit it and run `apply.sh` again.

| Setting | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account. Begin with a lowercase letter, digit or underscore; remaining characters may also be dashes. |
| `hostName` | `null` | Computer, local (Bonjour) and host name; `null` keeps the current one. |
| `sshKeys` | your key | Public keys added to the account's `~/.ssh/authorized_keys`. |
| `keyOnlySsh` | `true` | SSH password, keyboard-interactive and root sign-in off. |
| `autoLogin` | `false` | Sign the account in on the screen at every start; needs FileVault off. `false` removes a stored password. |
| `tailscale.enable` | `false` | Run the open-source Tailscale daemon from Homebrew. Leave it off when the Tailscale app is installed. |
| `extras.homebrew` | `true` | Install Apple's Command Line Tools and Homebrew, then the `Brewfile`. |
| `extras.brewAutoUpgrade` | `true` | A launchd job, run as the account, does `brew update`, `brew upgrade` and `brew cleanup` every Sunday at 03:00 (at the next wake if the Mac slept through it); log in `~/Library/Logs/headless-brew-upkeep.log`. Needs `homebrew`. |
| `extras.neverSleepOnPower` | `true` | On the power adapter the Mac and its disks never sleep (the display sleeps after 10 minutes if it was set to never). On battery macOS's own settings stay. |
| `extras.wakeOnLan` | `true` | Wake for network access on the power adapter. |
| `extras.powerNapOff` | `true` | Power Nap off on battery and adapter. |
| `extras.startAfterPowerLoss` | `false` | Start up by itself after a power cut (desktop Macs; laptops have no such setting). |
| `extras.spotlightOff` | `false` | Spotlight indexing off on every volume. |
| `extras.siriOff` | `false` | Siri off for the account. |

`new-config.sh --extra-on NAME` turns on an extra that starts off;
`--extra-off NAME` turns one off; `--auto-login` turns automatic sign-in on.

A MacBook with its lid closed and no external display sleeps no matter
what `pmset` says; `neverSleepOnPower` keeps it awake with the lid open (or
closed with a display attached). `verify.sh` says so in an `info` line.

Turning an extra off later stops the skill managing it; it does not put
the macOS default back (Spotlight stays off, and so on) until the user
changes it at the Mac or in `machine.sh`. Automatic sign-in is the
exception: `false` removes the stored password.

## Brewfile and machine.sh

- `Brewfile`: what Homebrew keeps on the Mac. `apply.sh` runs `brew bundle
  install --no-upgrade` as the account, so anything listed and missing is
  installed; nothing is removed. Upgrades come from the weekly
  `brewAutoUpgrade` job, or `brew upgrade` on the Mac any time. Casks that
  update themselves (`auto_updates`) are left to their own updater. Casks
  whose installers need sudo fail over SSH and in the weekly job (sudo has
  no terminal there); install and upgrade those at the Mac.
- `machine.sh`: your own additions, run as the account (not root) after
  `brew bundle` on every apply, with Homebrew on `PATH`. Keep it safe to
  run again.

## The admin step (`admin.sh`)

As root, with the password from the store for `sudo -S`:

1. **Command Line Tools** (when `homebrew` is on and they are missing),
   through Software Update, as Homebrew's own installer does. It takes
   several minutes.
2. **Homebrew**, from its signed `.pkg` (pinned version and SHA-256 in
   `scripts/mac/remote/admin.sh`), made to belong to the account through
   `/var/tmp/.homebrew_pkg_user.plist`. An existing Homebrew is kept; if
   `/opt/homebrew` belongs to another account the step stops and says so.
3. **Automatic sign-in** (only when `autoLogin` is true): FileVault off, then
   the password stored as `/etc/kcpassword` (root-only, and recoverable by
   anyone with root on the Mac; say so).

### How it turns FileVault off

With automatic sign-in chosen and FileVault on, `admin.sh` runs, as root,
`fdesetup disable -inputplist` with the account name and password in a
plist on standard input (never a command line). In order:

1. While FileVault is still encrypting, it waits: macOS refuses to turn it
   off before then.
2. If the account is not one `fdesetup list` names (it has no secure token),
   it asks the user.
3. It turns FileVault off, then reads `fdesetup status`. Anything but
   "Decryption in progress" or "FileVault is Off" asks the user with
   macOS's message; a managed Mac whose organization forbids it asks too.
4. It waits until decryption ends. A restart before then stops at
   FileVault's unlock screen.

Every "ask the user" line names what the user can do: turn FileVault off at
the Mac, or set `"autoLogin": false`. Running `admin.sh` again picks up
where it stopped.

## Where things go on the Mac

- `~/.headless/config`: the copy of the config folder each apply uses.
- `~/.headless/remote`: the step scripts each step copies over.
- `/etc/headless/settings.json`: what the Mac should be, for `verify.sh`.
- `/etc/ssh/sshd_config.d/000-headless.conf`: the key-only lines. sshd takes
  the first value it reads, so it is named to come before macOS's own
  `100-macos.conf`.
- `/opt/homebrew`: Homebrew, owned by the account.
- `/Library/LaunchDaemons/com.headless.brew-upkeep.plist`: the weekly
  Homebrew upkeep job (runs as the account, not root).
- `/etc/kcpassword`: the automatic sign-in password, only when it is on.

## Common failures

| Message | Meaning and fix |
| --- | --- |
| `gave no single ed25519 host key; is Remote Login on?` | Remote Login is off, or the address is wrong. |
| `shows a different host key than the one pinned` | The Mac was reinstalled, or something else answers at that address. Find out which before deleting `known_hosts`. |
| `password sign-in ... failed` | Wrong password in the store, or the account is not allowed under Remote Login. |
| `is not an administrator` | Use an admin account, or make this one an admin at the Mac. |
| `Software Update offers no Command Line Tools` | Install them at the Mac with `xcode-select --install`, then run `admin.sh` again. |
| `/opt/homebrew belongs to ...` | Another account installed Homebrew. Use that account, or hand it over at the Mac. |
| `brew bundle did not install everything` | A formula or cask failed; its output says which. Casks that need sudo go in at the Mac. |
| `ask the user: ... FileVault ...` | The admin step could not turn FileVault off; the line says why. |
| `did not come back within ... seconds` | After a restart with FileVault on, the Mac waits at its unlock screen; unlock it at the Mac and run `verify.sh`. |
| `is not signed in on the screen after the restart` | Automatic sign-in did not work: FileVault on, or the password changed since `admin.sh` stored it (run it again). |

## Removing it

Delete `/etc/ssh/sshd_config.d/000-headless.conf` (password sign-in comes
back), `/etc/headless` and `~/.headless`, and `/etc/kcpassword` if present.
Stop the upkeep job with `sudo launchctl bootout
system/com.headless.brew-upkeep` and delete its plist.
Power settings stay as set; `sudo pmset -c sleep 1` and the like change
them back. Homebrew stays; its own uninstaller removes it.
