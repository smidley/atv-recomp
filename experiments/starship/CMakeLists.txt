# Included by the Nativecade runtime build, like experiments/spaghettikart. Game code has hidden
# symbols, while SDL, Metal, libultraship, audio codecs and Torch come from the shared runtime.
# libultraship's event functions aren't referenced by Shipwright but are needed by Starship.
target_sources(RecompTVShipwright PRIVATE "${RECOMPTV_LUS_SOURCE}/src/libultraship/bridge/eventsbridge.cpp")
include(FetchContent)
FetchContent_Declare(nativecade_sse2neon GIT_REPOSITORY https://github.com/DLTcollab/sse2neon.git
    GIT_TAG 2272251cc3ad9cba8b8c47c4065811cfb396b802)
FetchContent_MakeAvailable(nativecade_sse2neon)
set(fox "${RECOMPTV_STARSHIP_SOURCE}")
file(GLOB_RECURSE fox_sources CONFIGURE_DEPENDS "${fox}/src/audio/*.c" "${fox}/src/engine/*.c"
    "${fox}/src/overlays/*.c" "${fox}/src/port/*.c" "${fox}/src/port/*.cpp" "${fox}/src/sys/*.c")
foreach(file libultra/io/aisetfreq libultra/gu/sqrtf libultra/gu/mtxutil libultra/gu/ortho buffers dmatable
        libc_math64 libc_sprintf)
    list(APPEND fox_sources "${fox}/src/${file}.c")
endforeach()
# libultraship provides the event system (scripts/prepare-starship.py).
list(FILTER fox_sources EXCLUDE REGEX "\\.inc\\.c$|/engine/fox_(colheaders|edata_info|rcp_setup|load_inits)\\.c$|/ovl_ending/fox_end2_data\\.c$|/sys/sys_(timer|fault)\\.c$|/mods/object_ram\\.c$|/hooks/impl/EventSystem\\.cpp$")
# Nativecade restores the original game's C globals before each later start (NativecadeRuntime.mm).
set(fox_c ${fox_sources})
list(FILTER fox_c INCLUDE REGEX "\\.c$")
set_property(SOURCE ${fox_c} APPEND PROPERTY COMPILE_OPTIONS
    -include "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game/GameStateSection.h")
add_library(NativecadeStarshipObjects OBJECT ${fox_sources} StarshipRuntime.mm StarshipRestart.cpp
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_pi.cpp"
    # XML commands must use Star Fox's F3DEX encoding, not Shipwright's F3DEX2.
    "${RECOMPTV_LUS_SOURCE}/src/fast/resource/factory/DisplayListFactory.cpp")
set_target_properties(NativecadeStarshipObjects PROPERTIES C_STANDARD 11)
# Upstream also defines GBI_FLOATS. The shared Fast3D interpreter reads the N64's fixed-point
# vertices and matrices, which Starship's code still supports.
target_compile_definitions(NativecadeStarshipObjects PRIVATE VERSION_US=1 ENABLE_RUMBLE=1 F3DEX_GBI=1
    _LANGUAGE_C _USE_MATH_DEFINES CIMGUI_DEFINE_ENUMS_AND_STRUCTS NON_MATCHING=1 NON_EQUIVALENT=1
    AVOID_UB=1 __IOS__ PLATFORM_IOS=1 RECOMPTV_TVOS SDL_MAIN_HANDLED _CONSOLE UNICODE _UNICODE
    SPDLOG_ACTIVE_LEVEL=2)
# Prepared assets depend on the game release and the shared Torch.
string(SUBSTRING "${RECOMPTV_TORCH_REVISION}" 0 7 recomptv_torch_short)
target_compile_definitions(NativecadeStarshipObjects PRIVATE
    NATIVECADE_FOX_PREPARED="Starship-${RECOMPTV_STARSHIP_RELEASE}-torch${recomptv_torch_short}")
target_compile_options(NativecadeStarshipObjects PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden
    -Wno-narrowing -Wno-deprecated-enum-enum-conversion -Wno-unknown-pragmas -Wno-return-type
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
set_source_files_properties("${fox}/src/port/Game.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeStarshipMain")
target_include_directories(NativecadeStarshipObjects PRIVATE "${fox}" "${fox}/include" "${fox}/src"
    "${dr_libs_SOURCE_DIR}" "${nativecade_sse2neon_SOURCE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game" "${RECOMPTV_LUS_SOURCE}/include/libultraship")
# OBJECT usage requirements supply matching dependency headers without linking
# a second SDL or libultraship copy into the game framework.
target_link_libraries(NativecadeStarshipObjects PRIVATE libultraship torch vorbisfile)
add_library(NativecadeStarship SHARED $<TARGET_OBJECTS:NativecadeStarshipObjects>)
target_link_libraries(NativecadeStarship PRIVATE RecompTVShipwright libzip::zip "-framework Foundation" "-framework UIKit")
string(REGEX REPLACE "^v" "" recomptv_starship_version "${RECOMPTV_STARSHIP_RELEASE}")
set_target_properties(NativecadeStarship PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeStarship
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/StarshipRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.starship"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${recomptv_starship_version}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
