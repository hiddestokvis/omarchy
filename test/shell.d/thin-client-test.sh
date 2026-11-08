#!/bin/bash

# The thin client's uwsm-app overlay decides, for every launch, whether an app
# runs on this device or on the server, and rewrites terminals so the shell
# inside them runs on the server. A wrong call either strands an app on a
# device that does not have it or runs a local hardware tool on the server.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home/.config/omarchy"
export HOME="$work/home" CALLS="$work/calls"

cat >"$work/bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'local %s\n' "$*" >>"$CALLS"
SH
cat >"$work/bin/omarchy-thin-run" <<'SH'
#!/bin/bash
printf 'remote %s\n' "$*" >>"$CALLS"
SH
chmod +x "$work/bin/"*

echo 'OMARCHY_THIN_SERVER="alice@server"' >"$HOME/.config/omarchy/thin.conf"
export PATH="$ROOT/default/thin/bin:$work/bin:$PATH"

launch() {
  : >"$CALLS"
  uwsm-app -- "$@"
  cat "$CALLS"
}

[[ $(launch chromium --new-window) == "remote chromium --new-window" ]] ||
  fail "a desktop app runs on the server"

[[ $(launch omarchy-launch-about) == "local -- omarchy-launch-about" ]] ||
  fail "Omarchy's own commands stay on the device"

[[ $(launch xdg-terminal-exec --dir=/home/local) == "local -- xdg-terminal-exec -e omarchy-thin-exec" ]] ||
  fail "a new terminal opens a shell on the server, without the local cwd"

[[ $(launch xdg-terminal-exec --app-id=org.omarchy.btop -e btop) == "local -- xdg-terminal-exec --app-id=org.omarchy.btop -e omarchy-thin-exec btop" ]] ||
  fail "a TUI runs on the server inside a local terminal"

[[ $(launch xdg-terminal-exec --app-id=org.omarchy.wiremix -e wiremix) == "local -- xdg-terminal-exec --app-id=org.omarchy.wiremix -e wiremix" ]] ||
  fail "the audio mixer drives this device's audio"

script="omarchy-show-logo; omarchy-install-dev-env ruby; code=\$?"
[[ $(launch xdg-terminal-exec -e bash -c "$script") == "local -- xdg-terminal-exec -e omarchy-thin-exec bash -c $script" ]] ||
  fail "menu install flows install on the server"

script="omarchy-show-logo; omarchy-setup-wifi; code=\$?"
[[ $(launch xdg-terminal-exec -e bash -c "$script") == "local -- xdg-terminal-exec -e bash -c $script" ]] ||
  fail "menu setup flows for this device stay local"

echo 'OMARCHY_THIN_LOCAL_APPS=(firefox)' >>"$HOME/.config/omarchy/thin.conf"
[[ $(launch firefox) == "local -- firefox" ]] ||
  fail "apps listed in OMARCHY_THIN_LOCAL_APPS stay on the device"

pass "thin client routes launches between device and server"
