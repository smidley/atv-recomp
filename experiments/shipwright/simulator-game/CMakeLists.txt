cmake_minimum_required(VERSION 3.26)
include("${CMAKE_CURRENT_LIST_DIR}/../../../upstream/pins.cmake")
project(RecompTVShipwrightGame VERSION ${RECOMPTV_SHIPWRIGHT_RELEASE} LANGUAGES C CXX OBJC OBJCXX)
option(RECOMPTV_BUILD_RUNTIME_FRAMEWORK "Build the distributable Nativecade runtime framework" OFF)
string(TOLOWER "${CMAKE_OSX_SYSROOT}" simulator_sdk)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS" OR
   (NOT RECOMPTV_BUILD_RUNTIME_FRAMEWORK AND NOT simulator_sdk MATCHES "appletvsimulator"))
    message(FATAL_ERROR "This development game target is simulator-only")
endif()
set(CMAKE_C_STANDARD 23)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
add_compile_definitions(CONTROLLERBUTTONS_T=uint32_t)
# The pinned game's CVar names are a config ABI. An earlier standalone Metal
# configure may have cached generic libultraship names; do not reuse those.
get_cmake_property(recomptv_cached_variables CACHE_VARIABLES)
foreach(variable IN LISTS recomptv_cached_variables)
    if(variable MATCHES "^CVAR_")
        unset(${variable} CACHE)
    endif()
endforeach()
include("${RECOMPTV_SHIPWRIGHT_SOURCE}/CMake/soh-cvars.cmake")
include("${RECOMPTV_SHIPWRIGHT_SOURCE}/CMake/lus-cvars.cmake")
add_compile_options(-fno-fast-math -ffp-contract=off)
add_subdirectory(../metal metal)

include(FetchContent)
FetchContent_GetProperties(SDL2 SOURCE_DIR recomptv_sdl_source)
set(scene_patch "${CMAKE_CURRENT_LIST_DIR}/sdl-scenes.patch")
set(library_patch "${CMAKE_CURRENT_LIST_DIR}/sdl-nativecade.patch")
execute_process(COMMAND git apply --reverse --check "${library_patch}"
    WORKING_DIRECTORY "${recomptv_sdl_source}" RESULT_VARIABLE library_patch_applied
    OUTPUT_QUIET ERROR_QUIET)
execute_process(COMMAND git apply --reverse --check "${scene_patch}"
    WORKING_DIRECTORY "${recomptv_sdl_source}" RESULT_VARIABLE scene_patch_applied
    OUTPUT_QUIET ERROR_QUIET)
if(NOT scene_patch_applied EQUAL 0 AND NOT library_patch_applied EQUAL 0)
    execute_process(COMMAND git apply "${scene_patch}"
        WORKING_DIRECTORY "${recomptv_sdl_source}" COMMAND_ERROR_IS_FATAL ANY)
endif()
target_compile_definitions(SDL2-static PRIVATE RECOMPTV_TVOS_SCENES)
if(RECOMPTV_BUILD_RUNTIME_FRAMEWORK)
    if(NOT library_patch_applied EQUAL 0)
        execute_process(COMMAND git apply "${library_patch}"
            WORKING_DIRECTORY "${recomptv_sdl_source}" COMMAND_ERROR_IS_FATAL ANY)
    endif()
    target_compile_definitions(SDL2-static PRIVATE NATIVECADE_RUNTIME)
endif()
set(rumble_patch "${CMAKE_CURRENT_LIST_DIR}/sdl-rumble.patch")
execute_process(COMMAND git apply --reverse --check "${rumble_patch}"
    WORKING_DIRECTORY "${recomptv_sdl_source}" RESULT_VARIABLE rumble_patch_applied
    OUTPUT_QUIET ERROR_QUIET)
if(NOT rumble_patch_applied EQUAL 0)
    execute_process(COMMAND git apply "${rumble_patch}"
        WORKING_DIRECTORY "${recomptv_sdl_source}" COMMAND_ERROR_IS_FATAL ANY)
endif()

FetchContent_Declare(dr_libs GIT_REPOSITORY https://github.com/mackron/dr_libs.git
    GIT_TAG da35f9d6c7374a95353fd1df1d394d44ab66cf01)
FetchContent_Declare(SDL2_net GIT_REPOSITORY https://github.com/libsdl-org/SDL_net.git
    GIT_TAG 669e75b84632e2c6cc5c65974ec9e28052cb7a4e)
FetchContent_Declare(Ogg GIT_REPOSITORY https://github.com/xiph/ogg.git
    GIT_TAG e1774cd77f471443541596e09078e78fdc342e4f OVERRIDE_FIND_PACKAGE)
FetchContent_Declare(vorbis GIT_REPOSITORY https://github.com/xiph/vorbis.git
    GIT_TAG 0657aee69dec8508a0011f47f3b69d7538e9d262)
FetchContent_Declare(opus GIT_REPOSITORY https://github.com/xiph/opus.git
    GIT_TAG ddbe48383984d56acd9e1ab6a090c54ca6b735a6)
