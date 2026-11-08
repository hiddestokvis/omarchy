-- Thin clients (omarchy-thin-install) are often old machines, like a 2010
-- iMac. Blur and shadows are the costly part of drawing a frame on old GPUs,
-- so they go; animations stay, as they are cheap and make the desktop feel
-- like Omarchy. ~/.config/hypr/looknfeel.lua loads later and can bring them back.
if os.getenv("OMARCHY_THIN") == "1" then
  hl.config({
    decoration = {
      blur = {
        enabled = false,
      },

      shadow = {
        enabled = false,
      },
    },
  })
end
