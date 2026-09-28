# macOS arm64: Metal, one static library linked against the system libc++.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "")
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "")
# Apple M1 is the minimum CPU.
set(CMAKE_C_FLAGS "-mcpu=apple-m1" CACHE STRING "")
set(CMAKE_CXX_FLAGS "-mcpu=apple-m1" CACHE STRING "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE STRING "")
set(DAWN_ENABLE_METAL ON CACHE BOOL "")
set(DAWN_ENABLE_VULKAN OFF CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS "abseil-cpp;webgpu-headers/src" CACHE STRING "")
