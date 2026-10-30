"""Prepare the pinned Super Smash Bros. port (BattleShip) for tvOS without changing its checkout
or reading any game ROM.

Writes the adapted sources to build/battleship/source and the support files the app bundles
(Fast3D shaders, Torch's extraction definitions, menu fonts) to RESOURCES, by default
build/battleship/NativecadeGame/BattleShip. The game's assets are extracted on the Apple TV
from the player's ROM (experiments/battleship/BattleShipRuntime.mm).

  python3 scripts/prepare-battleship.py [RESOURCES]
"""
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/battleship-baseline.json").read_text())
upstream = root / "build/upstream/BattleShip"
destination = root / "build/battleship/source"
resources = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "build/battleship/NativecadeGame/BattleShip"

# The release and its submodules, each checked out by scripts/upstream.py at its pin.
for source in pin["sources"].values():
    checkout = upstream / source.get("gitlink", "")
    git = ["git", "-C", str(checkout)]
    if subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip() != source["revision"]:
        raise SystemExit(f"{checkout} does not match the pinned BattleShip release; run scripts/upstream.py fetch.")
    if subprocess.check_output([*git, "status", "--porcelain", "--ignore-submodules=all"], text=True).strip():
        raise SystemExit(f"Preserve {checkout}'s local edits before preparing a generated copy.")


def swap(text, old, new, relative):
    """TEXT with every OLD replaced by NEW. Fails when an upstream update changed OLD."""
    if old not in text:
        raise SystemExit(f"prepare-battleship.py: {old.strip()[:70]!r} is no longer in {relative}")
    return text.replace(old, new)


TVOS_ONLY_ON_MAC = "#if defined(__APPLE__) && TARGET_OS_OSX"
# Each game expects a new process for each start; Nativecade starts it again in the same one
# (docs/GAME_SWITCHING.md). experiments/battleship/BattleShipRuntime.mm calls these after a game.
RESETS = {
    "port/gameloop.cpp": ("NativecadeBattleShipResetLoop", """\
    sGameCoroutine = NULL; // PortGameShutdown destroyed it
    sFrameCount = 0;
    sGbiTraceInitDone = 0; // register the trace callback with the next interpreter
    sDLSubmitsThisFrame = 0;
    sPendingDisplayList = nullptr; // points into game memory, which is reset before the next start
    sSimLoadStallFrames = 0;"""),
    # The cached fonts belong to the ImGui context that ended with the game.
    "port/gui/Menu.cpp": ("NativecadeBattleShipResetMenu", """\
    Ship::gMenuFonts.clear();
    Ship::gMenuFontsLoaded = false;"""),
}


