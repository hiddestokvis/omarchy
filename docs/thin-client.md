# Thin Client and Server

How `omarchy-thin-*` (the device) and `omarchy-server-*` (the machine that runs the apps) fit together. User-facing documentation is [`manual/52-thin-clients.md`](../manual/52-thin-clients.md).

## Why waypipe and not a video stream

Remote desktops (Sunshine, VNC, RDP) capture a whole rendered screen and encode it as video. Every frame crosses the network, compression artifacts show, and every interaction (dragging a window, an animation, the cursor) waits for a round trip.

The thin client instead runs its own Hyprland and Omarchy shell, and remote apps are Wayland clients of it, proxied by [waypipe](https://gitlab.freedesktop.org/mstoeckl/waypipe). Window management, animation, the cursor and input are local. waypipe forwards the Wayland protocol and, for buffer contents, only the damaged regions as lossless diffs compressed with zstd or lz4. Terminals are the cheapest case of all: the terminal emulator is local and only the PTY's text crosses the network.

Modern toolkits (GTK 4, Qt 6, Chromium, Electron) draw into buffers client-side, so there is no drawing-command protocol to forward; damage-region diffs of those buffers are the smallest faithful representation available. The only streams that are encoded as media are those that are media to begin with: audio (Opus) and the camera (H.264, or the camera's own MJPEG passed through).

## One connection

Everything rides one SSH connection per device. `omarchy-thin-connect` (run by `omarchy-thin.service`) starts `waypipe ssh` as the SSH `ControlMaster`; the remote command is `omarchy-server-session`, which waypipe server starts with `WAYLAND_DISPLAY` pointing at its proxy socket. Every other stream opens a channel on that master through `ControlPath`:

| Channel | Client side | Server side |
| --- | --- | --- |
| Session (waypipe) | `omarchy-thin-connect` | `omarchy-server-session` |
| App launch | `omarchy-thin-run` | `omarchy-server-launch` |
| Terminal | `omarchy-thin-exec` | `omarchy-server-exec` |
| Speakers | `omarchy-thin-audio speakers` | `omarchy-server-audio speakers` |
| Microphone | `omarchy-thin-audio mic` | `omarchy-server-audio mic` |
| Camera | `omarchy-thin-camera stream` | `omarchy-server-camera` |
| Notifications | `omarchy-thin-notifications` | `omarchy-server-notify-bridge` |
| Launcher entries | `omarchy-thin-sync-apps` | `omarchy-server-apps-export` |

`default/thin/client.sh` holds the shared SSH options. `omarchy-server-setup` raises sshd's `MaxSessions`, since each channel counts as a session.

## The server session

`omarchy-server-session` runs for as long as the device is connected. It:

- starts `xwayland-satellite` on a free display for X11-only apps
- with Opus audio, loads a null sink (`omarchy_thin_speakers`) and a pipe source (`omarchy_thin_mic`) into the user's PipeWire and makes them the defaults
- writes the session environment to `$XDG_RUNTIME_DIR/omarchy-thin/env` and imports it into the user's systemd manager and D-Bus activation environment, so D-Bus activated apps (Nautilus, portals) also land on the thin client
- prepends `default/thin/server-bin` to `PATH`, whose `uwsm-app` hands launches to `omarchy-server-launch`, so Omarchy's own launchers work unchanged on the server
- removes all of it when the connection ends, and ends an older session of the same user when a newer one starts

`omarchy-server-launch` runs each app as a transient unit in the user's `app.slice`, so it outlives the channel that started it and is accounted like any other app.

## Routing launches on the device

A thin client session gets `default/thin/uwsm-env` in `~/.config/uwsm/env.d/`, which sets `OMARCHY_THIN=1`, prepends `default/thin/bin` to `PATH`, and puts `~/.local/share/omarchy-thin` first on `XDG_DATA_DIRS`.

- `default/thin/bin/uwsm-app` sees every launch. `thin_command_location` in `client.sh` decides: Omarchy's own commands, terminals and hardware tools are local; `omarchy-install-*`, `omarchy-pkg-*`, `omarchy-webapp-*`, `omarchy-tui-*` and `omarchy-remove-*` are remote; anything else is remote. For `xdg-terminal-exec` the terminal stays local and the command inside (or the shell) is wrapped in `omarchy-thin-exec`. Menu flows run as `bash -c "omarchy-show-logo; <cmd>; ..."`, so the decision uses `<cmd>`.
- Launchers that inspect local state before starting an app (the browser and web app launchers, Nautilus, Spotify and others) are symlinked in `default/thin/bin` to `omarchy-thin-forward`, which runs the same launcher on the server.
- `omarchy-thin-sync-apps` copies the server's desktop entries and their hicolor/pixmap icons into `~/.local/share/omarchy-thin`, rewriting `Exec=` to go through `omarchy-thin-run` and dropping `TryExec=` and `DBusActivatable=`. Desktop IDs are unchanged, so MIME defaults and `xdg-open` reach the server's apps. Entries the device has installed itself are skipped.

`test/shell.d/thin-client-test.sh` covers the routing decisions.

## Multiple users

Each person is a normal Unix account on the server, listed in `/etc/omarchy-server/users`. Isolation comes from the account boundary: sessions, runtime directories, PipeWire instances and D-Bus buses are all per user. `/etc/systemd/system/user-.slice.d/50-omarchy-server.conf` gives every user slice equal CPU and IO weight, a memory ceiling, and a task limit.

`omarchy-server-cameras --apply` gives the user on line N of the users file `/dev/video(39+N)`, a v4l2loopback device with `exclusive_caps`, owned by that user with mode 0600 via a generated udev rule.

## Known gaps

- waypipe has no session resume, so dropping the connection for longer than the SSH keepalive window (two minutes) closes the user's GUI apps.
- Remote apps use the server user's theme; a theme change on the device does not follow.
- Notifications are one-way: actions and clicking to focus the sending app are not forwarded.
- The speaker and microphone streams run while connected rather than starting on demand; Opus DTX keeps idle cost near zero.
