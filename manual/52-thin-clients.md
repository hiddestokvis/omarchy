# Thin Clients

One strong Omarchy machine can serve the whole household or office. It becomes the **Omarchy server**: every app runs there, every file stays there, and each person gets their own account. The devices people sit at become **thin clients**: an old laptop, a Raspberry Pi, a mini PC with 2 GB of RAM. They only draw the desktop and pass the keyboard, mouse, speakers, microphone and camera through.

It doesn't stream the screen as video. The thin client runs Omarchy's own compositor, bar, menus and terminals, so moving windows, switching workspaces, animations, the cursor and typing all happen on the device itself and feel exactly like a local Omarchy. Apps on the server send only what they actually change, as compressed, pixel-exact updates. Terminals send nothing but text.

## Setting up the server

Install Omarchy on the server as usual, then run:

```bash
omarchy server setup
```

This installs what thin clients need, prepares SSH for them, and shares the machine fairly: every person gets an equal share of CPU and disk, and no one can use more than 70% of the memory before their apps slow down instead of everyone's.

Then add each person who will connect:

```bash
omarchy server user add alice
```

That creates the account if it doesn't exist (asking for a password, used once when Alice sets up her device), and reserves a private webcam for her. Install whatever apps people should have on the server, with the menu or `omarchy pkg add`.

`omarchy server status` shows who is connected and how much memory and CPU each person uses. `omarchy server user remove alice` takes away thin client access while keeping her account and files.

## Setting up a thin client

Install Omarchy on the device, then run:

```bash
omarchy thin setup alice@server
```

It installs a few small packages, creates a key for the device, asks for Alice's server password once, and connects. Log out and back in, and the device is a thin client.

Add `--slim` to also remove the big apps (Chromium, LibreOffice, Obsidian, Docker and the like) that now run on the server. That frees disk and memory on small devices.

## Using it

Everything works the way it does on any Omarchy machine:

- **Apps** from the launcher, the menu and the hotkeys open on the server and appear as normal windows. The launcher lists the server's apps, including web apps you install.
- **Terminals** open on the device, with the shell running on the server. Apps you start from that shell (`nautilus .`, `chromium`) show up on your screen too.
- **Files** live on the server. The file manager, file dialogs and downloads all use your server home folder.
- **Copy and paste** works between every window.
- **Notifications** from server apps appear in the device's notification area.
- **Sound** plays on the device's speakers, and the device's microphone is the default microphone on the server.
- **The camera** is off until you turn it on with `Super + Ctrl + Alt + V` (or `omarchy thin camera on`). It then appears in browsers and call apps on the server as a webcam named Thin-Client-Camera. Turn it on before you join a call.

Some things stay on the device on purpose, because they're about the device itself: Wi-Fi, Bluetooth, the audio mixer, screenshots, display settings, themes and the Omarchy menu. Installing apps from the menu installs them on the server.

`omarchy thin status` shows the connection, which streams are running, and how much data has gone each way.

## Tuning

Settings live in `~/.config/omarchy/thin.conf`. Restart the connection after changing them with `systemctl --user restart omarchy-thin`.

| Setting | What it does |
| --- | --- |
| `OMARCHY_THIN_COMPRESS` | `zstd=7` (default) uses the least bandwidth. On very slow devices, `lz4` uses less CPU. |
| `OMARCHY_THIN_AUDIO` | `opus` (default) uses about 100 kbit/s and almost nothing when quiet. `pulse` has the lowest delay but uses about 1.5 Mbit/s. `off` turns audio off. |
| `OMARCHY_THIN_CAMERA_*` | Camera device, size, frame rate and bitrate. Set `OMARCHY_THIN_CAMERA_ENCODER=copy` on devices too slow to encode video. |
| `OMARCHY_THIN_LOCAL_APPS` | Apps to run on the device instead, like `(firefox)` if you'd rather browse locally. |
| `OMARCHY_THIN_LOCAL_SHELL` | `1` opens terminals with a local shell. |

## Good to know

- **Video playback** inside a server app (YouTube, a video file, the other people in a call) is the one thing that costs real bandwidth, because every frame changes every pixel. It works well on a home or office network; over a weak connection, watch videos on the device instead.
- **Disconnecting** closes the apps you had open on the server. Unsaved work in them is lost, so save before you close the lid. Terminal programs survive if you run them inside `tmux`.
- **One device per person at a time.** Connecting from a second device takes over the session.
- To stop using the server, run `omarchy thin remove` and log out.
