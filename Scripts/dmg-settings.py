"""Persist the installer layout without driving Finder or changing user defaults."""
import os

source = defines["source"]
format = "UDZO"
files = [os.path.join(source, name) for name in ("ScriptDeck.app", "Extras")]
symlinks = {"Applications": "/Applications"}
background = os.path.join(source, ".background", "installer.png")
icon = os.path.join(defines["root"], "Assets", "AppIcon.icns")
hide_extensions = ["ScriptDeck.app"]
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((100, 100), (720, 440))
icon_size = 88
text_size = 13
icon_locations = {
    "ScriptDeck.app": (180, 205),
    "Applications": (540, 205),
    "Extras": (360, 345),
}
