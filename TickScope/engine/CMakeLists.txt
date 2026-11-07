cmake_minimum_required(VERSION 3.24)
project(tickscope_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(TICKSCOPE_SANITIZE "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
option(TICKSCOPE_TSAN "Build with ThreadSanitizer" OFF)
option(TICKSCOPE_BUILD_BENCH "Build Google Benchmark suites" ON)

if(TICKSCOPE_SANITIZE AND TICKSCOPE_TSAN)
  message(FATAL_ERROR "ASan/UBSan and TSan cannot be combined")
endif()

# ---- Dependencies (pinned release tarballs) --------------------------------
include(FetchContent)

FetchContent_Declare(googletest
  URL https://github.com/google/googletest/releases/download/v1.15.2/googletest-1.15.2.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

if(TICKSCOPE_BUILD_BENCH)
  FetchContent_Declare(benchmark
    URL https://github.com/google/benchmark/archive/refs/tags/v1.9.1.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
  set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE BOOL "" FORCE)
  set(BENCHMARK_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
  set(BENCHMARK_ENABLE_WERROR OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(benchmark)
endif()

# ---- Shared compile settings for project targets only ----------------------
add_library(tickscope_options INTERFACE)
target_compile_options(tickscope_options INTERFACE -Wall -Wextra -Wpedantic -Werror)

if(TICKSCOPE_SANITIZE)
  target_compile_options(tickscope_options INTERFACE
    -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all)
  target_link_options(tickscope_options INTERFACE -fsanitize=address,undefined)
endif()

if(TICKSCOPE_TSAN)
  target_compile_options(tickscope_options INTERFACE -fsanitize=thread -fno-omit-frame-pointer)
  target_link_options(tickscope_options INTERFACE -fsanitize=thread)
endif()

# ---- Engine library ---------------------------------------------------------
add_library(tickscope_core STATIC
  src/order_book.cpp
  src/order_book_v2.cpp
  src/market_data.cpp
  src/generator.cpp
)
target_include_directories(tickscope_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(tickscope_core PUBLIC tickscope_options)

# ---- Replay driver / end-to-end benchmark ------------------------------------
add_executable(tickscope_replay src/main.cpp)
target_link_libraries(tickscope_replay PRIVATE tickscope_core)
string(TOUPPER "${CMAKE_BUILD_TYPE}" _bt)
target_compile_definitions(tickscope_replay PRIVATE
  TICKSCOPE_BUILD_INFO="${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} ${CMAKE_BUILD_TYPE} ${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_${_bt}}")

# ---- Tests and benchmarks ---------------------------------------------------
enable_testing()
add_subdirectory(tests)

if(TICKSCOPE_BUILD_BENCH)
  add_subdirectory(bench)
endif()
