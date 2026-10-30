"""Changes that build RT64 and N64ModernRuntime for tvOS, shared by the recompiled games that use
them (prepare-sote.py, prepare-racer.py). Each table maps a file inside that project to the
(old, new) replacements it gets; apply() stops when an upstream update changed an OLD text.
"""
from pathlib import Path

# Only what the tvOS build and the Mac's shader tools compile.
RT64_SUBMODULES = {
    ".": [f"src/contrib/{name}" for name in (
        "ddspp", "dxc", "hlslpp", "im3d", "imgui", "implot", "nativefiledialog-extended", "plume",
        "re-spirv", "spirv-cross", "stb", "xxHash", "zstd")],
    "src/contrib/plume": ["contrib/Vulkan-Headers", "contrib/VulkanMemoryAllocator", "contrib/volk"],
    "src/contrib/re-spirv": ["external/SPIRV-Headers"],
}
RUNTIME_SUBMODULES = {".": ["N64Recomp", "thirdparty/miniz", "thirdparty/o1heap", "thirdparty/xxHash"]}
# librecomp links this recompiler library; its live recompiler (sljit) is never built.
N64RECOMP_SUBMODULES = {".": ["lib/ELFIO", "lib/fmt", "lib/rabbitizer", "lib/sljit", "lib/tomlplusplus"]}

# plume's window code for tvOS, which replaces its AppKit src/contrib/plume/plume_apple.mm.
PLUME_APPLE = Path(__file__).resolve().parent.parent / "experiments/sote/plume_apple_tvos.mm"


def rt64(prefix):
    """RT64's changes. The including project sets PREFIX_HOST_TOOLS, the folder with the Mac builds
    of RT64's shader tools (experiments/sote/host-tools), and PREFIX_METAL_TARGET."""
    return {
        # RT64 cross-compiles for tvOS: its shader tools run on the Mac and its Metal shaders target
        # the tvOS SDK.
        "CMakeLists.txt": [
            ('    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")\n', ""),
            ("add_subdirectory(src/tools/file_to_c)\n",
             "add_executable(file_to_c IMPORTED GLOBAL)\n"
             f'set_target_properties(file_to_c PROPERTIES IMPORTED_LOCATION "${{{prefix}_HOST_TOOLS}}/file_to_c")\n'),
            # The file dialog only serves RT64's developer inspector; its Apple backend needs AppKit.
            ("add_subdirectory(src/contrib/nativefiledialog-extended)\n", ""),
            ("target_link_libraries(rt64 nfd)\n", ""),
            ("    find_package(SDL2 REQUIRED)\n", "    # Nativecade's shared runtime supplies SDL2_INCLUDE_DIRS.\n"),
            ("add_subdirectory(src/tools/texture_hasher)\nadd_subdirectory(src/tools/texture_packer)\n", ""),
            ("    add_subdirectory(src/tools/spirv_cross_msl)\n",
             "    add_executable(spirv_cross_msl IMPORTED GLOBAL)\n"
             f'    set_target_properties(spirv_cross_msl PROPERTIES IMPORTED_LOCATION "${{{prefix}_HOST_TOOLS}}/spirv_cross_msl")\n'),
            (' -framework IOKit"', '"'),
            ("COMMAND xcrun -sdk macosx metal -o ${OUTNAME}.ir -c ${OUTNAME}.metal",
             f"COMMAND xcrun -sdk ${{CMAKE_OSX_SYSROOT}} metal ${{{prefix}_METAL_TARGET}} -o ${{OUTNAME}}.ir -c ${{OUTNAME}}.metal"),
            ("COMMAND xcrun -sdk macosx metallib", "COMMAND xcrun -sdk ${CMAKE_OSX_SYSROOT} metallib"),
        ],
        # tvOS takes the iOS dialect of the Metal shading language.
        "src/tools/spirv_cross_msl/spirv_cross_msl.cpp": [
            ("        msl_options.argument_buffers = true;\n",
             "        msl_options.platform = spirv_cross::CompilerMSL::Options::iOS;\n"
             "        msl_options.argument_buffers = true;\n"),
        ],
        "src/apple/rt64_apple.mm": [("#import <AppKit/AppKit.h>\n", "")],
        # plume's Metal device takes its iOS path on tvOS too. Device locations and the device list are
        # macOS APIs (the list reached tvOS only in tvOS 18), so Apple TV uses its one built-in GPU.
        "src/contrib/plume/plume_metal.h": [
            ("#    define PLUME_IOS                    (TARGET_OS_IOS && !TARGET_OS_MACCATALYST)",
             "#    define PLUME_IOS                    (TARGET_OS_IPHONE && !TARGET_OS_MACCATALYST)"),
        ],
        "src/contrib/plume/plume_metal.cpp": [
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
        "src/contrib/hlslpp/include/hlsl++/platforms/scalar.h": [
            ("#include <math.h>\n#include <stdint.h>\n", "#include <math.h>\n#include <stdint.h>\n#include <stdlib.h>\n"),
        ],
    }


RUNTIME = {
    # The runtime reserves 4 GB of address space, so a stray game address faults instead of reaching
    # other memory. An Apple TV app may not have that much free in one piece; then it reserves the
    # game's memory only, without that guard.
    "librecomp/src/recomp.cpp": [
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
    ],
    # Code mods are compiled to native code while the game runs, which tvOS doesn't allow, so the
    # live recompiler isn't linked (experiments/sote/AppleTVStubs.cpp) and code mods fail to load.
    "librecomp/CMakeLists.txt": [
        ("target_link_libraries(librecomp PRIVATE ultramodern N64Recomp LiveRecomp)",
         "target_link_libraries(librecomp PRIVATE ultramodern N64Recomp)"),
    ],
    # The shared runtime already builds these header libraries for Torch and libultraship.
    "N64Recomp/CMakeLists.txt": [
        ("add_subdirectory(lib/fmt)\n", "if(NOT TARGET fmt)\n    add_subdirectory(lib/fmt)\nendif()\n"),
        ("add_subdirectory(lib/tomlplusplus)\n",
         "if(NOT TARGET tomlplusplus::tomlplusplus)\n    add_subdirectory(lib/tomlplusplus)\nendif()\n"),
    ],
}


def apply(root, table, script):
    """Applies TABLE's replacements to the files under ROOT. A "#" suffix on a key lets one file
    have several commented groups."""
    for key, replacements in table.items():
        relative = key.split("#")[0]
        path = root / relative
        text = path.read_text()
        for old, new in replacements:
            if old not in text:
                raise SystemExit(f"{script}: {old.strip()[:70]!r} is no longer in {relative}")
            text = text.replace(old, new)
        path.write_text(text)


def adapt(rt64_root, runtime_root, prefix, script):
    """All of the shared changes, plus plume's tvOS window code and the mod loader's live
    recompilation step, which experiments/sote/AppleTVStubs.cpp doesn't provide."""
    apply(rt64_root, rt64(prefix), script)
    apply(runtime_root, RUNTIME, script)
    (rt64_root / "src/contrib/plume/plume_apple.mm").write_bytes(PLUME_APPLE.read_bytes())
    mods = runtime_root / "librecomp/src/mods.cpp"
    text = mods.read_text()
    start = text.index("    N64Recomp::LiveGeneratorInputs recompiler_inputs{\n")
    end = text.index("    is_good = !errored && recompiler_output->good;\n", start)
    end += len("    is_good = !errored && recompiler_output->good;\n")
    mods.write_text(text[:start] + f"    // tvOS can't run code generated while the game runs ({script}).\n"
                    "    is_good = false;\n" + text[end:])
