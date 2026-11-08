# Shared helpers for the omarchy-thin-* commands. Sourced, not executed.
#
# A thin client is an appliance: the local `thin` account logs in on its own
# and shows the sign-in screen, and whoever signs in gets their persistent
# desktop from the Omarchy server. Every stream rides one SSH connection,
# opened at sign-in as the ControlMaster: the wprs display, terminals, app
# launches, audio, camera and notifications are channels multiplexed over it.

OMARCHY_THIN_ETC=${OMARCHY_THIN_ETC:-/etc/omarchy-thin}
OMARCHY_THIN_CONFIG="$OMARCHY_THIN_ETC/thin.conf"
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
  ssh wprsc
)

# Omarchy commands that act on the server: installing apps and web apps there.
OMARCHY_THIN_REMOTE_DEFAULTS=(
  "omarchy-install-*" "omarchy-pkg-*" "omarchy-webapp-*" "omarchy-tui-*" "omarchy-remove-*"
)

# Loads the device settings. Returns 1 when the device is not a thin client.
thin_load_config() {
  OMARCHY_THIN_SERVER=""
  OMARCHY_THIN_PORT=22
  OMARCHY_THIN_SPEAKER_BITRATE=96000
  OMARCHY_THIN_MIC_BITRATE=32000
  OMARCHY_THIN_AUDIO=opus
  OMARCHY_THIN_CAMERA_DEVICE=/dev/video0
  OMARCHY_THIN_CAMERA_SIZE=1280x720
  OMARCHY_THIN_CAMERA_FPS=30
  OMARCHY_THIN_CAMERA_BITRATE=1500k
  OMARCHY_THIN_CAMERA_ENCODER=auto
  OMARCHY_THIN_LOCAL_APPS=()
  OMARCHY_THIN_REMOTE_APPS=()

  if [[ -f $OMARCHY_THIN_CONFIG ]]; then
    source "$OMARCHY_THIN_CONFIG"
  fi

  if [[ -z $OMARCHY_THIN_SERVER ]]; then
    echo "This device is not a thin client. Set it up with: omarchy thin install <server>" >&2
    return 1
  fi

  # The server account is only known once someone has signed in.
  OMARCHY_THIN_USER=""
  if [[ -f $OMARCHY_THIN_STATE/user ]]; then
    read -r OMARCHY_THIN_USER <"$OMARCHY_THIN_STATE/user"
  fi
  OMARCHY_THIN_DESTINATION="${OMARCHY_THIN_USER:-nobody}@$OMARCHY_THIN_SERVER"

  OMARCHY_THIN_SSH_OPTS=(
    -F none
    -p "$OMARCHY_THIN_PORT"
    -o ControlPath="$OMARCHY_THIN_CONTROL"
    # The device key proves this is an enrolled thin client; the person's
    # password, asked at sign-in, proves who is using it.
    -o IdentityFile="$OMARCHY_THIN_ETC/device_key"
    -o IdentitiesOnly=yes
    # The server's host key was pinned when the device was installed.
    -o UserKnownHostsFile="$OMARCHY_THIN_ETC/known_hosts"
    -o StrictHostKeyChecking=yes
    -o HostKeyAlias=omarchy-server
    # wprs compresses the display itself; compressing it again in SSH only
    # burns CPU on both ends.
    -o Compression=no
    # ChaCha20 is fast on CPUs without AES instructions.
    -o Ciphers=chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
    -o IPQoS=lowdelay
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=3
  )
}

# Quote arguments for the remote shell that SSH hands its command line to.
thin_remote_command() {
  printf '%q ' "$@"
}

# Run a command on the server over the signed-in connection. Never opens a
# connection of its own: without a signed-in session there is nobody to be.
thin_ssh() {
  ssh "${OMARCHY_THIN_SSH_OPTS[@]}" -o ControlMaster=no -o BatchMode=yes "$@"
}

thin_connected() {
  [[ -S $OMARCHY_THIN_CONTROL ]] &&
    ssh "${OMARCHY_THIN_SSH_OPTS[@]}" -O check "$OMARCHY_THIN_DESTINATION" >/dev/null 2>&1
}

# Wait for the signed-in connection.
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
  omarchy-notification-send -u critical -g 󰒍 "Not signed in to the Omarchy server" "Sign in again, or run: omarchy thin status" >/dev/null 2>&1 || true
}
