# Linux GNU (shared by every architecture): the pinned Zig with a glibc 2.28
# baseline, so the build does not depend on the runner's glibc, GCC or
# libstdc++. The arch file sets CMAKE_SYSTEM_PROCESSOR and LIZZIE_ZIG_CPU first.
set(CMAKE_SYSTEM_NAME Linux CACHE STRING "")
set(LIZZIE_ZIG_TARGET "${CMAKE_SYSTEM_PROCESSOR}-linux-gnu.2.28" CACHE STRING "")
set(LIZZIE_LINK_LIBRARIES "c++" CACHE STRING "")
include("${CMAKE_CURRENT_LIST_DIR}/zig.cmake")
