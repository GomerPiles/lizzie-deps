# Linux GNU (shared by every architecture): Vulkan with Wayland WSI only,
# one static library linked against the system libstdc++. Built on the
# Ubuntu 24.04 runner image, which sets the glibc 2.39 / GCC 13 baseline.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE STRING "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_WAYLAND ON CACHE BOOL "")
set(DAWN_USE_X11 OFF CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
