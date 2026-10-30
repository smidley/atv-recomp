"""Prepare the pinned Shadows of the Empire recompilation for tvOS without reading any game ROM.

The game's own code is generated from the player's ROM by scripts/generate-sote-code.sh into
build/sote/source/generated, which this script keeps.
"""
import json
from pathlib import Path
import shutil
import subprocess

import rt64_tvos

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/sote-baseline.json").read_text())
source = root / "build/upstream/SotE-Recomp"
revision = pin["sources"]["sote"]["revision"]


def git(*args, cwd=source):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


if git("rev-parse", "HEAD") != revision:
    raise SystemExit("The SotE-Recomp checkout does not match the pinned revision.")
if git("status", "--porcelain"):
    raise SystemExit("Preserve the upstream checkout's local edits before preparing a generated copy.")

# Only what the tvOS build and the Mac's code generators compile, at the pinned commit's gitlinks.
SUBMODULES = {".": ["third_party/N64ModernRuntime", "third_party/N64Recomp", "third_party/rt64"]}
for base, table in (("third_party/rt64", rt64_tvos.RT64_SUBMODULES),
                    ("third_party/N64ModernRuntime", rt64_tvos.RUNTIME_SUBMODULES),
                    ("third_party/N64ModernRuntime/N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES),
                    ("third_party/N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES)):
    for parent, paths in table.items():
        SUBMODULES[base if parent == "." else f"{base}/{parent}"] = paths
for parent, paths in SUBMODULES.items():
    subprocess.check_call(["git", "submodule", "--quiet", "update", "--init", "--depth", "1", *paths],
                          cwd=source / parent)

destination = root / "build/sote/source"
destination.mkdir(parents=True, exist_ok=True)
for entry in destination.iterdir():
    if entry.name != "generated":
        shutil.rmtree(entry) if entry.is_dir() else entry.unlink()
# Clones share the checkout's blocks until a file changes, so the 250 MB RT64 tree copies instantly.
# Keeping modification times means a build only recompiles what the patches and changes below touch.
for name in ("src", "config", "tools", "patches", "third_party", "sote.toml", "LICENSE", "LICENSES.md"):
    subprocess.check_call(["cp", "-cRp", str(source / name), str(destination / name)])
# Git metadata in the copy would point back at the checkout's submodules.
for marker in destination.rglob(".git"):
    shutil.rmtree(marker) if marker.is_dir() else marker.unlink()

# SotE's own patches, in the order its build.ps1 applies them.
PATCHES = [
    ("third_party/N64ModernRuntime", "0001-n64modernruntime-sote-audio-fifo.patch"),
    ("third_party/N64ModernRuntime", "0004-n64modernruntime-alternate-rom-hashes.patch"),
    ("third_party/N64ModernRuntime", "0007-n64modernruntime-count-sign-extension.patch"),
    ("third_party/rt64", "0002-rt64-sote-f3dbeta.patch"),
    ("third_party/rt64", "0006-rt64-texture-slots-native-capture.patch"),
    ("third_party/rt64/src/contrib/plume", "0003-plume-d3d12-copy-sample-positions.patch"),
    ("third_party/rt64", "0008-rt64-present-diagnostics.patch"),
    ("third_party/rt64/src/contrib/plume", "0009-plume-vulkan-capture.patch"),
    ("third_party/rt64", "0011-rt64-pause-frame-and-textures.patch"),
]
for directory, patch in PATCHES:
    subprocess.check_call(["git", "apply", "--ignore-whitespace", "--unsafe-paths",
                           f"--directory={(destination / directory).relative_to(root)}",
                           str(destination / "patches" / patch)], cwd=root)


# SotE's own changes; rt64_tvos.py has those its runtime and renderer share with other games.
SWAPS = {
    # SotE's runtime frees the game's memory when the game ends, from what rt64_tvos.py reserved.
    "third_party/N64ModernRuntime/librecomp/src/recomp.cpp": [
        ("    free_failed = (munmap(rdram, allocation_size) == -1);",
         "    free_failed = (munmap(rdram, reserved) == -1);"),
    ],
    # SotE's SDL host code (the Linux build) with a Metal window: RT64 draws into the layer of an
    # SDL Metal view, which experiments/sote/plume_apple_tvos.mm reads.
    "src/main.cpp": [
        ("    if(smoke_test) return nullptr;\n    SDL_SetMainReady();\n",
         "    if(smoke_test) return {};\n    SDL_SetMainReady();\n"),
        ('        std::fprintf(stderr,"[sote] SDL video failed: %s\\n",SDL_GetError());\n        return nullptr;\n',
         '        std::fprintf(stderr,"[sote] SDL video failed: %s\\n",SDL_GetError());\n        return {};\n'),
        ("        SDL_WINDOW_VULKAN|SDL_WINDOW_RESIZABLE|(offscreen?SDL_WINDOW_HIDDEN:SDL_WINDOW_SHOWN));",
         "        SDL_WINDOW_METAL|SDL_WINDOW_FULLSCREEN|SDL_WINDOW_ALLOW_HIGHDPI|SDL_WINDOW_SHOWN);"),
        ('        std::fprintf(stderr,"[sote] SDL window failed: %s\\n",SDL_GetError());\n        return nullptr;\n',
         '        std::fprintf(stderr,"[sote] SDL window failed: %s\\n",SDL_GetError());\n        return {};\n'),
        ("        sote::graphics_menu::sync_display_resolution(display.w,display.h);\n    return graphics_window;\n",
         "        sote::graphics_menu::sync_display_resolution(display.w,display.h);\n"
         "    SDL_MetalView view=SDL_Metal_CreateView(graphics_window);\n"
         "    if(!view) {\n"
         '        std::fprintf(stderr,"[sote] SDL Metal view failed: %s\\n",SDL_GetError());\n'
         "        return {};\n"
         "    }\n"
         "    void* layer=SDL_Metal_GetLayer(view);\n"
         "    return {layer,layer};\n"),
    ],
    # On Apple TV the Siri Remote is a game controller too, and often the first one; SotE reads
    # only one controller, so it takes a gamepad when there is one.
    "src/frontend.cpp": [
        ("""    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {""",
         """    for (int pass = 0; pass < 2 && controller == nullptr; ++pass)
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        const char* name = SDL_GameControllerNameForIndex(i);
        if (SDL_IsGameController(i) && (pass == 1 || name == nullptr || std::strstr(name, "Remote") == nullptr)) {"""),
    ],
    # SotE sends the process's output to its own log files; in Nativecade that would capture every
    # later game's output too, so it only does that when asked.
    "src/main.cpp#logging": [
        ("        ((!smoke_test && !frontend_smoke_test) ||\n         std::getenv(\"SOTE_FORCE_FILE_LOG\") != nullptr)) {\n",
         "        std::getenv(\"SOTE_FORCE_FILE_LOG\") != nullptr) {\n"),
    ],
    "src/rt64_renderer.cpp": [
        ("        core.window = window_handle;\n", "        core.window = {window_handle.window, window_handle.view};\n"),
        ("RT64::UserConfiguration::GraphicsAPI::Vulkan;", "RT64::UserConfiguration::GraphicsAPI::Metal;"),
        ("selecting Vulkan (previous=%d)", "selecting Metal (previous=%d)"),
    ],
}

rt64_tvos.adapt(destination / "third_party/rt64", destination / "third_party/N64ModernRuntime", "RECOMPTV_SOTE",
                "prepare-sote.py")
rt64_tvos.apply(destination, SWAPS, "prepare-sote.py")
# Tables for experiments/n64interp, which runs the game's code from the ROM instead of compiling
# code generated from it. They come from SotE's configuration and symbol file only.
subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"), str(destination / "sote.toml"),
                       str(destination / "third_party/N64ModernRuntime/N64Recomp"), str(destination / "interpreter")])
print(f"Prepared Shadows of the Empire {pin['release']} ({revision[:12]}) in {destination.relative_to(root)}")
