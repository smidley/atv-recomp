cmake_minimum_required(VERSION 3.26)
project(RecompTVShipwrightTools LANGUAGES C CXX)

# These executables run on the development Mac. Never cross-compile and then
# execute an asset tool as part of a simulator or device build.
if(CMAKE_CROSSCOMPILING OR NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    message(FATAL_ERROR "Configure these asset tools for the macOS host")
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POLICY_VERSION_MINIMUM 3.12)
find_package(Git REQUIRED)
function(require_revision source revision)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${source}" rev-parse HEAD
        OUTPUT_VARIABLE actual OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY)
    if(NOT actual STREQUAL revision)
        message(FATAL_ERROR "Wrong source revision at ${source}: expected ${revision}")
    endif()
endfunction()
require_revision("${RECOMPTV_SHIPWRIGHT_SOURCE}" f0599f96f8d442f26d0fa1c5cedafddacd56633f)
require_revision("${RECOMPTV_TORCH_SOURCE}" 2ab12fe9660aec04e02ee89fe81baed304a1a1d6)

include(FetchContent)
# First declarations win, pinning Torch's tag-based dependencies to commits.
FetchContent_Declare(spdlog GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG 486b55554f11c9cccc913e11a87085b2a91f706f OVERRIDE_FIND_PACKAGE)
FetchContent_Declare(yaml-cpp GIT_REPOSITORY https://github.com/jbeder/yaml-cpp.git
    GIT_TAG 56e3bb550c91fd7005566f19c079cb7a503223cf)
FetchContent_Declare(tinyxml2 GIT_REPOSITORY https://github.com/leethomason/tinyxml2.git
    GIT_TAG 321ea883b7190d4e85cae5512a12e5eaa8f8731f OVERRIDE_FIND_PACKAGE)
FetchContent_Declare(zlib GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG 51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf OVERRIDE_FIND_PACKAGE)
set(USE_STANDALONE OFF CACHE BOOL "" FORCE)
set(PORT_VERSION_ENDIANNESS ON CACHE BOOL "" FORCE)
set(ROM_CRC_BSWAP OFF CACHE BOOL "" FORCE)
set(BUILD_OOT ON CACHE BOOL "" FORCE)
foreach(feature UI STORMLIB SM64 MK64 SF64 PM64 FZERO BK64 MARIO_ARTIST NAUDIO)
    set(BUILD_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory("${RECOMPTV_TORCH_SOURCE}" torch)
target_compile_definitions(torch INTERFACE YAML_CPP_STATIC_DEFINE)

set(ship "${RECOMPTV_SHIPWRIGHT_SOURCE}/soh")
add_executable(soh-torch ExtractROM.cpp
    "${ship}/soh/Extractor/TorchExtract.cpp")
target_include_directories(soh-torch PRIVATE "${ship}/soh/Extractor")
target_link_libraries(soh-torch PRIVATE torch)
add_executable(soh-o2r-packer "${ship}/assets/tools/soh-o2r-packer/main.cpp"
    "${ship}/assets/tools/soh-o2r-packer/PngTexture.cpp")
target_link_libraries(soh-o2r-packer PRIVATE torch)
