# Linux GNU (shared by every architecture): Vulkan with Wayland WSI only, one
# static library compiled by the pinned `zig c++` against Zig's bundled libc++
# and a glibc 2.28 baseline, so the build does not depend on the runner's
# glibc, GCC or libstdc++. Consumers link Zig's libc++ (`linkLibCpp`) from the
# same Zig version. The arch file sets CMAKE_SYSTEM_PROCESSOR first.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_SYSTEM_NAME Linux CACHE STRING "")
foreach(lang C CXX)
    set(CMAKE_${lang}_COMPILER_TARGET "${CMAKE_SYSTEM_PROCESSOR}-linux-gnu.2.28" CACHE STRING "")
    # Unlike clang and GCC, `zig cc` emits debug info unless told otherwise.
    set(CMAKE_${lang}_FLAGS "-g0" CACHE STRING "")
endforeach()
set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig/cc" CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig/c++" CACHE FILEPATH "")
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/zig/ar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/zig/ranlib" CACHE FILEPATH "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE STRING "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_WAYLAND ON CACHE BOOL "")
set(DAWN_USE_X11 OFF CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
