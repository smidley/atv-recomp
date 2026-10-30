# Included by the Nativecade runtime build, like experiments/lighthouse. The game's code is generated
# from the player's ROM (scripts/generate-sote-code.sh); without it, in CI or on another Mac, the
# framework only reports that this build doesn't include the game (SoteUnavailable.cpp).
if(NOT RECOMPTV_SOTE_SOURCE OR NOT EXISTS "${RECOMPTV_SOTE_SOURCE}/generated/aspMain.cpp")
    add_library(NativecadeSote SHARED SoteUnavailable.cpp)
else()
# The game code, N64ModernRuntime and RT64 have hidden symbols; SDL comes from the shared runtime.
set(sote "${RECOMPTV_SOTE_SOURCE}")
set(sote_runtime "${sote}/third_party/N64ModernRuntime")
set(sote_rt64 "${sote}/third_party/rt64")
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_OBJC_VISIBILITY_PRESET hidden)
set(CMAKE_OBJCXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

# RT64 compiles its shaders while it builds: its tools run on the Mac (host-tools/CMakeLists.txt,
# RECOMPTV_SOTE_HOST_TOOLS) and the Metal compiler targets this SDK.
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(RECOMPTV_SOTE_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET}-simulator)
else()
    set(RECOMPTV_SOTE_METAL_TARGET -target air64-apple-tvos${CMAKE_OSX_DEPLOYMENT_TARGET})
endif()
set(RT64_STATIC TRUE)
set(SDL2_INCLUDE_DIRS "$<TARGET_PROPERTY:SDL2-static,INTERFACE_INCLUDE_DIRECTORIES>")
add_subdirectory("${sote_rt64}" rt64)
add_subdirectory("${sote_runtime}" runtime)

# The game's code, generated from the ROM by N64Recomp, with SotE's hooks.
file(GLOB sote_recompiled CONFIGURE_DEPENDS "${sote}/generated/RecompiledFuncs/*.c")
add_library(NativecadeSoteGameCode OBJECT ${sote_recompiled})
target_include_directories(NativecadeSoteGameCode PRIVATE "${sote_runtime}/ultramodern/include"
    "${sote_runtime}/librecomp/include" "${sote_runtime}/N64Recomp/include")
target_compile_options(NativecadeSoteGameCode PRIVATE -include "${sote}/src/recomp_hooks.h" -fno-strict-aliasing
    -Wno-unused-variable -Wno-implicit-function-declaration)
# Upstream's C standard: the code calls runtime functions it doesn't declare, which C23 forbids.
set_target_properties(NativecadeSoteGameCode PROPERTIES C_STANDARD 17)

# SotE's host program (upstream's SOTE_RUNTIME_SOURCES) and its audio microcode, from RSPRecomp.
set(sote_sources controls_menu.cpp control_bindings.cpp modern_controls.cpp modern_aim.cpp frontend.cpp
    graphics_menu.cpp menu_model.cpp menu_canvas.cpp hud_labels.cpp menu_skin.cpp menu_renderer.cpp hd_audio.cpp
    pc_voices.cpp hd_music.cpp san_movies.cpp music_replacement.cpp libultra_stubs.c main.cpp
    register_overlays.cpp rt64_renderer.cpp)
list(TRANSFORM sote_sources PREPEND "${sote}/src/")
add_library(NativecadeSoteObjects OBJECT ${sote_sources} "${sote}/generated/aspMain.cpp"
    SoteRuntime.mm SoteRestart.cpp AppleTVStubs.cpp)
add_dependencies(NativecadeSoteObjects rt64)
set_source_files_properties("${sote}/src/main.cpp" PROPERTIES COMPILE_DEFINITIONS "main=NativecadeSoteMain")
# SDL_MAIN_HANDLED stops SDL's tvOS header from renaming main to SDL_main.
target_compile_definitions(NativecadeSoteObjects PRIVATE NOMINMAX SDL_MAIN_HANDLED)
# OBJECT usage requirements supply the runtime's headers (sse2neon, concurrentqueue, rabbitizer).
target_link_libraries(NativecadeSoteObjects PRIVATE librecomp ultramodern N64Recomp)
target_compile_options(NativecadeSoteObjects PRIVATE -fno-strict-aliasing -fms-extensions
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_include_directories(NativecadeSoteObjects PRIVATE "${sote}/generated/RecompiledFuncs" "${CMAKE_BINARY_DIR}/src"
    "${sote_runtime}/ultramodern/include" "${sote_runtime}/librecomp/include" "${sote_runtime}/N64Recomp/include"
    "${sote_rt64}/include" "${sote_rt64}/src" "${sote_rt64}/src/rhi" "${sote_rt64}/src/render" "${sote_rt64}/src/contrib"
    "${sote_rt64}/src/contrib/plume" "${sote_rt64}/src/contrib/imgui" "${sote_rt64}/src/contrib/hlslpp/include"
    "${sote_rt64}/src/contrib/nativefiledialog-extended/src/include" "${sote}/third_party/sandec"
    "${CMAKE_CURRENT_LIST_DIR}/../shipwright/simulator-game" "${SDL2_INCLUDE_DIRS}")

add_library(NativecadeSote SHARED $<TARGET_OBJECTS:NativecadeSoteObjects> $<TARGET_OBJECTS:NativecadeSoteGameCode>)
target_link_libraries(NativecadeSote PRIVATE rt64 librecomp ultramodern RecompTVShipwright
    "-framework Foundation" "-framework UIKit" "-framework Metal" "-framework QuartzCore")
endif()
set_target_properties(NativecadeSote PROPERTIES FRAMEWORK TRUE OUTPUT_NAME NativecadeSote
    PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/SoteRuntime.h"
    MACOSX_FRAMEWORK_IDENTIFIER "com.smidley.nativecade.sote"
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${RECOMPTV_SOTE_RELEASE}" MACOSX_FRAMEWORK_BUNDLE_VERSION "1"
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