def adapt(relative, text):
    if relative.startswith("libultraship/") and (relative.endswith(".cmake") or relative.endswith("CMakeLists.txt")):
        if relative == "libultraship/CMakeLists.txt":
            # Nativecade cross-compiles with CMake's own tvOS support, not the ios-cmake toolchain.
            text = swap(text, '    include(cmake/ios-toolchain-populate.cmake)\n', "", relative)
        if relative == "libultraship/src/CMakeLists.txt":
            text = swap(text, "    set_xcode_property(${PROJECT_NAME} PRODUCT_BUNDLE_IDENTIFIER ${BUNDLE_ID} All)\n", "", relative)
        if relative == "libultraship/cmake/dependencies/common.cmake":
            # tvOS has no IOKit HID, so the Raphnet adapter gets the no-op hidapi Android uses.
            text = swap(text, 'if (CMAKE_SYSTEM_NAME STREQUAL "Android")\n    set(_LUS_HIDAPI_STUB_DIR',
                        'if (CMAKE_SYSTEM_NAME MATCHES "^(Android|tvOS)$")\n    set(_LUS_HIDAPI_STUB_DIR', relative)
            # Metal only: no OpenGL backend for ImGui.
            text = swap(text, "    ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp\n", "", relative)
        # tvOS builds take libultraship's iOS paths.
        text = text.replace('CMAKE_SYSTEM_NAME STREQUAL "iOS"', 'CMAKE_SYSTEM_NAME MATCHES "^(iOS|tvOS)$"')
    if relative == "libultraship/src/ship/Context.cpp":
        # Apple TV apps keep files in Library/Caches; NativecadeRuntime.mm names the game's folder.
        text = swap(text, '#ifdef __IOS__\n    const char* home = getenv("HOME");',
                    '#ifdef __IOS__\n    if (const char* game = getenv("NATIVECADE_GAME_DIRECTORY")) return game;\n'
                    '    const char* home = getenv("HOME");', relative)
    if relative == "libultraship/src/ship/audio/Audio.cpp":
        # Core Audio's HAL player is macOS-only; tvOS uses the SDL backend.
        text = "#ifdef __APPLE__\n#include <TargetConditionals.h>\n#endif\n" + swap(text, "#ifdef __APPLE__", TVOS_ONLY_ON_MAC, relative)
    if relative == "libultraship/src/fast/backends/gfx_sdl2.cpp":
        text = swap(text, '#include "ship/utils/macUtils.h"',
                    '#include <TargetConditionals.h>\n#if TARGET_OS_OSX\n#include "ship/utils/macUtils.h"\n#endif', relative)
        text = swap(text, "#if defined(__APPLE__)\n    // Implement fullscreening with native macOS APIs",
                    TVOS_ONLY_ON_MAC + "\n    // Implement fullscreening with native macOS APIs", relative)
        text = swap(text, "#ifdef __APPLE__\n    auto nextFullscreenState = isNativeMacOSFullscreenActive(mWnd);",
                    TVOS_ONLY_ON_MAC + "\n    auto nextFullscreenState = isNativeMacOSFullscreenActive(mWnd);", relative)
        # UIKit owns the fullscreen surface, as in the shared libultraship (metal/tvos.patch).
        text = swap(text, "void GfxWindowBackendSDL2::SetFullscreenImpl(bool on, bool call_callback) {\n",
                    "void GfxWindowBackendSDL2::SetFullscreenImpl(bool on, bool call_callback) {\n"
                    "#if defined(__APPLE__) && TARGET_OS_TV\n"
                    "    const bool changed = !mFullScreen;\n    mFullScreen = true;\n"
                    "    if (changed && call_callback && mOnFullscreenChanged != nullptr) {\n"
                    "        mOnFullscreenChanged(true);\n    }\n    return;\n#endif\n", relative)
        # Nativecade quits SDL once the whole context is gone (metal/restart.patch).
        text = swap(text, "        mWnd = nullptr;\n    }\n    SDL_Quit();\n}",
                    "        mWnd = nullptr;\n    }\n}", relative)
    if relative == "libultraship/src/fast/backends/gfx_metal.cpp":
        # The tvOS simulator rejects depth clamping (as in the shared libultraship's rendering.patch).
        text = swap(text, '#include "fast/backends/gfx_metal.h"', '#include "fast/backends/gfx_metal.h"\n#include <TargetConditionals.h>', relative)
        text, count = re.subn(r"^( *)(\S+)->setDepthClipMode\(MTL::DepthClipModeClamp\);$",
                              r"#if !(TARGET_OS_TV && TARGET_OS_SIMULATOR)\n\1\2->setDepthClipMode(MTL::DepthClipModeClamp);\n#endif",
                              text, flags=re.M)
        if not count:
            raise SystemExit(f"prepare-battleship.py: setDepthClipMode is no longer in {relative}")
    if relative == "port/port.cpp":
        # Nativecade prepares BattleShip.o2r before Play (BattleShipRuntime.mm), so the first-run
        # extractor and its wizard, which run Torch as a separate process, are left out.
        text = swap(text, '#include "first_run.h"\n', "", relative)
        text = swap(text, "\t\tssb64::ExtractAssetsIfNeeded(targetO2r, /*silent=*/true);\n", "", relative)
        text = swap(text, "\t\t\tif (!ssb64::RunFirstRunWizard(targetO2r)) {\n\t\t\t\tport_log(\"SSB64: first-run wizard cancelled — exiting\\n\");",
                    "\t\t\t{\n\t\t\t\tport_log(\"SSB64: \" SSB64_O2R_NAME \" is missing; Nativecade prepares it before Play\\n\");", relative)
        # The game runs in its own folder; SDL_GetPrefPath shows a storage alert on tvOS.
        log = ('\t\tif (char* p = SDL_GetPrefPath(NULL, "BattleShip")) {\n\t\t\tlogPath = std::string(p) + "ssb64.log";\n'
               '\t\t\tSDL_free(p);\n\t\t} else {\n\t\t\tlogPath = "ssb64.log";  // last-resort cwd fallback\n\t\t}\n')
        text = swap(text, log, '#ifdef RECOMPTV_TVOS\n\t\tlogPath = "ssb64.log";\n#else\n' + log + "#endif\n", relative)
        # A macOS keyboard setting; it would only write into Nativecade's preferences.
        text = swap(text, "#ifdef __APPLE__\n\t/* Disable the macOS press-and-hold",
                    "#if defined(__APPLE__) && !defined(RECOMPTV_TVOS)\n\t/* Disable the macOS press-and-hold", relative)
    if relative == "port/port_save.cpp":
        # The save stays in the game's folder (Context, or the working directory); no SDL_GetPrefPath.
        prefs = '    if (char *p = SDL_GetPrefPath(NULL, "BattleShip")) {\n'
        text = swap(text, prefs, "#ifndef RECOMPTV_TVOS\n" + prefs, relative)
        text = swap(text, '        SDL_free(p);\n        return;\n    }\n', '        SDL_free(p);\n        return;\n    }\n#endif\n', relative)
    if relative == "port/gameloop.cpp":
        text = swap(text, "#if !defined(__ANDROID__)\n\tssb64::enhancements::TickDiscordPresence();",
                    "#if !defined(__ANDROID__) && !defined(RECOMPTV_TVOS)\n\tssb64::enhancements::TickDiscordPresence();", relative)
    if relative == "port/gui/PortMenu.cpp":
        # As on Android: no updater, Discord, shader-pack downloader, post-process picker,
        # windowed fullscreen or texture-dump tooling. The menu's Quit button stays.
        text = swap(text, "#if !defined(__ANDROID__)\n", "#if !defined(__ANDROID__) && !defined(RECOMPTV_TVOS)\n", relative)
    if relative == "port/port_watchdog.cpp":
        # The hang watchdog stays, but not its process-wide crash handlers: they would outlive the
        # game in Nativecade's process, and tvOS has no sigaltstack. Crashes go to the system's reports.
        text = swap(text, "    /* Alternate signal stack so", "#if !defined(RECOMPTV_TVOS)\n    /* Alternate signal stack so", relative)
        text = swap(text, "    sigaltstack(&ss, nullptr);\n", "    sigaltstack(&ss, nullptr);\n#endif\n", relative)
        text = swap(text, "    struct sigaction csa;\n", "#if !defined(RECOMPTV_TVOS)\n    struct sigaction csa;\n", relative)
        text = swap(text, "    sigaction(SIGABRT, &csa, nullptr);\n", "    sigaction(SIGABRT, &csa, nullptr);\n#endif\n", relative)
    if relative == "port/bridge/lbreloc_byteswap.cpp":
        # tvOS has no shell; this debug dump folder is made directly.
        text = "#include <sys/stat.h>\n" + swap(text, '\tstd::system("mkdir -p tex_dump");', '\tmkdir("tex_dump", 0755);', relative)
    if relative in RESETS:
        name, body = RESETS[relative]
        text += f'\n// Generated by scripts/prepare-battleship.py for Nativecade.\nextern "C" void {name}(void) {{\n{body}\n}}\n'
    return text


