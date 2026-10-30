# Included by the Nativecade runtime build, like experiments/starship. Game code has hidden
# symbols, while SDL, Metal, libultraship, audio codecs and Torch come from the shared runtime.
set(mario "${RECOMPTV_GHOSTSHIP_SOURCE}")
# Upstream's source list, without the web and Android ports. Networking is off (USE_NETWORKING).
file(GLOB_RECURSE mario_sources CONFIGURE_DEPENDS "${mario}/actors/*.c" "${mario}/data/*.c"
    "${mario}/levels/*.c" "${mario}/src/*.c" "${mario}/src/*.cpp")
foreach(file alBnkfNew guLookAtRef guMtxF2L guNormalize guOrthoF guPerspectiveF guRotateF guScaleF guLookAtF
        guTranslateF osAiSetFrequency)
    list(APPEND mario_sources "${mario}/lib/src/${file}.c")
endforeach()
list(FILTER mario_sources EXCLUDE REGEX "\\.inc\\.c$|/src/game/main\\.c$|/src/pc/dlmalloc\\.c$|/src/port/(web|android)/")
# Nativecade restores the original game's C globals before each later start (NativecadeRuntime.mm).
# Upstream builds its C code without strict aliasing; with it, the camera breaks.
set(mario_c ${mario_sources})
list(FILTER mario_c INCLUDE REGEX "\\.c$")
set_property(SOURCE ${mario_c} APPEND PROPERTY COMPILE_OPTIONS -fno-strict-aliasing
    -include "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game/GameStateSection.h")
add_library(NativecadeGhostshipObjects OBJECT ${mario_sources} GhostshipRuntime.mm GhostshipRestart.cpp
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_pi.cpp" "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_vm.cpp"
    # Shipwright doesn't use the event debugger, so the shared runtime doesn't build it.
    "${RECOMPTV_LUS_SOURCE}/src/ship/window/gui/EventDebuggerWindow.cpp")
set_target_properties(NativecadeGhostshipObjects PROPERTIES C_STANDARD 11)
# Upstream also defines GBI_FLOATS. The shared Fast3D interpreter reads the N64's fixed-point
# matrices, which Ghostship's code still supports.
target_compile_definitions(NativecadeGhostshipObjects PRIVATE VERSION_US=1 ENABLE_RUMBLE=1 F3D_OLD=1 F3D_GBI=1
    _LANGUAGE_C _USE_MATH_DEFINES AVOID_UB=1 __IOS__ PLATFORM_IOS=1 RECOMPTV_TVOS SDL_MAIN_HANDLED
    SPDLOG_ACTIVE_LEVEL=2)
# Prepared assets depend on the game release and the shared Torch.
string(SUBSTRING "${RECOMPTV_TORCH_REVISION}" 0 7 recomptv_torch_short)
target_compile_definitions(NativecadeGhostshipObjects PRIVATE
    NATIVECADE_MARIO_PREPARED="Ghostship-${RECOMPTV_GHOSTSHIP_RELEASE}-torch${recomptv_torch_short}")
target_compile_options(NativecadeGhostshipObjects PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden
    -Wno-narrowing -Wno-unknown-pragmas -Wno-return-type
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
set_source_files_properties("${mario}/src/port/Game.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeGhostshipMain")
target_include_directories(NativecadeGhostshipObjects PRIVATE "${mario}" "${mario}/include" "${mario}/src"
    "${dr_libs_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game"
    "${RECOMPTV_LUS_SOURCE}/include/libultraship")
# OBJECT usage requirements supply matching dependency headers without linking
# a second SDL or libultraship copy into the game framework.
target_link_libraries(NativecadeGhostshipObjects PRIVATE libultraship torch vorbisfile)
add_library(NativecadeGhostship SHARED $<TARGET_OBJECTS:NativecadeGhostshipObjects>)
target_link_libraries(NativecadeGhostship PRIVATE RecompTVShipwright libzip::zip "-framework Foundation" "-framework UIKit")
set_target_properties(NativecadeGhostship PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeGhostship
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/GhostshipRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.ghostship"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${RECOMPTV_GHOSTSHIP_RELEASE}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
