"""Prepare the pinned Shadows of the Empire recompilation for tvOS without reading any game ROM.

The game's own code is generated from the player's ROM by scripts/generate-sote-code.sh into
build/sote/source/generated, which this script keeps.
"""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/sote-baseline.json").read_text())
source = root / "build/upstream/SotE-Recomp"
revision = pin["sources"]["sote"]["revision"]
experiment = root / "experiments/sote"


def git(*args, cwd=source):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


if git("rev-parse", "HEAD") != revision:
    raise SystemExit("The SotE-Recomp checkout does not match the pinned revision.")
if git("status", "--porcelain"):
    raise SystemExit("Preserve the upstream checkout's local edits before preparing a generated copy.")

# Only what the tvOS build and the Mac's code generators compile, at the pinned commit's gitlinks.
SUBMODULES = {
    ".": ["third_party/N64ModernRuntime", "third_party/N64Recomp", "third_party/rt64"],
    "third_party/N64ModernRuntime": ["N64Recomp", "thirdparty/miniz", "thirdparty/o1heap", "thirdparty/xxHash"],
    "third_party/N64Recomp": ["lib/ELFIO", "lib/fmt", "lib/rabbitizer", "lib/sljit", "lib/tomlplusplus"],
    # librecomp links this copy's recompiler library; its live recompiler (sljit) is never built.
    "third_party/N64ModernRuntime/N64Recomp": ["lib/ELFIO", "lib/fmt", "lib/rabbitizer", "lib/sljit", "lib/tomlplusplus"],
    "third_party/rt64": [f"src/contrib/{name}" for name in (
        "ddspp", "dxc", "hlslpp", "im3d", "imgui", "implot", "nativefiledialog-extended", "plume",
        "re-spirv", "spirv-cross", "stb", "xxHash", "zstd")],
    "third_party/rt64/src/contrib/plume": ["contrib/Vulkan-Headers", "contrib/VulkanMemoryAllocator", "contrib/volk"],
    "third_party/rt64/src/contrib/re-spirv": ["external/SPIRV-Headers"],
}
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


def swap(text, old, new, relative):
    """TEXT with OLD replaced by NEW. Fails when an upstream update changed OLD."""
    if old not in text:
        raise SystemExit(f"prepare-sote.py: {old.strip()[:70]!r} is no longer in {relative}")
    return text.replace(old, new)


