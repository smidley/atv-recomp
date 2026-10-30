"""Prepare the pinned Star Wars Episode I: Racer recompilation for tvOS without reading any game ROM.

upstream/racer-baseline.json pins Racer and the runtime, renderer and recompiler forks it builds
with. This copies them to build/racer/source, applies the tvOS changes Racer shares with Shadows of
the Empire (rt64_tvos.py) and its own, and writes the tables experiments/n64interp runs the game's
code with. Racer's own build turns that code into C from the ROM; Nativecade interprets it from
the ROM in memory instead, so nothing here comes from a ROM.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess

import rt64_tvos

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/racer-baseline.json").read_text())
checkouts = {name: root / "build/upstream" / source.get("checkout", source["repository"].split("/")[1])
             for name, source in pin["sources"].items()}


def git(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


for name, path in checkouts.items():
    if git(path, "rev-parse", "HEAD") != pin["sources"][name]["revision"]:
        raise SystemExit(f"{path} doesn't match its pin; run scripts/upstream.py fetch.")
    if git(path, "status", "--porcelain"):
        raise SystemExit(f"Preserve {path}'s local edits before preparing a generated copy.")

# Only what the tvOS build compiles. The N64Recomp checkout is read for its lists of the libultra
# functions the runtime replaces; librecomp builds the runtime's own N64Recomp submodule.
for base, table in ((checkouts["rt64"], rt64_tvos.RT64_SUBMODULES),
                    (checkouts["N64ModernRuntime"], rt64_tvos.RUNTIME_SUBMODULES),
                    (checkouts["N64ModernRuntime"] / "N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES)):
    for parent, paths in table.items():
        subprocess.check_call(["git", "submodule", "--quiet", "update", "--init", "--depth", "1", *paths],
                              cwd=base / parent)

destination = root / "build/racer/source"
if destination.exists():
    shutil.rmtree(destination)
(destination / "racer").mkdir(parents=True)
# Clones share the checkouts' blocks until a file changes, and keeping modification times means a
# build only recompiles what the changes below touch.
racer = checkouts["racer"]
for name in ("src", "frontend", "recomp.toml", "symbols.toml", "LICENSE"):
    subprocess.check_call(["cp", "-cRp", str(racer / name), str(destination / "racer" / name)])
for name in ("N64ModernRuntime", "rt64"):
    subprocess.check_call(["cp", "-cRp", str(checkouts[name]), str(destination / name)])
# Git metadata in the copy would point back at the checkouts' submodules.
for marker in destination.rglob(".git"):
    shutil.rmtree(marker) if marker.is_dir() else marker.unlink()

rt64_tvos.adapt(destination / "rt64", destination / "N64ModernRuntime", "RECOMPTV_RACER", "prepare-racer.py")
rt64_tvos.apply(destination, {
    # Racer's SDL frontend: a full-screen window, whose Metal layer RT64 draws into (plume's tvOS
    # window code reads the layer), and a renderer that plays without RT64 in simulator smoke runs.
    "racer/frontend/src/app.cpp": [
        ('#include "internal.hpp"\n',
         '#include "internal.hpp"\n#include <TargetConditionals.h>\n'
         "#if TARGET_OS_SIMULATOR\n"
         "// experiments/racer/RacerGame.cpp: RT64 can't draw in the tvOS simulator.\n"
         "std::unique_ptr<ultramodern::renderer::RendererContext> nativecade_headless_renderer(uint8_t*,\n"
         "    ultramodern::renderer::WindowHandle, bool);\n"
         "#endif\n"),
        ("    Uint32 flags = SDL_WINDOW_RESIZABLE | (g_config.fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);\n",
         "    Uint32 flags = SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI;\n"),
        ("    SDL_MetalView view = SDL_Metal_CreateView(g_window);\n"
         "    return { wminfo.info.cocoa.window, SDL_Metal_GetLayer(view) };\n",
         "    void* layer = SDL_Metal_GetLayer(SDL_Metal_CreateView(g_window));\n"
         "    return { layer, layer };\n"),
        ("    cfg.renderer_callbacks.create_render_context = create_render_context;\n",
         "    cfg.renderer_callbacks.create_render_context = create_render_context;\n"
         "#if TARGET_OS_SIMULATOR\n"
         '    if (const char* s = env("HEADLESS_SMOKE"); s && *s == \'1\')\n'
         "        cfg.renderer_callbacks.create_render_context = nativecade_headless_renderer;\n"
         "#endif\n"),
        # The ROM is in the game folder, not beside the app (and the shared runtime's SDL leaves
        # out SDL_GetBasePath, which no other game uses).
        ("""    char* p = SDL_GetBasePath();
    if (!p) return std::filesystem::current_path();
    std::filesystem::path dir = std::filesystem::u8path(p);
    SDL_free(p);
    return dir;
""", "    return std::filesystem::current_path();\n"),
        # Nativecade returns to its library when a game ends, and quits SDL itself afterwards.
        ("    fflush(nullptr);\n    std::_Exit(0);\n}", "    fflush(nullptr);\n    return 0;\n}"),
    ],
    # RT64 keeps its data in the game folder, which is in Caches; Apple TV apps can't write elsewhere.
    "racer/frontend/src/rt64_context.cpp": [
        ("        app_config.detectDataPath = true;\n",
         '        app_config.dataPath = std::filesystem::current_path() / "rt64";\n'),
    ],
}, "prepare-racer.py")

# Tables for experiments/n64interp, from Racer's configuration and symbol file. Its section table
# (src/section_table.cpp, which its main.cpp registers) also names the functions N64Recomp split off
# at calls into other functions, and tools/post_recomp_patches.py sends two functions to host code.
table = (racer / "src/section_table.cpp").read_text()
base = int(re.search(r"(0x[0-9A-Fa-f]+),\s*// ram_addr", table).group(1), 16)
extras = [f"{name}@{base + int(offset, 16):X}"
          for name, offset in re.findall(r"\{ (\w+), (0x[0-9A-Fa-f]+), 0x[0-9A-Fa-f]+ \}", table)]
patches = (racer / "tools/post_recomp_patches.py").read_text()
redirects = re.findall(r'"(\w+)":\s*"(\w+)"', re.search(r"REDIRECTS = \{(.*?)\n\}", patches, re.S).group(1))
subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"), str(destination / "racer/recomp.toml"),
                       str(checkouts["N64Recomp"]), str(destination / "interpreter"),
                       *[f"{name}={target}" for name, target in redirects], *extras])
print(f"Prepared Star Wars Episode I: Racer {pin['release']} in {destination.relative_to(root)}")
