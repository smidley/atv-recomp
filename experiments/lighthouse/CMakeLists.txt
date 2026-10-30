# Included by the Nativecade runtime build, like experiments/ghostship. Game code has hidden
# symbols, while SDL, Metal, libultraship, audio codecs and Torch come from the shared runtime.
set(bk "${RECOMPTV_LIGHTHOUSE_SOURCE}")
# Upstream's source list. Networking is off (USE_NETWORKING), so Anchor multiplayer is unavailable.
file(GLOB_RECURSE bk_sources CONFIGURE_DEPENDS "${bk}/src/*.c" "${bk}/src/*.cpp" "${bk}/lib/ultralib/*.c")
# The Flag Tracer's name tables, generated from include/enums.h by upstream's script.
block()
    set(CMAKE_CURRENT_SOURCE_DIR "${bk}")
    set(CMAKE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}")
    include("${bk}/cmake/GenerateFlagNames.cmake")
endblock()
# Nativecade restores the original game's C globals before each later start (NativecadeRuntime.mm).
set(bk_c ${bk_sources})
list(FILTER bk_c INCLUDE REGEX "\\.c$")
set_property(SOURCE ${bk_c} APPEND PROPERTY COMPILE_OPTIONS
    -include "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game/GameStateSection.h")
add_library(NativecadeLighthouseObjects OBJECT ${bk_sources} LighthouseRuntime.mm LighthouseRestart.cpp
    # libultraship sources that the shared runtime doesn't build, because Shipwright doesn't use them.
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_pi.cpp" "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_vm.cpp"
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/bridge/gfxbridge.cpp")
set_target_properties(NativecadeLighthouseObjects PROPERTIES C_STANDARD 11)
# Upstream also defines GBI_FLOATS. The shared Fast3D interpreter reads the N64's fixed-point
# matrices, which Lighthouse's code still supports. The file picker is libultraship's ImGui browser.
target_compile_definitions(NativecadeLighthouseObjects PRIVATE VERSION_US=1 ENABLE_RUMBLE=1 F3DEX_GBI=1
    _LANGUAGE_C _USE_MATH_DEFINES CIMGUI_DEFINE_ENUMS_AND_STRUCTS NON_MATCHING=1 NON_EQUIVALENT=1 AVOID_UB=1
    N_MICRO=1 LIGHTHOUSE_NATIVE_FILE_DIALOG=0 __IOS__ RECOMPTV_TVOS SDL_MAIN_HANDLED SPDLOG_ACTIVE_LEVEL=2)
# Prepared assets depend on the game release and the shared Torch.
string(SUBSTRING "${RECOMPTV_TORCH_REVISION}" 0 7 recomptv_torch_short)
target_compile_definitions(NativecadeLighthouseObjects PRIVATE
    NATIVECADE_BANJO_PREPARED="Lighthouse-${RECOMPTV_LIGHTHOUSE_RELEASE}-torch${recomptv_torch_short}")
# Upstream builds all of its code without strict aliasing.
target_compile_options(NativecadeLighthouseObjects PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden
    -fno-strict-aliasing -Wno-narrowing -Wno-unknown-pragmas -Wno-return-type
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion;-Wno-implicit-function-declaration>
    $<$<COMPILE_LANGUAGE:CXX>:-Wno-c++11-narrowing;-Wno-deprecated-enum-enum-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
set_source_files_properties("${bk}/src/port/Game.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeLighthouseMain")
target_include_directories(NativecadeLighthouseObjects PRIVATE "${bk}" "${bk}/include" "${bk}/lib/ultralib/include"
    "${bk}/src" "${CMAKE_CURRENT_BINARY_DIR}/generated" "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game"
    "${RECOMPTV_LUS_SOURCE}/include/libultraship")
# OBJECT usage requirements supply matching dependency headers without linking
# a second SDL or libultraship copy into the game framework.
target_link_libraries(NativecadeLighthouseObjects PRIVATE libultraship torch vorbisfile)
add_library(NativecadeLighthouse SHARED $<TARGET_OBJECTS:NativecadeLighthouseObjects>)
target_link_libraries(NativecadeLighthouse PRIVATE RecompTVShipwright libzip::zip "-framework Foundation" "-framework UIKit")
set_target_properties(NativecadeLighthouse PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeLighthouse
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/LighthouseRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.lighthouse"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${RECOMPTV_LIGHTHOUSE_RELEASE}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
