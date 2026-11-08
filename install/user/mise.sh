# Build the lazy shims for Omarchy's default tools and the account dispatchers,
# both declared by /etc/mise/conf.d, without resolving versions over the network.
# Thin client images have no mise (omarchy-thin-base.packages): tools run on the server.
omarchy-pkg-present mise-bin || return 0
MISE_OFFLINE=true mise reshim --system
MISE_OFFLINE=true mise reshim
