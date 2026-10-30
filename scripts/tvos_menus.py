"""Lets a controller move through the libultraship ports' settings menus on Apple TV.

The menus are nested ImGui child regions. A controller's D-pad stops at each region's border
until A enters it, so on Apple TV the menus seemed stuck. ImGuiChildFlags_NavFlattened lets focus
cross from region to region; every region in these menus resizes with ImGuiChildFlags_AutoResizeY,
so that is where the flag goes.
"""
FLAG = "ImGuiChildFlags_AutoResizeY"


def flatten(text, relative, script):
    """TEXT, a port's Menu.cpp, with its regions flattened for controller navigation."""
    if FLAG + " | ImGuiChildFlags_NavFlattened" in text:
        return text
    if text.count(FLAG) < 3:
        raise SystemExit(f"{script}: {relative} no longer builds its menu from {FLAG} regions")
    return text.replace(FLAG, FLAG + " | ImGuiChildFlags_NavFlattened")


def flatten_file(path, script):
    text = path.read_text()
    flat = flatten(text, path.name, script)
    if flat != text:
        path.write_text(flat)
