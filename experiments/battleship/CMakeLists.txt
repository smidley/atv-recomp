cmake_minimum_required(VERSION 3.26)
# Super Smash Bros. (BattleShip) for Apple TV (docs/BATTLESHIP.md). BattleShip needs its own forks of
# libultraship and Torch, so this is a project of its own rather than part of the shared runtime
# build, whose libultraship, torch and ImGui targets have the same names. Everything here is
# linked into NativecadeBattleShip.framework with hidden symbols; only SDL and the game-runner API
# come from NativecadeRuntime.framework.
project(NativecadeBattleShip LANGUAGES C CXX OBJC OBJCXX)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS")
    message(FATAL_ERROR "NativecadeBattleShip is built with the tvOS SDK")
endif()
set(repo "${CMAKE_CURRENT_LIST_DIR}/../..")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${repo}/upstream/battleship-baseline.json")
file(READ "${repo}/upstream/battleship-baseline.json" pins)
string(JSON release GET "${pins}" release)
string(JSON torch_revision GET "${pins}" sources battleship-torch revision)
string(SUBSTRING "${torch_revision}" 0 7 torch_short)
string(TOLOWER "${CMAKE_OSX_SYSROOT}" sdk)
if(sdk MATCHES "simulator")
    set(sdk appletvsimulator)
else()
    set(sdk appletvos)
endif()
set(RECOMPTV_BATTLESHIP_SOURCE "${repo}/build/battleship/source" CACHE PATH "Output of scripts/prepare-battleship.py")
set(RECOMPTV_RUNTIME_BUILD "${repo}/build/nativecade-runtime/${sdk}" CACHE PATH "The shared runtime's build for this SDK")
set(bs "${RECOMPTV_BATTLESHIP_SOURCE}")
set(runtime "${RECOMPTV_RUNTIME_BUILD}")
if(NOT EXISTS "${runtime}/NativecadeRuntime.framework/NativecadeRuntime")
    message(FATAL_ERROR "Build the shared runtime for ${sdk} first (scripts/build-nativecade-runtime.sh)")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
# Nothing but the preparation entry point leaves the framework (also enforced when linking).
add_compile_options(-fvisibility=hidden $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fvisibility-inlines-hidden>)

