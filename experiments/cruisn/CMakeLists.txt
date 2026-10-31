cmake_minimum_required(VERSION 3.20)
# Cruis'n USA and Cruis'n World, as NativecadeCruisn.framework. They build on the runtime, renderer
# and frontend Racer builds, with navjack's patches (scripts/prepare-cruisn.py), so this is a project
# of its own like Racer's: build-nativecade-runtime.sh runs it after the shared runtime, whose
# framework supplies SDL (RECOMPTV_RUNTIME_BUILD). Both games' code and audio microcode run through
# experiments/n64interp from the player's ROM, with tables prepare-cruisn.py writes from navjack's
# configurations, so nothing in the build comes from a ROM. Without a prepared copy
# (RECOMPTV_CRUISN_SOURCE), the framework only reports that this build doesn't include the games.
project(NativecadeCruisn LANGUAGES C CXX OBJC OBJCXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(cruisn "${RECOMPTV_CRUISN_SOURCE}")
if(NOT cruisn OR NOT EXISTS "${cruisn}/usa/interpreter/n64interp_game.c")
    add_library(NativecadeCruisn SHARED CruisnUnavailable.cpp)
else()
# The games, N64ModernRuntime and RT64 have hidden symbols; SDL comes from the shared runtime.
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_OBJC_VISIBILITY_PRESET hidden)
set(CMAKE_OBJCXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
file(GLOB sdl_config "${RECOMPTV_RUNTIME_BUILD}/_deps/sdl2-build/include-config-*/SDL2")
set(SDL2_INCLUDE_DIRS "${RECOMPTV_RUNTIME_BUILD}/_deps/sdl2-build/include"
    "${RECOMPTV_RUNTIME_BUILD}/_deps/sdl2-build/include/SDL2" ${sdl_config})
add_library(SDL2::SDL2 INTERFACE IMPORTED)
set_target_properties(SDL2::SDL2 PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SDL2_INCLUDE_DIRS}")

# RT64 compiles its shaders while it builds, with Racer's Mac shader tools (the same RT64;
# RECOMPTV_CRUISN_HOST_TOOLS), and the Metal compiler targets this SDK.
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(RECOMPTV_CRUISN_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET}-simulator)
else()
    set(RECOMPTV_CRUISN_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET})
endif()
set(RT64_STATIC TRUE)
set(RT64_DIR "${cruisn}/rt64")
set(N64_MODERN_RUNTIME_DIR "${cruisn}/N64ModernRuntime")
add_subdirectory("${RT64_DIR}" rt64)
# As Racer's: ImGui's Metal backend classes get names no other framework in the app uses.
set_source_files_properties("${RT64_DIR}/src/contrib/imgui/backends/imgui_impl_metal.mm" TARGET_DIRECTORY rt64
    PROPERTIES COMPILE_DEFINITIONS
    "MetalBuffer=CruisnImGuiMetalBuffer;FramebufferDescriptor=CruisnImGuiFramebufferDescriptor;MetalContext=CruisnImGuiMetalContext;MetalTexture=CruisnImGuiMetalTexture")
add_subdirectory("${N64_MODERN_RUNTIME_DIR}" runtime)
# Game code reaches hardware registers (0xA4000000 and up) and the cartridge window (0xB0000000) as
# memory past KSEG0; this keeps those accesses in scratch memory instead of faulting.
target_compile_definitions(librecomp PUBLIC RECOMP_MEM_SIZE_MB=1024)
add_subdirectory("${cruisn}/frontend" frontend)

# Each game's code, interpreted from RDRAM, and its tables. The generated names start with the
# game's prefix, so both games fit in one framework.
add_library(NativecadeCruisnGameCode OBJECT "${CMAKE_CURRENT_LIST_DIR}/../n64interp/N64Interpreter.cpp"
    "${cruisn}/usa/interpreter/n64interp_game.c" "${cruisn}/world/interpreter/n64interp_game.c")
target_include_directories(NativecadeCruisnGameCode PRIVATE "${N64_MODERN_RUNTIME_DIR}/N64Recomp/include"
    "${CMAKE_CURRENT_LIST_DIR}/../n64interp")
# navjack's N64Recomp keeps all of COP0 in the context; the hooks' host functions are in CruisnHooks.h.
target_compile_definitions(NativecadeCruisnGameCode PRIVATE N64INTERP_COP0_REGISTERS)
target_compile_options(NativecadeCruisnGameCode PRIVATE -fno-strict-aliasing
    "$<$<COMPILE_LANGUAGE:C>:SHELL:-include ${CMAKE_CURRENT_LIST_DIR}/CruisnHooks.h>")
