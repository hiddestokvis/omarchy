# Thin Clients

One strong Omarchy machine can be the computer for a whole household, classroom or office. It becomes the **Omarchy server**: everyone's apps run there and everyone's files stay there, each person with their own account and their own desktop. The machines people sit at become **thin clients**: an old laptop, a 2010 iMac, a mini PC. They boot straight to a sign-in screen, and once you sign in they behave like a full Omarchy computer.

Nothing is streamed as video. The thin client draws the desktop itself (the bar, menus, window layout, animations, the cursor), so all of that is instant. The server sends only the parts of each window that actually changed, compressed without any loss of quality. Terminals send nothing but text.

Your desktop lives on the server. Lock the thin client, walk to another one, sign in, and every app is exactly where you left it, mid-sentence.

## Setting up the server

Install Omarchy on the server with disk encryption on (the installer's default), then run:

```bash
omarchy server setup
```

This prepares the server for thin clients. It refuses to run on an unencrypted disk, since the server holds everyone's files. It builds the display software once (thin clients reuse that build), and shares the machine fairly: everyone gets an equal share of CPU and disk, and nobody can use enough memory to slow down everyone else.

### People

```bash
omarchy server user add alice
```

```bash
omarchy server user add sam students
```

This creates the account (asking for the password they'll type on the sign-in screen) and puts them on a profile: `default`, or the one you name. Other commands:

- `omarchy server user list` shows everyone, their profile, and whether their desktop is running
- `omarchy server user set-profile sam default` moves someone to another profile
- `omarchy server user password sam` resets a password
- `omarchy server user remove sam` takes away thin client access and closes their desktop, but keeps their files; add `--delete-files` to remove the account entirely

### Profiles

A profile sets what everyone on it gets. Create one with `omarchy server profile add students`, which opens it in your editor, or change one with `omarchy server profile edit default`. Saving applies it to everyone on that profile.

| Setting | What it does |
| --- | --- |
| `APPS` | Apps to install on the server, like `(libreoffice-fresh gimp)` |
| `LAUNCHER_ONLY` | Show only these apps in the launcher, like `(chromium libreoffice-writer)`. Leave empty to show everything. This keeps the launcher tidy for someone; it doesn't stop them starting other apps from a terminal. |
| `WEBAPPS` | Web apps to put in everyone's launcher, as `"Name\|URL\|icon"` |
| `THEME`, `BACKGROUND` | The theme (any Omarchy theme name) and background image. Put background images in `/etc/omarchy-server/backgrounds`. |
| `THEME_LOCKED` | `1` stops people changing their theme; it's set back at every sign-in |
| `CPU_WEIGHT`, `MEMORY_MAX` | A person's share of the processor (100 is normal; 50 is half as much when the server is busy) and their memory limit (like `4G` or `25%`) |
| `NETWORK`, `NETWORK_ALLOW`, `NETWORK_DENY` | What their apps may reach. `allow` lets everything through except `NETWORK_DENY`; `deny` blocks everything except `NETWORK_ALLOW`. Entries look like `"tcp:443"`, `"10.0.0.0/8"` or `"tcp:22@10.0.0.5"`. Use addresses and ports, not website names. |

`omarchy server firewall --show` prints the network rules the profiles add up to. Inbound access to the server itself stays with the regular firewall (`ufw`).

### Devices

Signing in takes two things: a device the server knows, and the person's password. A stolen password doesn't work from a stranger's computer, and a stolen thin client doesn't work without a password.

- `omarchy server device list` shows enrolled thin clients
- `omarchy server device remove kitchen-imac` stops one from connecting, for when it's lost or sold

`omarchy server status` shows who is signed in, from which device, and how much memory and CPU each person is using.

## Setting up a thin client

Install Omarchy on the device, with disk encryption on. Then, signed in as the admin account you created during install, run:

```bash
omarchy thin install studio.local
```

1. It shows the server's fingerprint. On the server, run `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` and check that they match. This is what makes sure the device only ever talks to your server.
2. It asks for a server admin's password, to enroll the device. Use `--admin <name>` if your admin account there has a different name, and `--name <name>` to give the device a name of its own.
3. It removes the big desktop apps (they run on the server now) and makes the machine start at the sign-in screen. Add `--keep-apps` to keep them.

Reboot, and the device is a thin client. Its admin account still works: switch to another console with `Ctrl + Alt + F3`, or SSH in.

### Old machines

Thin clients need very little: a 64-bit processor from 2009 or later, 2 GB of memory, and a graphics card that runs Hyprland. A 2010 iMac is plenty. On thin clients, Omarchy leaves out window blur and shadows, which old graphics cards struggle with. Animations stay. For the camera on a slow machine, set `OMARCHY_THIN_CAMERA_ENCODER=copy` in `/etc/omarchy-thin/thin.conf`.

## Using a thin client

Sign in with your server username and password, and you're at your desktop:

- **Apps** from the launcher, the menu and the hotkeys open on the server and appear as normal windows. The launcher shows the server's apps, including web apps.
- **Terminals** open with your shell on the server. Apps you start from there (`nautilus .`) open on your screen too.
- **Files** are in your home folder on the server. File dialogs, downloads and the file manager all use it.
- **Copy and paste** works between every window.
- **Notifications** from your apps appear as usual.
- **Sound** plays on the device, and its microphone is your microphone in every app.
- **The camera** is off until you turn it on with `Super + Ctrl + Alt + V`. It then shows up in browsers and call apps as a webcam named Thin-Client-Camera. Turn it on before you join a call.
- **Your theme** follows you. Pick one from the theme menu and it's what you get on every thin client, unless your administrator has set it for you.

Wi-Fi, Bluetooth, sound settings, screenshots and the display settings belong to the device you're sitting at, so they work on the device. Installing an app from the menu installs it on the server.

### Leaving, and signing out

- **Lock** (`Super + Escape`, or walking away until the screen locks) and **Logout** both take you back to the sign-in screen. Your apps keep running on the server, and the next sign-in, here or on any other thin client, brings them all back.
- **Sign Out of Server** in the system menu closes all your apps on the server. Use it when you're done for the day, so they stop using the server's memory.
- **Signing in on another device** moves your desktop there. The first device goes back to its sign-in screen and says so.

When you leave, the device forgets your session: your clipboard, notifications and the list of your apps are wiped before the sign-in screen comes back.

`omarchy thin status` shows who is signed in, which parts of the session are running, and how much data has gone each way.

## Good to know

- **One device at a time.** Your desktop shows on the device you signed in on most recently, not on two at once.
- **Video inside an app** (YouTube, the other people in a call) costs real bandwidth, because every frame changes every pixel. It's fine on a home or office network; on a weak connection, expect it to stutter.
- **If the network drops**, the device goes back to the sign-in screen within half a minute. Your apps are still running on the server; sign in again to pick up where you were.
- **Restarting the server** closes everyone's apps, the same as restarting any computer.