# BattleShip's own configuration (its CMakeLists.txt), as its Android build sets it: no TinyCC
# mods or funchook (no runtime code generation on tvOS), no MPQ, Torch linked in, not run as a tool.
set(DISABLE_SCRIPTING ON CACHE BOOL "" FORCE)
add_compile_definitions(DISABLE_SCRIPTING)
set(INCLUDE_MPQ_SUPPORT OFF CACHE BOOL "" FORCE)
set(GBI_UCODE "F3DEX_GBI_2" CACHE STRING "" FORCE)
set(LUS_ENABLE_POSTPROCESS_TRANSPILER OFF CACHE BOOL "" FORCE)
set(USE_STANDALONE OFF CACHE BOOL "" FORCE)
foreach(feature STORMLIB SM64 MK64 SF64 PM64 FZERO MARIO_ARTIST)
    set(BUILD_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
set(BUILD_NAUDIO ON CACHE BOOL "" FORCE)
set(BUILD_SSB64 ON CACHE BOOL "" FORCE)
foreach(option ENABLE_BZIP2 ENABLE_LZMA ENABLE_ZSTD ENABLE_OPENSSL ENABLE_GNUTLS ENABLE_MBEDTLS
        ENABLE_COMMONCRYPTO BUILD_TOOLS BUILD_REGRESS BUILD_EXAMPLES BUILD_DOC BUILD_OSSFUZZ
        tinyxml2_BUILD_TESTING JSON_BuildTests)
    set(${option} OFF CACHE BOOL "" FORCE)
endforeach()

# SDL is the shared runtime's: its headers and build configuration, linked from the framework.
set(runtime_sdl "${runtime}/_deps/sdl2-build")
file(GLOB runtime_sdl_config "${runtime_sdl}/include-config-*/SDL2")
add_library(SDL2::SDL2-static INTERFACE IMPORTED GLOBAL)
target_include_directories(SDL2::SDL2-static INTERFACE "${runtime_sdl}/include" "${runtime_sdl}/include/SDL2" ${runtime_sdl_config})
add_library(SDL2::SDL2main INTERFACE IMPORTED GLOBAL)
file(WRITE "${CMAKE_FIND_PACKAGE_REDIRECTS_DIR}/sdl2-config.cmake" "# SDL2::SDL2-static is defined by experiments/battleship\n")

# The shared runtime already downloaded these at the commits BattleShip's libultraship asks for.
# Its ImGui carries the same patches except BattleShip's Android guards and a floating-viewport
# clear, which tvOS doesn't use. Anything else is downloaded as BattleShip declares it.
foreach(dependency nlohmann_json=55f93686c01528224f448c19128836e7df245f72 tinyxml2=9148bdf719e997d1f474be6bcc7943881046dba1
        spdlog=486b55554f11c9cccc913e11a87085b2a91f706f libzip=6f8a0cdd24a0dc6cce9dac4a7679da784ab124ea
        threadpool=097aa718f25d44315cadb80b407144ad455ee4f9 metalcpp=7bf710a725b386f6db869f8a2b48a56be29b6233
        prism=1de054450e7b3c5f777d2e3dfcb228ad120c329d imgui=4806a1924ff6181180bf5e4b8b79ab4394118875)
    string(REPLACE "=" ";" dependency "${dependency}")
    list(GET dependency 0 name)
    list(GET dependency 1 commit)
    set(directory "${runtime}/_deps/${name}-src")
    execute_process(COMMAND git -C "${directory}" rev-parse HEAD
        OUTPUT_VARIABLE head OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(head STREQUAL commit)
        string(TOUPPER "${name}" name)
        set(FETCHCONTENT_SOURCE_DIR_${name} "${directory}")
    endif()
endforeach()

add_subdirectory("${bs}/libultraship" libultraship)
add_subdirectory("${bs}/torch" torch)
# The shared runtime's copy of ImGui's Metal backend registers the same Objective-C class names.
target_compile_definitions(ImGui PRIVATE MetalBuffer=NativecadeBattleShipMetalBuffer
    FramebufferDescriptor=NativecadeBattleShipFramebufferDescriptor MetalContext=NativecadeBattleShipMetalContext)

# Upstream's definitions for the US build (SSB64_COMPILE_DEFS).
set(game_definitions REGION_US=1 VERSION_US=1 SSB64_APP_NAME=\"BattleShip\" SSB64_O2R_NAME=\"BattleShip.o2r\"
    NON_MATCHING=1 NON_EQUIVALENT=1 AVOID_UB=1 PORT=1 F3DEX_GBI_2=1 _LANGUAGE_C N_MICRO=1 _USE_MATH_DEFINES
    CIMGUI_DEFINE_ENUMS_AND_STRUCTS BATTLESHIP_CURRENT_VERSION=\"${release}\" PORT_HIRES_ENABLED=1)

# The decompiled game, compiled against the decomp's own C headers (upstream's ssb64_game).
foreach(folder credits ef ft gm gr if it lb mn mp mv sc sys wp)
    file(GLOB_RECURSE found CONFIGURE_DEPENDS "${bs}/decomp/src/${folder}/*.c")
    list(APPEND game_sources ${found})
endforeach()
list(FILTER game_sources EXCLUDE REGEX "\\.inc\\.c$")
file(GLOB stubs CONFIGURE_DEPENDS "${bs}/port/stubs/*.c")
foreach(file gu/mtxcatf gu/mtxutil gu/mtxxfmf gu/normalize gu/sinf gu/cosf n_audio/n_env n_audio/n_synaddplayer
        n_audio/n_synallocfx n_audio/n_synallocvoice n_audio/n_synfreevoice n_audio/n_syndelete n_audio/n_synsetfxmix
        n_audio/n_synsetpan n_audio/n_synsetpitch n_audio/n_synsetpriority n_audio/n_synsetvol
        n_audio/n_synstartvoiceparam n_audio/n_synstopvoice n_audio/n_cspplay n_audio/n_cspsetbank
        n_audio/n_cspsetfxmix n_audio/n_cspsetpriority n_audio/n_cspsetseq n_audio/n_cspsetvol n_audio/n_cspstop
        n_audio/n_seq n_audio/n_seqplayer n_audio/n_seqpgetchlvol n_audio/n_seqpgetvol audio/cents2ratio)
    list(APPEND game_sources "${bs}/decomp/src/libultra/${file}.c")
endforeach()
add_library(NativecadeBattleShipGame OBJECT ${game_sources} ${stubs})
target_compile_definitions(NativecadeBattleShipGame PRIVATE ${game_definitions})
target_include_directories(NativecadeBattleShipGame PRIVATE "${bs}/include" "${bs}/decomp/include" "${bs}/decomp/src"
    "${bs}/port" "${bs}/debug_tools" "${bs}/libultraship/src" "${bs}/libultraship/include")
target_compile_options(NativecadeBattleShipGame PRIVATE -fno-builtin-sinf -fno-builtin-cosf
    -Werror=implicit-function-declaration -Wno-implicit-int -Werror=int-conversion -Werror=incompatible-pointer-types
    -Wno-shift-negative-value -Wno-parentheses-equality -Wno-pointer-sign -Wno-unused-value -Wno-unused-variable
    -Wno-unused-but-set-variable -Wno-unused-function -Werror=return-type -Werror=incompatible-library-redeclaration
    -Werror=return-mismatch -Wno-constant-conversion -Wno-tautological-constant-out-of-range-compare)
set_source_files_properties("${bs}/decomp/src/libultra/gu/sinf.c" "${bs}/decomp/src/libultra/gu/cosf.c"
    PROPERTIES COMPILE_OPTIONS "-ffp-contract=off;-fno-strict-aliasing")

# The port layer, without what tvOS can't run or Nativecade replaces: the first-run extractor and
# file dialog (they start Torch and osascript as processes), the updater, Discord and the shader
# downloader (as on Android), mods (DISABLE_SCRIPTING) and the other platforms' coroutines.
file(GLOB_RECURSE port_sources CONFIGURE_DEPENDS "${bs}/port/*.cpp" "${bs}/port/*.c" "${bs}/debug_tools/*.c")
list(FILTER port_sources EXCLUDE REGEX "/port/(stubs|mods)/|/port/resource/RelocFileTable\\.jp\\.cpp$")
list(FILTER port_sources EXCLUDE REGEX "/port/(first_run|native_dialog|android_[a-z_]+|coroutine_(android|win32|test))\\.cpp$")
list(FILTER port_sources EXCLUDE REGEX "/port/enhancements/(Updater|DiscordRichPresence|ShaderDownloader)\\.cpp$")
# Nativecade restores the original game's C globals before each later start (NativecadeRuntime.mm).
set(game_c ${game_sources} ${stubs} ${port_sources})
list(FILTER game_c INCLUDE REGEX "\\.c$")
set_property(SOURCE ${game_c} APPEND PROPERTY COMPILE_OPTIONS
    -include "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game/GameStateSection.h")
set_source_files_properties("${bs}/port/port.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeBattleShipMain")

add_library(NativecadeBattleShip SHARED $<TARGET_OBJECTS:NativecadeBattleShipGame> ${port_sources} BattleShipRuntime.mm)
target_compile_definitions(NativecadeBattleShip PRIVATE ${game_definitions} RECOMPTV_TVOS
    NATIVECADE_BATTLESHIP_PREPARED="BattleShip-${release}-torch${torch_short}")
target_include_directories(NativecadeBattleShip PRIVATE "${bs}/decomp/src" "${bs}/port" "${bs}/debug_tools"
    "${bs}/generated" "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game")
target_compile_options(NativecadeBattleShip PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_link_libraries(NativecadeBattleShip PRIVATE libultraship torch libzip::zip
    "-framework Foundation" "-framework UIKit" "-framework CoreFoundation")
# Only symbols that this framework's own libraries don't define may bind to the shared runtime: SDL
# and the game-runner API. It is linked last so that its exported ImGui, libultraship and libzip
# symbols can't satisfy anything here.
foreach(language C CXX OBJC OBJCXX)
    set(CMAKE_${language}_STANDARD_LIBRARIES "\"${runtime}/NativecadeRuntime.framework/NativecadeRuntime\"")
endforeach()
target_link_options(NativecadeBattleShip PRIVATE "LINKER:-exported_symbol,_NativecadePrepareSuperSmashBros" "LINKER:-dead_strip")
string(REGEX REPLACE "^v" "" bundle_version "${release}")
set_target_properties(NativecadeBattleShip PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeBattleShip
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/BattleShipRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.battleship"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${bundle_version}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
