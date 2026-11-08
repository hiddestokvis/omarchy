#!/bin/bash

# The thin client's uwsm-app overlay decides, for every launch, whether an app
# runs on this device or on the server, and rewrites terminals so the shell
# inside them runs on the server. A wrong call either strands an app on a
# device that does not have it or runs a local hardware tool on the server.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/etc"
export HOME="$work/home" CALLS="$work/calls" OMARCHY_THIN_ETC="$work/etc"

cat >"$work/bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'local %s\n' "$*" >>"$CALLS"
SH
cat >"$work/bin/omarchy-thin-run" <<'SH'
#!/bin/bash
printf 'remote %s\n' "$*" >>"$CALLS"
SH
chmod +x "$work/bin/"*

echo 'OMARCHY_THIN_SERVER="server"' >"$OMARCHY_THIN_ETC/thin.conf"
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

echo 'OMARCHY_THIN_LOCAL_APPS=(firefox)' >>"$OMARCHY_THIN_ETC/thin.conf"
[[ $(launch firefox) == "local -- firefox" ]] ||
  fail "apps listed in OMARCHY_THIN_LOCAL_APPS stay on the device"

pass "thin client routes launches between device and server"

# Per-person network rules: a profile entry that parses wrong either blocks
# what an admin allowed or, worse, lets through what they denied.
server_etc="$work/server"
mkdir -p "$server_etc/profiles"
cat >"$server_etc/profiles/kids.conf" <<'CONF'
NETWORK=deny
NETWORK_ALLOW=("tcp:443" "10.0.0.0/8" "tcp:22@10.0.0.5" "fd00::/8" "example.com")
CONF
cat >"$server_etc/profiles/work.conf" <<'CONF'
NETWORK_DENY=("tcp:25")
CONF
echo 'NETWORK=allow' >"$server_etc/profiles/open.conf"
printf '%s kids\nnobody work\ndaemon open\n' "$(id -un)" >"$server_etc/users"

rules=$(OMARCHY_SERVER_ETC="$server_etc" "$ROOT/bin/omarchy-server-firewall" --show 2>"$work/firewall.err")
person=$(id -un)
person_chain=$(awk -v c="chain person_${person//-/_} {" '$0 ~ c { found = 1; next } found && /}/ { exit } found' <<<"$rules")

[[ $rules == *"meta skuid $(id -u) jump person_${person//-/_}"* ]] || fail "a restricted person's traffic goes through their chain"
[[ $person_chain == *"tcp dport 443 accept"* && $person_chain == *"ip daddr 10.0.0.5 tcp dport 22 accept"* &&
  $person_chain == *"ip6 daddr fd00::/8 accept"* ]] || fail "allowed ports, hosts and networks are let through"
[[ $(tail -1 <<<"$person_chain") == *"reject"* ]] || fail "a deny profile rejects everything it does not allow"
grep -q "example.com" "$work/firewall.err" || fail "host names are refused rather than silently dropped"
[[ $rules == *"tcp dport 25 counter reject"* ]] || fail "an allow profile rejects what it denies"
[[ $rules != *"skuid $(id -u daemon) "* ]] || fail "an unrestricted profile adds no rules"

pass "server firewall turns profiles into per-person rules"
