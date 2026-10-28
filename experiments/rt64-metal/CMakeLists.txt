cmake_minimum_required(VERSION 3.20)
project(RecompTVMetalBackendProbe LANGUAGES CXX OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS")
    message(FATAL_ERROR "This experiment must target the tvOS SDK")
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

add_library(rt64_metal STATIC
    "${RECOMPTV_RT64_PATCHED}/src/metal/rt64_metal.cpp"
    TVWindow.cpp
    SDKContract.mm
)
target_include_directories(rt64_metal PUBLIC
    "${RECOMPTV_RT64_PATCHED}/src"
    "${RECOMPTV_RT64_PATCHED}/src/metal"
    "${RECOMPTV_RT64_SOURCE}/src"
    "${RECOMPTV_RT64_SOURCE}/src/contrib"
    "${RECOMPTV_RT64_SOURCE}/src/contrib/metal-cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_options(rt64_metal PRIVATE -fblocks)
set_source_files_properties(SDKContract.mm PROPERTIES
    COMPILE_OPTIONS "-Werror=unguarded-availability;-Werror=unguarded-availability-new")
foreach(framework Metal Foundation QuartzCore CoreGraphics CoreFoundation)
    find_library(${framework}_LIBRARY ${framework} REQUIRED)
    target_link_libraries(rt64_metal PUBLIC "${${framework}_LIBRARY}")
endforeach()

add_executable(rt64_metal_link LinkProbe.cpp)
target_link_libraries(rt64_metal_link PRIVATE rt64_metal)
