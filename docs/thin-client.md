# Thin Client and Server

How `omarchy-thin-*` (the device) and `omarchy-server-*` (the machine that runs everyone's desktop) fit together. User-facing documentation is [`manual/52-thin-clients.md`](../manual/52-thin-clients.md).

## Why wprs and not a video stream

Remote desktops (Sunshine, VNC, RDP) capture a rendered screen and encode it as video. Every frame crosses the network, compression shows, and every interaction (dragging a window, an animation, the cursor) waits for a round trip.

Here the thin client runs its own Hyprland and Omarchy shell, and remote apps appear as native windows of it through [wprs](https://github.com/wayland-transpositor/wprs) ("like xpra, but for Wayland"):

- `wprsd` on the server is a Wayland compositor that renders nothing. It keeps each app's surfaces and last committed buffer, and sends buffer updates as losslessly compressed data: a per-channel difference filter and a colour transform, then zstd. GTK 4, Qt 6, Chromium and Electron draw their own pixels, so there are no drawing commands to forward; lossless buffer updates are the smallest faithful form of what they draw.
- `wprsc` on the device recreates those surfaces as windows of the local compositor. Window management, animation, the cursor and input are local.
- Because `wprsd` holds the state, a device can disconnect and any device can attach later and get every window back. That is what makes the desktop persistent and movable between devices. Waypipe, the earlier choice, can't do this: its windows die with the connection.

The only streams encoded as media are those that are media to begin with: audio (Opus) and the camera (H.264, or the camera's own MJPEG passed through).

wprs's wire protocol is not stable between builds, so the server and every thin client run one pinned build, packaged as `omarchy-wprs` from `default/thin/pkg/wprs/PKGBUILD`. `omarchy-server-wprs-build` builds it once on the server and keeps the package in `/var/lib/omarchy-server/packages`, where `omarchy-thin-install` fetches it. Upstream compiles for `x86-64-v3` (AVX2), which crashes on CPUs before 2013; the PKGBUILD builds for `x86-64-v2` instead, so 2009–2012 machines like a 2010 iMac run it. Its SIMD paths are chosen at compile time, and v2 selects the SSE4.1 ones.

## The device: an appliance

There are two ways to make a thin client:

- **The thin client ISO.** The omarchy-iso repo's `omarchy-iso-make --thin` builds it from `install/omarchy-thin-base.packages` instead of `omarchy-base.packages`. The ISO installs that much smaller set and then runs `omarchy-thin-provision --first-install` in the target.
- **A regular install.** `omarchy-thin-install` installs `install/omarchy-thin.packages`, removes `install/omarchy-thin-slim.packages`, then runs the same two steps by hand.

Both end in the same two steps:

- `omarchy-thin-provision` (root, chroot-safe) creates the `thin` account and its SDDM autologin, links the user units, and arms `omarchy-thin-enroll.service` with `/var/lib/omarchy-thin/enroll-pending`.
- `omarchy-thin-enroll` (root, on tty1 at first boot, like `omarchy-provision-owner`) brings up a network, pins the server host key after the fingerprint check, enrolls the device key through a server admin's sudo, and fetches the server's wprs build if the device lacks it.

Setup leaves that need packages the thin set leaves out (cups, Docker, mise, Chromium) skip themselves when those packages are absent.

The result:

- `/etc/omarchy-thin/`: `thin.conf` (server address and media settings), `known_hosts` (the server host key, pinned under the alias `omarchy-server` after the admin confirms the fingerprint), and `device_key` (this device's enrollment key, readable only by `thin`).
- An unprivileged, passwordless, sudo-less `thin` account that SDDM logs in automatically. Its uwsm environment (`default/thin/uwsm-env`) sets `OMARCHY_THIN=1`, puts `default/thin/bin` first on `PATH`, and puts `~/.local/share/omarchy-thin` first on `XDG_DATA_DIRS`.
- `omarchy-thin-greeter.service` (user unit of `thin`) runs the session lifecycle in a loop:
  1. `omarchy-thin-login-prompt`, fullscreen in foot, asks for the username and password and returns them in a 0600 file on the runtime tmpfs.
  2. The greeter starts the SSH ControlMaster as the transient unit `omarchy-thin-link`. It authenticates with the device key, then the password through `SSH_ASKPASS` (`omarchy-thin-askpass`); the password file is deleted as soon as authentication ends.
  3. It runs `omarchy-server-desktop attach` as a coprocess. That channel stays open for the whole session. When it reads `ready <socket>`, the greeter forwards the server's wprs socket to a local one, pulls the theme and background (`omarchy-thin-look`) and the launcher entries (`omarchy-thin-sync-apps`), and starts `omarchy-thin-session.target`: `omarchy-thin-display` (wprsc), speakers, microphone and notifications.
  4. The session ends when the attach channel closes. That happens through `omarchy-thin-logout` (Lock and Logout, via the `omarchy-system-lock` and `omarchy-system` overlays), `omarchy-thin-signout`, a takeover (the channel prints `moved` first), or a lost connection (keepalives notice within 30 s).
  5. The greeter stops the session, closes the connection, wipes the session's traces (synced app entries, clipboard history, notification history, the Wayland clipboard), restarts the shell, and shows the prompt again with the reason.

## The server: persistent desktops

Each person is a Unix account in group `omarchy-thin`, listed with their profile in `/etc/omarchy-server/users` (`user profile` per line), with lingering enabled so their user manager outlives their connections.

- `omarchy-server-desktop.service` (user unit) runs `omarchy-server-desktop run`. That loads a null sink and a pipe source into the person's PipeWire as the default speakers and microphone, writes the session environment to `$XDG_RUNTIME_DIR/omarchy-thin/env` and imports it into the user manager and D-Bus activation, then runs `wprsd`. X11 apps go through wprs's `xwayland-xdg-shell`, on display `100 + uid % 800`, so people don't collide.
- `omarchy-server-desktop attach` starts that service if needed, enforces a locked theme, and records itself and its sshd connection in `attached`. When another device attaches, it signals the previous attach shell (`USR1`), which prints `moved` to its device and closes that connection.
- `omarchy-server-desktop end` (Sign Out of Server) stops every app unit and the desktop.
- `omarchy-server-launch` runs each app as a transient unit `omarchy-thin-app-*` in the person's `app.slice`, so apps outlive the channel that started them. `default/thin/server-bin/uwsm-app` sends Omarchy's own launchers there.

## One connection per device

| Channel | Device | Server |
| --- | --- | --- |
| Attach (held open) | `omarchy-thin-greeter` | `omarchy-server-desktop attach` |
| Display | `omarchy-thin-display` (wprsc, forwarded socket) | `wprsd` |
| App launch | `omarchy-thin-run` | `omarchy-server-launch` |
| Terminal | `omarchy-thin-exec` | `omarchy-server-exec` |
| Speakers / microphone | `omarchy-thin-audio` | `omarchy-server-audio` |
| Camera | `omarchy-thin-camera stream` | `omarchy-server-camera` |
| Notifications | `omarchy-thin-notifications` | `omarchy-server-notify-bridge` |
| Launcher entries | `omarchy-thin-sync-apps` | `omarchy-server-apps-export` |
| Theme and background | `omarchy-thin-look` | `omarchy-server-look` |

`thin_ssh` in `default/thin/client.sh` only ever rides the signed-in master (`BatchMode=yes`, no key that would work alone), so nothing on the device can reach the server without someone signed in.

## Routing launches on the device

`default/thin/bin/uwsm-app` sees every launch; `thin_command_location` in `client.sh` decides where each one runs.

- **Local:** Omarchy's own commands, terminals, and hardware tools.
- **Remote:** `omarchy-install-*`, `omarchy-pkg-*`, `omarchy-webapp-*`, `omarchy-tui-*` and `omarchy-remove-*`, plus anything else not listed as local.
- **Terminals:** for `xdg-terminal-exec`, the terminal stays local and the command (or the shell) inside it runs through `omarchy-thin-exec`.

Launchers that inspect local state are symlinked to `omarchy-thin-forward`, which runs them on the server. The `omarchy-theme-set` overlay pushes a theme change to the server. `test/shell.d/thin-client-test.sh` covers the routing decisions.

## Security

- **Disks:** `omarchy-server-setup` refuses an unencrypted root filesystem unless given `--allow-unencrypted`; `omarchy-thin-install` warns. Both rely on Omarchy's LUKS install.
- **Transport:** SSH, with the server identity pinned at install.
- **Authentication:** `AuthenticationMethods publickey,keyboard-interactive:pam` for `Match Group omarchy-thin`. The public keys come from `/etc/omarchy-server/devices` (root-owned, managed by `omarchy-server-device`), so a person's password works only from an enrolled device. Device keys carry `restrict,port-forwarding,pty`, and sshd allows only local Unix-socket forwarding for the group.
- **Isolation:** by Unix account. Sessions, runtime directories, PipeWire, D-Bus and cameras (a v4l2loopback device per person, mode 0600 through a generated udev rule) are per person. `user-.slice.d/50-omarchy-server.conf` gives equal CPU and IO weight, a memory ceiling and a task limit; profiles narrow them per person with `systemctl set-property`.
- **Network:** `omarchy-server-firewall` compiles profiles into the nftables table `inet omarchy_server`, which matches outbound traffic on `meta skuid`. Loopback, established connections and DNS are always allowed. `omarchy-server-firewall.service` loads it at boot. ufw still handles inbound.
- **On the device:** the session's traces are wiped at every sign-out. The `thin` account has no password and no sudo, and holds nothing personal.

## Known gaps

- One attached device per person; wprs has no simultaneous multi-viewer mode.
- The `thin` account's own Omarchy shell stays reachable from the sign-in screen (the bar, network settings). It runs unprivileged and holds no personal data.
- `LAUNCHER_ONLY` curates the launcher; it doesn't stop a person running other installed programs from a terminal.
- Notifications are one-way: actions and click-to-focus aren't forwarded.
- Network rules take addresses, networks and ports, not host names.
- The pinned wprs needs a rebuild on every machine when the pin moves; the server and the devices must move together.
