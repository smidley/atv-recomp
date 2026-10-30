cmake_minimum_required(VERSION 3.20)
# Star Wars Episode I: Racer, as NativecadeRacer.framework. Its runtime and renderer are other
# versions of the ones Shadows of the Empire builds, with the same target names, so it is a project
# of its own: build-nativecade-runtime.sh runs it after the shared runtime, whose framework supplies
# SDL (RECOMPTV_RUNTIME_BUILD). The game's code and audio microcode run through experiments/n64interp
# from the player's ROM, with tables prepare-racer.py writes from Racer's configuration, so nothing in
# the build comes from a ROM. Without a prepared Racer (RECOMPTV_RACER_SOURCE), the framework only
# reports that this build doesn't include the game.
project(NativecadeRacer LANGUAGES C CXX OBJC OBJCXX)
include("${CMAKE_CURRENT_LIST_DIR}/../../upstream/pins.cmake")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(racer "${RECOMPTV_RACER_SOURCE}")
if(NOT racer OR NOT EXISTS "${racer}/interpreter/n64interp_game.c")
    add_library(NativecadeRacer SHARED RacerUnavailable.cpp)
else()
# The game, N64ModernRuntime and RT64 have hidden symbols; SDL comes from the shared runtime.
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

# RT64 compiles its shaders while it builds: its tools run on the Mac (experiments/sote/host-tools,
# RECOMPTV_RACER_HOST_TOOLS) and the Metal compiler targets this SDK.
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(RECOMPTV_RACER_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET}-simulator)
else()
    set(RECOMPTV_RACER_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET})
endif()
set(RT64_STATIC TRUE)
set(RT64_DIR "${racer}/rt64")
set(N64_MODERN_RUNTIME_DIR "${racer}/N64ModernRuntime")
add_subdirectory("${RT64_DIR}" rt64)
# ImGui's Metal backend defines Objective-C classes that the shared runtime's copy also defines, and
# the Objective-C runtime keeps one class per name in a process; Racer's copy gets its own names.
set_source_files_properties("${RT64_DIR}/src/contrib/imgui/backends/imgui_impl_metal.mm" TARGET_DIRECTORY rt64
    PROPERTIES COMPILE_DEFINITIONS
    "MetalBuffer=RacerImGuiMetalBuffer;FramebufferDescriptor=RacerImGuiFramebufferDescriptor;MetalContext=RacerImGuiMetalContext")
add_subdirectory("${N64_MODERN_RUNTIME_DIR}" runtime)
# As Racer's build: the game's libultra writes VI/AI/PI/MI registers (0xA4000000 and up), which
# land in memory past KSEG0.
target_compile_definitions(librecomp PUBLIC RECOMP_MEM_SIZE_MB=640)
add_subdirectory("${racer}/racer/frontend" frontend)

# The game's code, interpreted from RDRAM.
add_library(NativecadeRacerGameCode OBJECT "${CMAKE_CURRENT_LIST_DIR}/../n64interp/N64Interpreter.cpp"
    "${racer}/interpreter/n64interp_game.c")
target_include_directories(NativecadeRacerGameCode PRIVATE "${N64_MODERN_RUNTIME_DIR}/N64Recomp/include"
    "${racer}/interpreter" "${CMAKE_CURRENT_LIST_DIR}/../n64interp")
target_compile_options(NativecadeRacerGameCode PRIVATE -fno-strict-aliasing)
set_target_properties(NativecadeRacerGameCode PROPERTIES C_STANDARD 17)

# Racer's host program, its audio microcode, and what Apple TV leaves out (experiments/sote).
add_library(NativecadeRacerObjects OBJECT "${racer}/racer/src/main.cpp" "${racer}/racer/src/section_table.cpp"
    RacerGame.cpp RacerRuntime.mm "${CMAKE_CURRENT_LIST_DIR}/../n64interp/N64RspInterpreter.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../sote/AppleTVStubs.cpp")
add_dependencies(NativecadeRacerObjects rt64)
set_source_files_properties("${racer}/racer/src/main.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeRacerMain")
# SDL_MAIN_HANDLED stops SDL's tvOS header from renaming main to SDL_main; RT64's headers expect the rest.
target_compile_definitions(NativecadeRacerObjects PRIVATE SDL_MAIN_HANDLED NOMINMAX HLSL_CPU FFX_GCC)
# OBJECT usage requirements supply the runtime's and frontend's headers.
target_link_libraries(NativecadeRacerObjects PRIVATE librecomp ultramodern N64Recomp n64frontend)
target_compile_options(NativecadeRacerObjects PRIVATE -fno-strict-aliasing $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_include_directories(NativecadeRacerObjects PRIVATE "${racer}/interpreter"
    "${RT64_DIR}/src" "${RT64_DIR}/src/contrib" "${RT64_DIR}/src/contrib/hlslpp/include" "${RT64_DIR}/src/contrib/plume"
    "${RT64_DIR}/src/contrib/imgui" "${RT64_DIR}/src/contrib/mupen64plus-core/src/api"
    "${RT64_DIR}/src/contrib/nativefiledialog-extended/src/include"
    "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game" "${CMAKE_CURRENT_LIST_DIR}/../n64interp" ${SDL2_INCLUDE_DIRS})

add_library(NativecadeRacer SHARED $<TARGET_OBJECTS:NativecadeRacerObjects> $<TARGET_OBJECTS:NativecadeRacerGameCode>)
# All of librecomp and ultramodern, so their libultra replacements win over n64interp_game.c's
# weak fallbacks even where nothing else pulls those objects in.
target_link_libraries(NativecadeRacer PRIVATE n64frontend rt64 "-Wl,-force_load,$<TARGET_FILE:librecomp>"
    "-Wl,-force_load,$<TARGET_FILE:ultramodern>" librecomp ultramodern "-F${RECOMPTV_RUNTIME_BUILD}"
    "-framework NativecadeRuntime" "-framework Foundation" "-framework UIKit" "-framework Metal"
    "-framework QuartzCore")
endif()
set_target_properties(NativecadeRacer PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeRacer
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/RacerRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.racer"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${RECOMPTV_RACER_RELEASE}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