FetchContent_Declare(opusfile GIT_REPOSITORY https://github.com/xiph/opusfile.git
    GIT_TAG a55c164e9891a9326188b7d4d216ec9a88373739)
set(SDL2NET_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2NET_INSTALL OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(dr_libs SDL2_net Ogg vorbis opus opusfile)
add_library(recomptv_opusfile STATIC "${opusfile_SOURCE_DIR}/src/info.c"
    "${opusfile_SOURCE_DIR}/src/internal.c" "${opusfile_SOURCE_DIR}/src/opusfile.c"
    "${opusfile_SOURCE_DIR}/src/stream.c")
target_compile_definitions(recomptv_opusfile PRIVATE OP_DISABLE_HTTP HAVE_LRINTF)
target_include_directories(recomptv_opusfile PUBLIC "${opusfile_SOURCE_DIR}/include" "${opus_SOURCE_DIR}/include")
target_link_libraries(recomptv_opusfile PUBLIC opus ogg)

FetchContent_Declare(yaml-cpp GIT_REPOSITORY https://github.com/jbeder/yaml-cpp.git
    GIT_TAG 56e3bb550c91fd7005566f19c079cb7a503223cf)
FetchContent_Declare(zlib GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG 51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf OVERRIDE_FIND_PACKAGE)
set(USE_STANDALONE OFF CACHE BOOL "" FORCE)
set(PORT_VERSION_ENDIANNESS ON CACHE BOOL "" FORCE)
set(ROM_CRC_BSWAP OFF CACHE BOOL "" FORCE)
set(BUILD_OOT ON CACHE BOOL "" FORCE)
foreach(feature UI STORMLIB SM64 MK64 SF64 PM64 FZERO BK64 MARIO_ARTIST NAUDIO)
    set(BUILD_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
if(RECOMPTV_SPAGHETTIKART_SOURCE)
    set(BUILD_MK64 ON CACHE BOOL "" FORCE)
    set(BUILD_NAUDIO ON CACHE BOOL "" FORCE)
endif()
if(RECOMPTV_STARSHIP_SOURCE)
    set(BUILD_SF64 ON CACHE BOOL "" FORCE)
    set(BUILD_NAUDIO ON CACHE BOOL "" FORCE)
endif()
add_subdirectory("${RECOMPTV_TORCH_SOURCE}" torch)
target_compile_definitions(torch INTERFACE YAML_CPP_STATIC_DEFINE)
if(RECOMPTV_SPAGHETTIKART_SOURCE)
    get_target_property(torch_sources torch SOURCES)
    list(REMOVE_ITEM torch_sources "${RECOMPTV_TORCH_SOURCE}/src/factories/DisplayListFactory.cpp")
    list(REMOVE_ITEM torch_sources "${RECOMPTV_TORCH_SOURCE}/src/utils/Decompressor.cpp")
    set_property(TARGET torch PROPERTY SOURCES "${torch_sources}")
    target_sources(torch PRIVATE "${RECOMPTV_SPAGHETTIKART_SOURCE}/../torch-compat/DisplayListFactory.cpp"
        "${RECOMPTV_SPAGHETTIKART_SOURCE}/../torch-compat/Decompressor.cpp")
    target_include_directories(torch PRIVATE "${RECOMPTV_TORCH_SOURCE}/src/factories" "${RECOMPTV_TORCH_SOURCE}/src/utils")
endif()

set(ship "${RECOMPTV_SHIPWRIGHT_SOURCE}/soh")
set(CMAKE_PROJECT_VERSION_MAJOR ${RecompTVShipwrightGame_VERSION_MAJOR})
set(CMAKE_PROJECT_VERSION_MINOR ${RecompTVShipwrightGame_VERSION_MINOR})
set(CMAKE_PROJECT_VERSION_PATCH ${RecompTVShipwrightGame_VERSION_PATCH})
set(PROJECT_BUILD_NAME "RecompTV Simulator")
set(PROJECT_TEAM "HarbourMasters / RecompTV experiment")
set(CMAKE_PROJECT_GIT_BRANCH "pinned-${RECOMPTV_SHIPWRIGHT_RELEASE}")
string(SUBSTRING "${RECOMPTV_SHIPWRIGHT_REVISION}" 0 8 CMAKE_PROJECT_GIT_COMMIT_HASH)
set(CMAKE_PROJECT_GIT_COMMIT_TAG "${RECOMPTV_SHIPWRIGHT_RELEASE}")
configure_file("${ship}/src/boot/build.c.in" "${ship}/src/boot/build.c" @ONLY)
configure_file("${ship}/properties.h.in" "${ship}/properties.h" @ONLY)
file(GLOB_RECURSE game CONFIGURE_DEPENDS "${ship}/src/*.c" "${ship}/soh/*.c" "${ship}/soh/*.cpp")
list(FILTER game EXCLUDE REGEX "/src/(dmadata|elf_message)/")
list(FILTER game EXCLUDE REGEX "/src/libultra/(io|libc|os|rmon)/")
list(FILTER game EXCLUDE REGEX "/src/libultra/gu/(cosf|lookat|lookathil|perspective|position|sinf|sqrtf|us2dex)\\.c$")
list(FILTER game EXCLUDE REGEX "/speechsynthesizer/(SAPI|ESpeak)")
list(APPEND game "${ship}/src/libultra/libc/sprintf.c"
    "${ship}/soh/Enhancements/speechsynthesizer/DarwinSpeechSynthesizer.mm")
if(RECOMPTV_BUILD_RUNTIME_FRAMEWORK)
    add_library(RecompTVShipwright SHARED ${game} NativecadeRuntime.mm NativecadeRuntime.h AppleTVPerformance.cpp
        AppleTVGameplay.cpp AppleTVSaveStore.mm AppleTVSaveUI.mm)
    set_target_properties(RecompTVShipwright PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeRuntime
        PUBLIC_HEADER "NativecadeRuntime.h" MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.runtime"
        MACOSX_FRAMEWORK_SHORT_VERSION_STRING "0.1.0" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
        INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
else()
    add_executable(RecompTVShipwright MACOSX_BUNDLE ${game} SimulatorMain.mm AppleTVPerformance.cpp
        AppleTVGameplay.cpp AppleTVSaveStore.mm AppleTVSaveUI.mm ControllerProbe.cpp SaveStoreTests.mm)
endif()
if(RECOMPTV_BUILD_RUNTIME_FRAMEWORK AND RECOMPTV_SPAGHETTIKART_SOURCE)
    add_subdirectory(../../spaghettikart spaghettikart)
endif()
if(RECOMPTV_BUILD_RUNTIME_FRAMEWORK AND RECOMPTV_STARSHIP_SOURCE)
    add_subdirectory(../../starship starship)
endif()
set_source_files_properties("${ship}/src/code/main.c" PROPERTIES COMPILE_DEFINITIONS "main=RecompTVShipwrightMain")
# Nativecade restores the original game's C globals before each later start (NativecadeRuntime.mm).
set(game_c ${game})
list(FILTER game_c INCLUDE REGEX "\\.c$")
set_property(SOURCE ${game_c} APPEND PROPERTY COMPILE_OPTIONS
    -include "${CMAKE_CURRENT_LIST_DIR}/GameStateSection.h")
target_compile_definitions(RecompTVShipwright PRIVATE __IOS__ RECOMPTV_TVOS SDL_MAIN_HANDLED
    NATIVECADE_SHIPWRIGHT_RELEASE="${RECOMPTV_SHIPWRIGHT_RELEASE}"
    F3DEX_GBI_2 _CONSOLE UNICODE _UNICODE SPDLOG_ACTIVE_LEVEL=2 LOG_LEVEL_GAME_PRINTS=6)
target_compile_options(RecompTVShipwright PRIVATE -fblocks -Wno-narrowing
    -Wno-deprecated-enum-enum-conversion -Wno-unknown-pragmas
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/SDL2")
configure_file("${sdl2_net_SOURCE_DIR}/SDL_net.h" "${CMAKE_CURRENT_BINARY_DIR}/include/SDL2/SDL_net.h" COPYONLY)
target_include_directories(RecompTVShipwright PRIVATE "${ship}" "${ship}/include"
    "${ship}/src" "${ship}/assets" "${dr_libs_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/include"
    "${CMAKE_CURRENT_LIST_DIR}")
target_link_libraries(RecompTVShipwright PRIVATE libultraship torch SDL2_net::SDL2_net-static
    vorbisfile recomptv_opusfile "-framework AVFoundation" "-framework Security" "-lz")
if(NOT RECOMPTV_BUILD_RUNTIME_FRAMEWORK)
# Match Xcode simulator builds: simulated entitlements are Mach-O sections,
# not restricted host macOS code-signing entitlements on an ad-hoc signature.
set(simulator_entitlements "${CMAKE_CURRENT_LIST_DIR}/Simulator.entitlements")
set(simulator_entitlements_der "${CMAKE_CURRENT_BINARY_DIR}/Simulator.entitlements.der")
find_program(RECOMPTV_DERQ derq PATHS /usr/bin REQUIRED)
execute_process(COMMAND "${RECOMPTV_DERQ}" query -f xml -i "${simulator_entitlements}"
    -o "${simulator_entitlements_der}" --raw COMMAND_ERROR_IS_FATAL ANY)
target_link_options(RecompTVShipwright PRIVATE
    "LINKER:-sectcreate,__TEXT,__entitlements,${simulator_entitlements}"
    "LINKER:-sectcreate,__TEXT,__ents_der,${simulator_entitlements_der}")
set_property(TARGET RecompTVShipwright APPEND PROPERTY LINK_DEPENDS "${simulator_entitlements}")
set_target_properties(RecompTVShipwright PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.smidley.RecompTVShipwrightExperiment"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "3"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
endif()