written = set()


def write(target, data):
    """Write DATA unless TARGET already holds it, keeping rebuilds small."""
    written.add(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_bytes() != data:
        target.write_bytes(data)


# The game, its port layer and both forked libraries. The decomp's relocData/ (decompiled data,
# 56 MB) is only used by an optional upstream pipeline; the game loads that data from the
# extracted BattleShip.o2r instead.
folders = ["port", "include", "debug_tools/acmd_trace", "debug_tools/gbi_trace", "decomp/include", "decomp/src",
           "libultraship", "torch"]
for folder in folders:
    for original in sorted((upstream / folder).rglob("*")):
        relative = original.relative_to(upstream).as_posix()
        if (not original.is_file() or "/.git" in f"/{relative}" or relative.startswith("decomp/src/relocData/")
                or re.match(r"(libultraship/tests|torch/test)/", relative)):
            continue
        data = original.read_bytes()
        if original.suffix in {".c", ".cpp", ".h", ".hpp", ".mm", ".cmake", ".txt", ".patch"}:
            text = data.decode("utf-8", "surrogateescape")
            data = adapt(relative, text).encode("utf-8", "surrogateescape")
        write(destination / relative, data)

# Upstream's build encodes the staff roll from the decomp's own credits text (GenerateCreditsAssets).
with tempfile.TemporaryDirectory() as scratch:
    for name in ("staff", "titles", "info", "companies"):
        shutil.copy2(upstream / f"decomp/src/credits/{name}.credits.us.txt", scratch)
    for arguments in (["staff.credits.us.txt"], ["titles.credits.us.txt"],
                      ["-paragraphFont", "-multiline", "info.credits.us.txt"], ["-paragraphFont", "companies.credits.us.txt"]):
        subprocess.run([sys.executable, "-I", str(upstream / "tools/creditsTextConverter.py"), *arguments],
                       cwd=scratch, check=True, stdout=subprocess.DEVNULL)
    for output in Path(scratch).glob("*.credits.*"):
        if output.suffix in {".encoded", ".metadata"}:
            write(destination / "decomp/src/credits" / output.name, output.read_bytes())


def png_rgba(path):
    """Width, height and RGBA bytes of a non-interlaced 8-bit RGBA PNG (the port's arrow art)."""
    data = path.read_bytes()
    width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", data[16:29])
    if (depth, color, interlace) != (8, 6, 0):
        raise SystemExit(f"{path.name} is no longer an 8-bit RGBA PNG")
    compressed, offset = b"", 8
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if kind == b"IDAT":
            compressed += data[offset + 8:offset + 8 + length]
        offset += 12 + length
    raw, stride, rows, previous = zlib.decompress(compressed), width * 4, [], bytearray(width * 4)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a, b, c = line[x - 4] if x >= 4 else 0, previous[x], previous[x - 4] if x >= 4 else 0
            p = a + b - c
            line[x] = (line[x] + (0, a, b, (a + b) // 2,
                                  a if abs(p - a) <= abs(p - b) and abs(p - a) <= abs(p - c) else b if abs(p - b) <= abs(p - c) else c)[kind]) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, b"".join(rows)


# Upstream bakes the stage-select scroll arrows (its own artwork) into headers with Pillow
# (tools/png_to_c_array.py); this writes the same big-endian RGBA16 arrays without it.
arrows = {}
for name, symbol in (("arrow", "Arrow"), ("arrow_left", "ArrowLeft")):
    width, height, rgba = arrows[name] = png_rgba(upstream / f"port/assets/css_icons/{name}.png")
    pixels = [((r >> 3) << 11) | ((g >> 3) << 6) | ((b >> 3) << 1) | (a >> 7) for r, g, b, a in struct.iter_unpack("4B", rgba)]
    body = ",\n    ".join(", ".join(f"0x{v >> 8:02x}, 0x{v & 255:02x}" for v in pixels[i:i + 16]) for i in range(0, len(pixels), 16))
    write(destination / f"generated/{name}_data.h", (
        f"// Generated by scripts/prepare-battleship.py from port/assets/css_icons/{name}.png.\n#pragma once\n\n"
        f"static const int k{symbol}Width  = {width};\nstatic const int k{symbol}Height = {height};\n"
        f"static const unsigned char k{symbol}RGBA16[{width * height * 2}] = {{\n    {body}\n}};\n").encode())
# The left arrow is the right one mirrored (tools/generate_arrow_svg.py --mirror): a check on the decoder.
width, height, right = arrows["arrow"]
mirrored = b"".join(right[(y * width + x) * 4:(y * width + x) * 4 + 4] for y in range(height) for x in reversed(range(width)))
assert mirrored == arrows["arrow_left"][2], "PNG decoding no longer matches the arrow art"
# Files an earlier release had would otherwise still be compiled (CMake globs these folders).
for stale in [path for path in destination.rglob("*") if path.is_file() and path not in written]:
    stale.unlink()

# Support files the app bundles. Torch reads config.yml and the US extraction definitions on the
# Apple TV; f3d.o2r holds the Fast3D shaders of BattleShip's own libultraship, as upstream packs it.
if resources.exists():
    shutil.rmtree(resources)
(resources / "yamls").mkdir(parents=True)
shutil.copytree(upstream / "yamls/us", resources / "yamls/us")
shutil.copy2(upstream / "config.yml", resources / "config.yml")
shutil.copytree(upstream / "assets/custom/fonts", resources / "assets/custom/fonts")
shaders = destination / "libultraship/src/fast/shaders"
with zipfile.ZipFile(resources / "f3d.o2r", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(shaders.rglob("*")):
        if path.is_file():
            archive.write(path, "shaders/" + path.relative_to(shaders).as_posix())
for path in resources.rglob("*"):
    if path.suffix.lower() in {".z64", ".n64", ".v64", ".o2r"} and path.name != "f3d.o2r":
        raise SystemExit("Refusing to package game data.")
shutil.copy2(upstream / "LICENSE", resources / "LICENSE.txt")
(resources / "Upstream.txt").write_text(
    f"BattleShip {pin['release']} by JRickey\nhttps://github.com/JRickey/BattleShip\n"
    + "\n".join(f"{source['repository']} {source['revision']}" for source in pin["sources"].values())
    + "\nMenu fonts: Montserrat and Inconsolata (SIL Open Font License, see assets/custom/fonts).\n"
    "No Super Smash Bros. ROM or extracted BattleShip.o2r is included.\n")
print(f"Prepared BattleShip {pin['release']} in {destination} and {resources}")
