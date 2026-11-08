#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/ufw" <<'STUB'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == status ]]; then
  echo 'Status: inactive'
fi
STUB

cat >"$stub_dir/ufw-docker" <<'STUB'
#!/bin/bash
set -euo pipefail
PATH="/bin:/usr/bin:/sbin:/usr/sbin:/snap/bin/"
printf 'ufw-docker %s\n' "$*" >>"$TEST_LOG"
if ! ufw status 2>/dev/null | grep -Fq 'Status: active'; then
  echo 'inactive' >&2
  exit 1
fi
STUB

cat >"$stub_dir/sed" <<'STUB'
#!/bin/bash
printf 'sed %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == 0,/^PATH=* ]]; then
  exec /usr/bin/sed "$@"
fi
exit 0
STUB

cat >"$stub_dir/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB

# Thin client images leave Docker out; the stub answers from $INSTALLED.
cat >"$stub_dir/omarchy-pkg-present" <<'STUB'
#!/bin/bash
[[ " $INSTALLED " == *" $1 "* ]]
STUB

chmod +x "$stub_dir"/*

export TEST_LOG="$stub_dir/firewall.log"
INSTALLED="ufw ufw-docker" PATH="$stub_dir:$PATH" bash -eE -c 'source "$1"' bash "$ROOT/install/config/firewall.sh"

grep -q '^ufw-docker install$' "$TEST_LOG" || fail "ufw-docker rules are installed"
grep -q '^systemctl enable ufw$' "$TEST_LOG" || fail "ufw is enabled for next boot"

pass "firewall config installs ufw-docker rules without activating live UFW"

: >"$TEST_LOG"
INSTALLED="ufw" PATH="$stub_dir:$PATH" bash -eE -c 'source "$1"' bash "$ROOT/install/config/firewall.sh" ||
  fail "firewall config finishes on a thin client image without Docker"
grep -q '^ufw-docker' "$TEST_LOG" && fail "ufw-docker is not run when it is not installed"
grep -q '^systemctl enable ufw$' "$TEST_LOG" || fail "ufw is still enabled without Docker"

pass "firewall config skips the Docker rules on images without Docker"
