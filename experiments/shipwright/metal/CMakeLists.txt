cmake_minimum_required(VERSION 3.24)
project(RecompTVShipwrightMetal LANGUAGES C CXX OBJC OBJCXX)
include("${CMAKE_CURRENT_LIST_DIR}/../../../upstream/pins.cmake")
if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS")
    message(FATAL_ERROR "This experiment must use the tvOS SDK")
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# No host package or desktop graphics API may enter this cross-build.
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ENABLE_SCRIPTING OFF CACHE BOOL "" FORCE)
set(DISABLE_DLL_LOADER ON CACHE BOOL "" FORCE)
set(INCLUDE_MPQ_SUPPORT OFF CACHE BOOL "" FORCE)
set(GFX_DEBUG_DISASSEMBLER OFF CACHE BOOL "" FORCE)
set(LUS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PRISM_STANDALONE OFF CACHE BOOL "" FORCE)
set(GBI_UCODE F3DEX_GBI_2 CACHE STRING "" FORCE)
set(SIGN_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_OPENGL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
set(SDL_METAL ON CACHE BOOL "" FORCE)
set(SDL_RENDER_METAL ON CACHE BOOL "" FORCE)
set(tinyxml2_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
foreach(option ENABLE_BZIP2 ENABLE_LZMA ENABLE_ZSTD ENABLE_OPENSSL ENABLE_GNUTLS
        ENABLE_MBEDTLS ENABLE_COMMONCRYPTO BUILD_TOOLS BUILD_REGRESS BUILD_EXAMPLES
        BUILD_DOC BUILD_OSSFUZZ)
    set(${option} OFF CACHE BOOL "" FORCE)
endforeach()

add_subdirectory("${RECOMPTV_LUS_SOURCE}" libultraship)
target_compile_options(libultraship PRIVATE -fblocks)
target_include_directories(libultraship PRIVATE "${CMAKE_CURRENT_LIST_DIR}")
# The upstream mobile-mode flag is PRIVATE; the link fixture needs matching headers.
add_executable(shipwright_metal_link LinkProbe.cpp SDKContract.mm)
target_compile_definitions(shipwright_metal_link PRIVATE __IOS__ SDL_MAIN_HANDLED)
set_source_files_properties(SDKContract.mm PROPERTIES
    COMPILE_OPTIONS "-Werror=unguarded-availability;-Werror=unguarded-availability-new")
# Force every libultraship object through the linker, including the real backend.
target_link_libraries(shipwright_metal_link PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,libultraship>")
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/link-probe-path.txt"
    CONTENT "$<TARGET_FILE:shipwright_metal_link>\n")

# A separate installable diagnostic app, using SDL's UIKit bootstrap and the
# actual libultraship shader generator, renderer, and resource loader.
set(probe_archive "${CMAKE_CURRENT_BINARY_DIR}/probe-shaders.o2r")
add_custom_command(OUTPUT "${probe_archive}"
    COMMAND python3 "${CMAKE_CURRENT_SOURCE_DIR}/pack-probe-shaders.py"
        "${RECOMPTV_LUS_SOURCE}" "${probe_archive}"
    DEPENDS pack-probe-shaders.py
        "${RECOMPTV_LUS_SOURCE}/src/fast/shaders/metal/default.shader.metal"
        "${RECOMPTV_LUS_SOURCE}/LICENSE"
    VERBATIM)
add_custom_target(shipwright_probe_assets DEPENDS "${probe_archive}")
add_executable(shipwright_metal_render MACOSX_BUNDLE RenderProbe.mm)
add_dependencies(shipwright_metal_render shipwright_probe_assets)
target_compile_definitions(shipwright_metal_render PRIVATE __IOS__ SDL_MAIN_HANDLED
    RECOMPTV_LUS_REVISION="${RECOMPTV_LUS_REVISION}")
target_compile_options(shipwright_metal_render PRIVATE -fobjc-arc -fblocks
    -Werror=unguarded-availability -Werror=unguarded-availability-new)
target_link_libraries(shipwright_metal_render PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,libultraship>")
set_target_properties(shipwright_metal_render PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/RenderProbe-Info.plist.in"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.smidley.RecompTV.ShipwrightProbe"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "3")
add_custom_command(TARGET shipwright_metal_render POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${probe_archive}"
        "$<TARGET_BUNDLE_DIR:shipwright_metal_render>/probe-shaders.o2r"
    VERBATIM)
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/render-probe-path.txt"
    CONTENT "$<TARGET_BUNDLE_DIR:shipwright_metal_render>\n")

# tvOS 27 only launches apps that adopt the UIScene lifecycle. Standalone probe
# builds reuse the game's SDL scene adapter; the game build, which includes this
# file, applies that adapter itself together with its other SDL patches.
if(PROJECT_IS_TOP_LEVEL)
    include(FetchContent)
    FetchContent_GetProperties(SDL2 SOURCE_DIR recomptv_sdl_source)
    set(scene_patch "${CMAKE_CURRENT_LIST_DIR}/../simulator-game/sdl-scenes.patch")
    execute_process(COMMAND git apply --reverse --check "${scene_patch}"
        WORKING_DIRECTORY "${recomptv_sdl_source}" RESULT_VARIABLE scene_patch_applied
        OUTPUT_QUIET ERROR_QUIET)
    if(NOT scene_patch_applied EQUAL 0)
        execute_process(COMMAND git apply "${scene_patch}"
            WORKING_DIRECTORY "${recomptv_sdl_source}" COMMAND_ERROR_IS_FATAL ANY)
    endif()
    target_compile_definitions(SDL2-static PRIVATE RECOMPTV_TVOS_SCENES)
endif()
