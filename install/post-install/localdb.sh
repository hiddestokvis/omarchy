# Update localdb so locate can find the installed system files immediately.
# Match the scheduled service while installation runs without a system manager.
# Thin client images have no plocate (omarchy-thin-base.packages): files live on the server.
omarchy-pkg-present plocate || return 0
updatedb --prune-bind-mounts=no --add-prunepaths=/.snapshots
