cmake_minimum_required(VERSION 3.26)
project(RecompTVShipwrightGame VERSION 9.3.1 LANGUAGES C CXX OBJC OBJCXX)
string(TOLOWER "${CMAKE_OSX_SYSROOT}" simulator_sdk)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS" OR NOT simulator_sdk MATCHES "appletvsimulator")
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
include("${RECOMPTV_SHIPWRIGHT_SOURCE}/CMake/soh-cvars.cmake")
include("${RECOMPTV_SHIPWRIGHT_SOURCE}/CMake/lus-cvars.cmake")
add_compile_options(-fno-fast-math -ffp-contract=off)
add_subdirectory(../metal metal)

include(FetchContent)
FetchContent_GetProperties(SDL2 SOURCE_DIR recomptv_sdl_source)
set(scene_patch "${CMAKE_CURRENT_LIST_DIR}/sdl-scenes.patch")
execute_process(COMMAND git apply --reverse --check "${scene_patch}"
    WORKING_DIRECTORY "${recomptv_sdl_source}" RESULT_VARIABLE scene_patch_applied
    OUTPUT_QUIET ERROR_QUIET)
if(NOT scene_patch_applied EQUAL 0)
    execute_process(COMMAND git apply "${scene_patch}"
        WORKING_DIRECTORY "${recomptv_sdl_source}" COMMAND_ERROR_IS_FATAL ANY)
endif()
target_compile_definitions(SDL2-static PRIVATE RECOMPTV_TVOS_SCENES)

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
add_subdirectory("${RECOMPTV_TORCH_SOURCE}" torch)
target_compile_definitions(torch INTERFACE YAML_CPP_STATIC_DEFINE)

set(ship "${RECOMPTV_SHIPWRIGHT_SOURCE}/soh")
set(CMAKE_PROJECT_VERSION_MAJOR 9)
set(CMAKE_PROJECT_VERSION_MINOR 3)
set(CMAKE_PROJECT_VERSION_PATCH 1)
set(PROJECT_BUILD_NAME "RecompTV Simulator")
set(PROJECT_TEAM "HarbourMasters / RecompTV experiment")
set(CMAKE_PROJECT_GIT_BRANCH "pinned-9.3.1")
set(CMAKE_PROJECT_GIT_COMMIT_HASH "f0599f96")
set(CMAKE_PROJECT_GIT_COMMIT_TAG "9.3.1")
configure_file("${ship}/src/boot/build.c.in" "${ship}/src/boot/build.c" @ONLY)
configure_file("${ship}/properties.h.in" "${ship}/properties.h" @ONLY)
file(GLOB_RECURSE game CONFIGURE_DEPENDS "${ship}/src/*.c" "${ship}/soh/*.c" "${ship}/soh/*.cpp")
list(FILTER game EXCLUDE REGEX "/src/(dmadata|elf_message)/")
list(FILTER game EXCLUDE REGEX "/src/libultra/(io|libc|os|rmon)/")
list(FILTER game EXCLUDE REGEX "/src/libultra/gu/(cosf|lookat|lookathil|perspective|position|sinf|sqrtf|us2dex)\\.c$")
list(FILTER game EXCLUDE REGEX "/speechsynthesizer/(SAPI|ESpeak)")
list(APPEND game "${ship}/src/libultra/libc/sprintf.c"
    "${ship}/soh/Enhancements/speechsynthesizer/DarwinSpeechSynthesizer.mm")
add_executable(RecompTVShipwright MACOSX_BUNDLE ${game} SimulatorMain.mm)
set_source_files_properties("${ship}/src/code/main.c" PROPERTIES COMPILE_DEFINITIONS "main=RecompTVShipwrightMain")
target_compile_definitions(RecompTVShipwright PRIVATE __IOS__ RECOMPTV_TVOS SDL_MAIN_HANDLED
    F3DEX_GBI_2 _CONSOLE UNICODE _UNICODE SPDLOG_ACTIVE_LEVEL=2 LOG_LEVEL_GAME_PRINTS=6)
target_compile_options(RecompTVShipwright PRIVATE -fblocks -Wno-narrowing
    -Wno-deprecated-enum-enum-conversion -Wno-unknown-pragmas
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/SDL2")
configure_file("${sdl2_net_SOURCE_DIR}/SDL_net.h" "${CMAKE_CURRENT_BINARY_DIR}/include/SDL2/SDL_net.h" COPYONLY)
target_include_directories(RecompTVShipwright PRIVATE "${ship}" "${ship}/include"
    "${ship}/src" "${ship}/assets" "${dr_libs_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/include")
target_link_libraries(RecompTVShipwright PRIVATE libultraship torch SDL2_net::SDL2_net-static
    vorbisfile recomptv_opusfile "-framework AVFoundation")
set_target_properties(RecompTVShipwright PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.smidley.RecompTVShipwrightExperiment"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "3"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
