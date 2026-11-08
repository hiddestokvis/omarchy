-- Thin client bindings, only on devices set up with omarchy-thin-install.
if os.getenv("OMARCHY_THIN") == "1" then
  o.bind("SUPER + CTRL + ALT + V", "Share camera with the Omarchy server", "omarchy-thin-camera toggle")
end