set_target_properties(NativecadeCruisnGameCode PROPERTIES C_STANDARD 17)
foreach(game usa world)
    add_library(NativecadeCruisn_${game}_tables OBJECT CruisnTables.cpp)
    target_include_directories(NativecadeCruisn_${game}_tables PRIVATE "${cruisn}/${game}/interpreter")
    target_compile_definitions(NativecadeCruisn_${game}_tables PRIVATE CRUISN_GAME=cruisn_${game}_)
    target_link_libraries(NativecadeCruisn_${game}_tables PRIVATE librecomp ultramodern N64Recomp)
endforeach()

# The host program, the audio microcode, navjack's Controller Pak and what Apple TV leaves out.
add_library(NativecadeCruisnObjects OBJECT CruisnGame.cpp CruisnRuntime.mm
    "${CMAKE_CURRENT_LIST_DIR}/../racer/HeadlessRenderer.cpp" "${CMAKE_CURRENT_LIST_DIR}/../n64interp/N64RspInterpreter.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../sote/AppleTVStubs.cpp" "${cruisn}/native/controller_pak.cpp")
add_dependencies(NativecadeCruisnObjects rt64)
# SDL_MAIN_HANDLED stops SDL's tvOS header from renaming main to SDL_main; RT64's headers expect the rest.
target_compile_definitions(NativecadeCruisnObjects PRIVATE SDL_MAIN_HANDLED NOMINMAX HLSL_CPU FFX_GCC)
# OBJECT usage requirements supply the runtime's and frontend's headers.
target_link_libraries(NativecadeCruisnObjects PRIVATE librecomp ultramodern N64Recomp n64frontend)
target_compile_options(NativecadeCruisnObjects PRIVATE -fno-strict-aliasing $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_include_directories(NativecadeCruisnObjects PRIVATE "${cruisn}/native"
    "${RT64_DIR}/src" "${RT64_DIR}/src/contrib" "${RT64_DIR}/src/contrib/hlslpp/include" "${RT64_DIR}/src/contrib/plume"
    "${RT64_DIR}/src/contrib/nativefiledialog-extended/src/include" "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game" "${CMAKE_CURRENT_LIST_DIR}/../n64interp" ${SDL2_INCLUDE_DIRS})

# Cruis'n World's copy protection compares eight values its boot leaves in memory, five of them
# instructions of the cartridge's boot code. navjack's cruisn_world_boot.cpp writes them, which the
# owner approved for builds on 2026-10-30; turned off, CruisnGame.cpp leaves them out and World stops
# at the check (docs/CRUISN.md).
option(RECOMPTV_CRUISN_WORLD_BOOT_WORDS "Write the boot values Cruis'n World checks (navjack's cruisn_world_boot.cpp)" ON)
if(RECOMPTV_CRUISN_WORLD_BOOT_WORDS)
    target_sources(NativecadeCruisnObjects PRIVATE "${cruisn}/world/native/cruisn_world_boot.cpp")
    target_compile_definitions(NativecadeCruisnObjects PRIVATE RECOMPTV_CRUISN_WORLD_BOOT_WORDS)
endif()

add_library(NativecadeCruisn SHARED $<TARGET_OBJECTS:NativecadeCruisnObjects> $<TARGET_OBJECTS:NativecadeCruisnGameCode>
    $<TARGET_OBJECTS:NativecadeCruisn_usa_tables> $<TARGET_OBJECTS:NativecadeCruisn_world_tables>)
# All of librecomp and ultramodern, so their libultra replacements win over the games' weak fallbacks
# even where nothing else pulls those objects in.
target_link_libraries(NativecadeCruisn PRIVATE n64frontend rt64 "-Wl,-force_load,$<TARGET_FILE:librecomp>"
    "-Wl,-force_load,$<TARGET_FILE:ultramodern>" librecomp ultramodern "-F${RECOMPTV_RUNTIME_BUILD}"
    "-framework NativecadeRuntime" "-framework Foundation" "-framework UIKit" "-framework Metal"
    "-framework QuartzCore")
endif()
set_target_properties(NativecadeCruisn PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeCruisn
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/CruisnRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.cruisn"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "1.0" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
