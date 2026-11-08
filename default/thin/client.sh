# Shared helpers for the omarchy-thin-* commands. Sourced, not executed.
#
# Every thin client stream rides one SSH connection: omarchy-thin-connect opens
# it through waypipe as the ControlMaster, and terminals, app launches, audio,
# camera and notifications are extra channels multiplexed over it. One TCP
# connection, one key exchange, and nothing to reconnect per app.

OMARCHY_THIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/thin.conf"
OMARCHY_THIN_STATE="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-thin"
OMARCHY_THIN_CONTROL="$OMARCHY_THIN_STATE/ssh.sock"

# Commands that always run on this device: terminals, the session itself, and
# tools that drive this device's own hardware.
OMARCHY_THIN_LOCAL_DEFAULTS=(
  xdg-terminal-exec alacritty ghostty kitty foot wezterm
  uwsm uwsm-app hyprctl hyprpicker hyprlock hypridle hyprsunset
  quickshell qs walker
  wiremix pavucontrol impala nmtui nm-connection-editor bluetui blueberry blueman-manager
  wl-copy wl-paste grim slurp satty
  ssh waypipe
)

# Omarchy commands that act on the server: installing apps and web apps there.
OMARCHY_THIN_REMOTE_DEFAULTS=(
  "omarchy-install-*" "omarchy-pkg-*" "omarchy-webapp-*" "omarchy-tui-*" "omarchy-remove-*"
)

thin_load_config() {
  OMARCHY_THIN_SERVER=""
  OMARCHY_THIN_PORT=22
  OMARCHY_THIN_REMOTE_RUNTIME=""
  OMARCHY_THIN_COMPRESS="zstd=7"
  OMARCHY_THIN_GPU=0
  OMARCHY_THIN_AUDIO=opus
  OMARCHY_THIN_SPEAKER_BITRATE=96000
  OMARCHY_THIN_MIC_BITRATE=32000
  OMARCHY_THIN_CAMERA_DEVICE=/dev/video0
  OMARCHY_THIN_CAMERA_SIZE=1280x720
  OMARCHY_THIN_CAMERA_FPS=30
  OMARCHY_THIN_CAMERA_BITRATE=1500k
  OMARCHY_THIN_CAMERA_ENCODER=auto
  OMARCHY_THIN_LOCAL_APPS=()
  OMARCHY_THIN_REMOTE_APPS=()
  OMARCHY_THIN_LOCAL_SHELL=0

  if [[ -f $OMARCHY_THIN_CONFIG ]]; then
    source "$OMARCHY_THIN_CONFIG"
  fi

  if [[ -z $OMARCHY_THIN_SERVER ]]; then
    echo "No Omarchy server configured. Run: omarchy thin setup <user@server>" >&2
    return 1
  fi

  OMARCHY_THIN_SSH_OPTS=(
    -p "$OMARCHY_THIN_PORT"
    -o ControlPath="$OMARCHY_THIN_CONTROL"
    -o BatchMode=yes
    # Waypipe compresses window updates itself; compressing them again in SSH
    # only burns CPU on both ends.
    -o Compression=no
    # ChaCha20 is fast on ARM boards without AES instructions.
    -o Ciphers=chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
    -o IPQoS=lowdelay
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=8
  )
}

# Quote arguments for the remote shell that SSH hands its command line to.
thin_remote_command() {
  printf '%q ' "$@"
}

# Run a command on the server over the shared connection.
thin_ssh() {
  ssh "${OMARCHY_THIN_SSH_OPTS[@]}" -o ControlMaster=no "$@"
}

thin_connected() {
  ssh "${OMARCHY_THIN_SSH_OPTS[@]}" -O check "$OMARCHY_THIN_SERVER" >/dev/null 2>&1
}

# Wait for omarchy-thin-connect to bring the shared connection up.
thin_wait_connected() {
  local timeout=${1:-30} waited=0

  until thin_connected; do
    if (( waited >= timeout * 2 )); then
      return 1
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
}

thin_matches_any() {
  local name=$1 pattern
  shift

  for pattern in "$@"; do
    # Unquoted on purpose: the entries are glob patterns.
    # shellcheck disable=SC2053
    if [[ $name == $pattern ]]; then
      return 0
    fi
  done

  return 1
}

# Decide where a command runs. Prints "local" or "remote".
thin_command_location() {
  local name=${1##*/}

  if thin_matches_any "$name" "${OMARCHY_THIN_LOCAL_APPS[@]}"; then
    echo local
  elif thin_matches_any "$name" "${OMARCHY_THIN_REMOTE_APPS[@]}" "${OMARCHY_THIN_REMOTE_DEFAULTS[@]}"; then
    echo remote
  elif [[ $name == omarchy-* ]] || thin_matches_any "$name" "${OMARCHY_THIN_LOCAL_DEFAULTS[@]}"; then
    echo local
  else
    echo remote
  fi
}

# The first command in a terminal invocation like
#   bash -c "omarchy-show-logo; omarchy-install-foo; ..."
# which is how Omarchy's menu runs its setup and install flows.
thin_terminal_command_name() {
  local script

  if [[ ${1##*/} == "bash" && ${2:-} == "-c" ]]; then
    script=${3:-}
    script=${script#omarchy-show-logo; }
    read -r script _ <<<"$script"
    echo "${script%;}"
  else
    echo "${1:-}"
  fi
}

thin_notify_offline() {
  omarchy-notification-send -u critical -g 󰒍 "Not connected to the Omarchy server" "Check the network, or run: omarchy thin status" >/dev/null 2>&1 || true
}
