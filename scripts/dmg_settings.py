# dmgbuild settings: classic drag-to-Applications window. Used by scripts/release.sh.
import os
app = os.environ["S2T_APP"]
background = os.environ["S2T_DMG_BG"]
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
background = background
window_rect = ((200, 200), (600, 400))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {os.path.basename(app): (150, 190), "Applications": (450, 190)}
