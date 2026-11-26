# Linux details

## Before the skill starts (at the machine)

- **systemd**, on x86_64 or aarch64, running Debian, Ubuntu or Fedora
  (dnf5); the skill applies a distro-neutral script. Another systemd
  distribution can use the script with `autoUpdates` and Tailscale off.
  NixOS is not supported in this fork: `connect.sh` refuses it.
- **An account with a password that may use sudo**: in the `sudo` group
  (Debian, Ubuntu) or `wheel` (Fedora). The skill never signs in as
  root and adds no passwordless sudo rule; every admin step pipes the
  password from the store to `sudo -S`.
- **An SSH server** the user can reach with that account's password, for
  the first sign-in only.
- **Its address**: an IP address or a name.

## What the settings do

`settings.json` holds what the script applies.

| Setting | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account. |
| `hostName` | `null` | The machine's host name; `null` keeps the current one. |
| `sshKeys` | your key | Public keys that may sign in, besides `~/.ssh/authorized_keys`. |
| `keyOnlySsh` | `true` | SSH password, keyboard-interactive and root sign-in off. |
| `autoLogin` | `true` | The account's session starts at boot (systemd lingering), so its user services run with nobody signed in. Nothing signs in on a screen. |
| `tailscale.enable` | `false` | Run the Tailscale daemon, from Tailscale's own signed package repository. |
| `extras.neverSleep` | `true` | Sleep, suspend and hibernate are masked. |
| `extras.autoUpdates` | `true` | unattended-upgrades (apt) or dnf5-automatic applying updates. |

Always on: SSH ends sessions whose other end is gone after about three
minutes, and `/etc/headless/settings.env` records what the machine should
be, for `verify.sh`.

The script writes `/etc/ssh/sshd_config.d/00-headless.conf` (first in name
order, so it wins over the distribution's own files), and checks with
`sshd -T` that password sign-in is really off. On Fedora that folder is
root-only, so `verify.sh` reports that line as `n/a` and relies on its
check that the server refuses a password. Turning a setting off later
undoes it: the SSH lines go, lingering stops. Masked sleep targets and
installed packages stay.

## When something fails

- **"is in neither the wheel nor the sudo group"**: add the account at the machine
  (`usermod -aG sudo NAME`, or `wheel`), sign out and in, and run
  `connect.sh` again.
- **"does not read /etc/ssh/sshd_config.d"**: an old or edited
  `sshd_config`; add `Include /etc/ssh/sshd_config.d/*.conf` at its top.
- **"another setting overrides"**: some file sets `PasswordAuthentication
  yes` before the headless one; find it with `sudo sshd -T` and
  `grep -r PasswordAuthentication /etc/ssh`.
- **"runs NixOS, which this fork of the skill does not set up"**: this
  fork supports Debian, Ubuntu and Fedora only.
- **It does not come back after a restart**: the machine's firmware decides
  whether it powers on after a power cut and whether it wakes from the
  network; set those in its firmware settings. The skill cannot change
  them from Linux.