SWAPS = {
    # RT64 cross-compiles for tvOS: its shader tools run on the Mac (experiments/sote/host-tools,
    # built by build-nativecade-runtime.sh) and its Metal shaders target the tvOS SDK.
    "third_party/rt64/CMakeLists.txt": [
        ('    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")\n', ""),
        ("add_subdirectory(src/tools/file_to_c)\n",
         "add_executable(file_to_c IMPORTED GLOBAL)\n"
         'set_target_properties(file_to_c PROPERTIES IMPORTED_LOCATION "${RECOMPTV_SOTE_HOST_TOOLS}/file_to_c")\n'),
        # The file dialog only serves RT64's developer inspector; its Apple backend needs AppKit.
        ("add_subdirectory(src/contrib/nativefiledialog-extended)\n", ""),
        ("target_link_libraries(rt64 nfd)\n", ""),
        ("    find_package(SDL2 REQUIRED)\n", "    # Nativecade's shared runtime supplies SDL2_INCLUDE_DIRS.\n"),
        ("add_subdirectory(src/tools/texture_hasher)\nadd_subdirectory(src/tools/texture_packer)\n", ""),
        ("    add_subdirectory(src/tools/spirv_cross_msl)\n",
         "    add_executable(spirv_cross_msl IMPORTED GLOBAL)\n"
         '    set_target_properties(spirv_cross_msl PROPERTIES IMPORTED_LOCATION "${RECOMPTV_SOTE_HOST_TOOLS}/spirv_cross_msl")\n'),
        (' -framework IOKit"', '"'),
        ("COMMAND xcrun -sdk macosx metal -o ${OUTNAME}.ir -c ${OUTNAME}.metal",
         "COMMAND xcrun -sdk ${CMAKE_OSX_SYSROOT} metal ${RECOMPTV_SOTE_METAL_TARGET} -o ${OUTNAME}.ir -c ${OUTNAME}.metal"),
        ("COMMAND xcrun -sdk macosx metallib", "COMMAND xcrun -sdk ${CMAKE_OSX_SYSROOT} metallib"),
    ],
    # tvOS takes the iOS dialect of the Metal shading language.
    "third_party/rt64/src/tools/spirv_cross_msl/spirv_cross_msl.cpp": [
        ("        msl_options.argument_buffers = true;\n",
         "        msl_options.platform = spirv_cross::CompilerMSL::Options::iOS;\n"
         "        msl_options.argument_buffers = true;\n"),
    ],
    "third_party/rt64/src/apple/rt64_apple.mm": [("#import <AppKit/AppKit.h>\n", "")],
    # plume's Metal device takes its iOS path on tvOS too. Device locations and the device list are
    # macOS APIs (the list reached tvOS only in tvOS 18), so Apple TV uses its one built-in GPU.
    "third_party/rt64/src/contrib/plume/plume_metal.h": [
        ("#    define PLUME_IOS                    (TARGET_OS_IOS && !TARGET_OS_MACCATALYST)",
         "#    define PLUME_IOS                    (TARGET_OS_IPHONE && !TARGET_OS_MACCATALYST)"),
    ],
    "third_party/rt64/src/contrib/plume/plume_metal.cpp": [
        ("""        NS::Array* devices = MTL::CopyAllDevices();
        MTL::Device *preferredDevice = nullptr;
        for (NS::UInteger i = 0; i < devices->count(); i++) {""",
         """#if PLUME_IOS
        MTL::Device *preferredDevice = nullptr;
#else
        NS::Array* devices = MTL::CopyAllDevices();
        MTL::Device *preferredDevice = nullptr;
        for (NS::UInteger i = 0; i < devices->count(); i++) {"""),
        ("""        mtl = preferredDevice ? preferredDevice : MTL::CreateSystemDefaultDevice();
        mtl->retain();
        devices->release();
""", """#endif
        mtl = preferredDevice ? preferredDevice : MTL::CreateSystemDefaultDevice();
        mtl->retain();
#if !PLUME_IOS
        devices->release();
#endif
"""),
        ("        description.type = mapDeviceType(mtl->location());\n",
         "#if PLUME_IOS\n        description.type = RenderDeviceType::INTEGRATED;\n#else\n"
         "        description.type = mapDeviceType(mtl->location());\n#endif\n"),
        ("""        const NS::Array* devices = MTL::CopyAllDevices();
        for (NS::UInteger i = 0; i < devices->count(); i++) {
            NS::String* deviceName = ((MTL::Device *)devices->object(i))->name();
            deviceNames.push_back(std::string(deviceName->utf8String()));
        }
""", """#if PLUME_IOS
        MTL::Device *device = MTL::CreateSystemDefaultDevice();
        deviceNames.push_back(std::string(device->name()->utf8String()));
        device->release();
#else
        const NS::Array* devices = MTL::CopyAllDevices();
        for (NS::UInteger i = 0; i < devices->count(); i++) {
            NS::String* deviceName = ((MTL::Device *)devices->object(i))->name();
            deviceNames.push_back(std::string(deviceName->utf8String()));
        }
#endif
"""),
        # RT64 times frames with GPU timestamps. The tvOS simulator has no timestamp counters, so
        # there is no sample buffer to write or read; report zero times instead of crashing.
        ("        MetalAutoreleasePool releasePool;\n        sampleBuffer->release();\n",
         "        MetalAutoreleasePool releasePool;\n        if (sampleBuffer != nullptr) sampleBuffer->release();\n"),
        ("""        const NS::Data* data = sampleBuffer->resolveCounterRange(NS::Range(0, results.size()));
        std::memcpy(results.data(), data->mutableBytes(), results.size() * sizeof(uint64_t));""",
         """        const NS::Data* data = sampleBuffer ? sampleBuffer->resolveCounterRange(NS::Range(0, results.size())) : nullptr;
        if (data == nullptr || data->length() < results.size() * sizeof(uint64_t)) {
            std::fill(results.begin(), results.end(), 0);
            return;
        }
        std::memcpy(results.data(), data->mutableBytes(), results.size() * sizeof(uint64_t));"""),
        ("""        const MetalQueryPool *interfaceQueryPool = static_cast<const MetalQueryPool *>(queryPool);
""", """        const MetalQueryPool *interfaceQueryPool = static_cast<const MetalQueryPool *>(queryPool);
        if (interfaceQueryPool->sampleBuffer == nullptr) return;
"""),
    ],
    # RT64 uses hlslpp's scalar code on Apple silicon, which calls labs without declaring it.
    "third_party/rt64/src/contrib/hlslpp/include/hlsl++/platforms/scalar.h": [
        ("#include <math.h>\n#include <stdint.h>\n", "#include <math.h>\n#include <stdint.h>\n#include <stdlib.h>\n"),
    ],
    # Code mods are compiled to native code while the game runs, which tvOS doesn't allow, so the
    # live recompiler isn't linked (experiments/sote/AppleTVStubs.cpp) and code mods fail to load.
    # The runtime reserves 4 GB of address space, so a stray game address faults instead of reaching
    # other memory. An Apple TV app may not have that much free in one piece; then it reserves the
    # 512 MB the game uses, without that guard.
    "third_party/N64ModernRuntime/librecomp/src/recomp.cpp": [
        ("""    rdram = (uint8_t*)mmap(NULL, allocation_size, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
    alloc_failed = rdram == reinterpret_cast<uint8_t*>(MAP_FAILED);
    if (!alloc_failed) {
        // mprotect returns -1 on failure.
        alloc_failed = (mprotect(rdram, mem_size, PROT_READ | PROT_WRITE) == -1);
        if (alloc_failed) {
            munmap(rdram, allocation_size);""",
         """    size_t reserved = allocation_size;
    rdram = (uint8_t*)mmap(NULL, reserved, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (rdram == reinterpret_cast<uint8_t*>(MAP_FAILED)) {
        reserved = mem_size;
        rdram = (uint8_t*)mmap(NULL, reserved, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
    }
    alloc_failed = rdram == reinterpret_cast<uint8_t*>(MAP_FAILED);
    if (!alloc_failed) {
        // mprotect returns -1 on failure.
        alloc_failed = (mprotect(rdram, mem_size, PROT_READ | PROT_WRITE) == -1);
        if (alloc_failed) {
            munmap(rdram, reserved);"""),
        ("    free_failed = (munmap(rdram, allocation_size) == -1);",
         "    free_failed = (munmap(rdram, reserved) == -1);"),
    ],
    "third_party/N64ModernRuntime/librecomp/CMakeLists.txt": [
        ("target_link_libraries(librecomp PRIVATE ultramodern N64Recomp LiveRecomp)",
         "target_link_libraries(librecomp PRIVATE ultramodern N64Recomp)"),
    ],
    # The shared runtime already builds these header libraries for Torch and libultraship.
    "third_party/N64ModernRuntime/N64Recomp/CMakeLists.txt": [
        ("add_subdirectory(lib/fmt)\n", "if(NOT TARGET fmt)\n    add_subdirectory(lib/fmt)\nendif()\n"),
        ("add_subdirectory(lib/tomlplusplus)\n",
         "if(NOT TARGET tomlplusplus::tomlplusplus)\n    add_subdirectory(lib/tomlplusplus)\nendif()\n"),
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

# The mod loader's live recompilation step, which AppleTVStubs.cpp doesn't provide.
mods = destination / "third_party/N64ModernRuntime/librecomp/src/mods.cpp"
text = mods.read_text()
start = text.index("    N64Recomp::LiveGeneratorInputs recompiler_inputs{\n")
end = text.index("    is_good = !errored && recompiler_output->good;\n", start)
end += len("    is_good = !errored && recompiler_output->good;\n")
mods.write_text(text[:start] + "    // tvOS can't run code generated while the game runs (prepare-sote.py).\n    is_good = false;\n" + text[end:])
for key, replacements in SWAPS.items():
    relative = key.split("#")[0]  # a "#" suffix lets one file have several commented groups
    path = destination / relative
    text = path.read_text()
    for old, new in replacements:
        text = swap(text, old, new, relative)
    path.write_text(text)
shutil.copyfile(experiment / "plume_apple_tvos.mm", destination / "third_party/rt64/src/contrib/plume/plume_apple.mm")
# Tables for experiments/n64interp, which runs the game's code from the ROM instead of compiling
# code generated from it. They come from SotE's configuration and symbol file only.
subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"), str(destination / "sote.toml"),
                       str(destination / "third_party/N64ModernRuntime/N64Recomp"), str(destination / "interpreter")])
print(f"Prepared Shadows of the Empire {pin['release']} ({revision[:12]}) in {destination.relative_to(root)}")
