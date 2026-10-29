# Included by the Nativecade runtime build. Game code has hidden symbols, while
# SDL, Metal, libultraship, audio codecs and Torch come from the shared runtime.
# These engine objects aren't referenced by Shipwright but are needed by MK64.
target_sources(RecompTVShipwright PRIVATE
    "${RECOMPTV_LUS_SOURCE}/src/ship/window/gui/GuiMenuBar.cpp"
    "${RECOMPTV_LUS_SOURCE}/src/fast/resource/factory/LightFactory.cpp"
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/window/gui/InputEditorWindow.cpp"
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/AudioDmaRegistry.cpp"
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_eeprom.cpp")
include(FetchContent)
FetchContent_Declare(tomlplusplus GIT_REPOSITORY https://github.com/marzer/tomlplusplus.git
    GIT_TAG 30172438cee64926dc41fdd9c11fb3ba5b2ba9de)
FetchContent_Declare(nativecade_semver GIT_REPOSITORY https://github.com/Neargye/semver.git
    GIT_TAG ccbbfdf2f862a48498d37d5955743a5082ee49bf)
FetchContent_Declare(nativecade_sse2neon GIT_REPOSITORY https://github.com/DLTcollab/sse2neon.git
    GIT_TAG 2272251cc3ad9cba8b8c47c4065811cfb396b802)
FetchContent_MakeAvailable(tomlplusplus nativecade_semver nativecade_sse2neon)
set(kart "${RECOMPTV_SPAGHETTIKART_SOURCE}")
file(GLOB kart_sources CONFIGURE_DEPENDS "${kart}/src/*.c")
foreach(folder buffers data debug ending racing audio port mods engine enhancements)
    file(GLOB_RECURSE files CONFIGURE_DEPENDS "${kart}/src/${folder}/*.c" "${kart}/src/${folder}/*.cpp")
    list(APPEND kart_sources ${files})
endforeach()
file(GLOB_RECURSE files CONFIGURE_DEPENDS "${kart}/assets/code/*.c" "${kart}/courses/*.c")
list(APPEND kart_sources ${files})
foreach(file guLookAtF guPerspectiveF guMtxF2L guRotateF guOrthoF guScaleF guTranslateF guMtxCatF guMtxCatL guNormalize)
    list(APPEND kart_sources "${kart}/src/os/${file}.c")
endforeach()
list(FILTER kart_sources EXCLUDE REGEX "\\.inc\\.c$|/debug/crash_screen_enhancement\\.c$")
add_library(NativecadeSpaghettiObjects OBJECT ${kart_sources} SpaghettiRuntime.mm SimulatorInputProbe.cpp
    "${RECOMPTV_LUS_SOURCE}/src/libultraship/libultra/os_pi.cpp"
    # XML commands must use MK64's F3DEX encoding, not Shipwright's F3DEX2.
    "${RECOMPTV_LUS_SOURCE}/src/fast/resource/factory/DisplayListFactory.cpp")
set_target_properties(NativecadeSpaghettiObjects PROPERTIES C_STANDARD 11)
target_compile_definitions(NativecadeSpaghettiObjects PRIVATE VERSION_US=1 ENABLE_RUMBLE=1 F3DEX_GBI=1
    _LANGUAGE_C _USE_MATH_DEFINES CIMGUI_DEFINE_ENUMS_AND_STRUCTS NON_MATCHING=1 NON_EQUIVALENT=1
    AVOID_UB=1 SPAGHETTI_VERSION="1.0.0" __IOS__ PLATFORM_IOS=1 RECOMPTV_TVOS SDL_MAIN_HANDLED
    EXCLUDE_MPQ_SUPPORT _CONSOLE UNICODE _UNICODE SPDLOG_ACTIVE_LEVEL=2)
target_compile_options(NativecadeSpaghettiObjects PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden
    -Wno-narrowing -Wno-deprecated-enum-enum-conversion -Wno-unknown-pragmas -Wno-return-type
    $<$<COMPILE_LANGUAGE:C>:-Wno-incompatible-pointer-types;-Wno-int-conversion>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
set_source_files_properties("${kart}/src/port/Game.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeSpaghettiMain")
target_include_directories(NativecadeSpaghettiObjects PRIVATE "${kart}" "${kart}/include" "${kart}/include/assets"
    "${kart}/src" "${dr_libs_SOURCE_DIR}" "${nativecade_sse2neon_SOURCE_DIR}" "${nativecade_semver_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game" "${RECOMPTV_LUS_SOURCE}/include/libultraship")
foreach(folder racing ending data buffers audio debug engine engine/tracks engine/actors engine/objects engine/sky engine/particles enhancements enhancements/freecam)
    target_include_directories(NativecadeSpaghettiObjects PRIVATE "${kart}/src/${folder}")
endforeach()
# OBJECT usage requirements supply matching dependency headers without linking
# a second SDL or libultraship copy into the game framework.
target_link_libraries(NativecadeSpaghettiObjects PRIVATE libultraship torch tomlplusplus::tomlplusplus vorbisfile)
add_library(NativecadeSpaghetti SHARED $<TARGET_OBJECTS:NativecadeSpaghettiObjects>)
target_link_libraries(NativecadeSpaghetti PRIVATE RecompTVShipwright libzip::zip "-framework Foundation" "-framework UIKit")
set_target_properties(NativecadeSpaghetti PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeSpaghetti
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/SpaghettiRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.spaghettikart"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "1.0.0" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
