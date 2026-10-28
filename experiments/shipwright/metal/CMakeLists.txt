cmake_minimum_required(VERSION 3.24)
project(RecompTVShipwrightMetal LANGUAGES C CXX OBJC OBJCXX)
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
# The upstream mobile-mode flag is PRIVATE; the link fixture needs matching headers.
add_executable(shipwright_metal_link LinkProbe.cpp SDKContract.mm)
target_compile_definitions(shipwright_metal_link PRIVATE __IOS__ SDL_MAIN_HANDLED)
set_source_files_properties(SDKContract.mm PROPERTIES
    COMPILE_OPTIONS "-Werror=unguarded-availability;-Werror=unguarded-availability-new")
# Force every libultraship object through the linker, including the real backend.
target_link_libraries(shipwright_metal_link PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,libultraship>")
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/link-probe-path.txt"
    CONTENT "$<TARGET_FILE:shipwright_metal_link>\n")
