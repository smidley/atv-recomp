cmake_minimum_required(VERSION 3.20)
project(RecompTVRuntimeCoreProbe LANGUAGES C CXX)

# This is intentionally separate from the app. No ROM, generated game code,
# librecomp, LiveRecomp, RT64, SDL, or desktop launcher is built here.
if(NOT EXISTS "${RECOMPTV_RUNTIME_SOURCE}/ultramodern/CMakeLists.txt")
    message(FATAL_ERROR "Set RECOMPTV_RUNTIME_SOURCE to the pinned N64ModernRuntime checkout")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(Threads REQUIRED)

add_subdirectory("${RECOMPTV_RUNTIME_SOURCE}/ultramodern" upstream)
add_executable(runtime_callbacks RuntimeCallbacks.cpp)
target_link_libraries(runtime_callbacks PRIVATE ultramodern Threads::Threads)
target_compile_options(runtime_callbacks PRIVATE -Wall -Wextra -Werror -pedantic)

# A cross-compiled executable is a link check, not evidence of simulator execution.
if(NOT CMAKE_CROSSCOMPILING)
    enable_testing()
    add_test(NAME runtime_callbacks COMMAND runtime_callbacks)
endif()
