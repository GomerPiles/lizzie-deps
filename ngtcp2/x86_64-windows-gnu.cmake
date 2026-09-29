# Windows x86_64 GNU, for Lizzie's local cross builds: the pinned Zig against
# its MinGW-w64 libc, with NASM for BoringSSL's assembly. It is cross-compiled
# on Linux, so its tests do not run; the MSVC target runs them on Windows.
set(CMAKE_SYSTEM_NAME Windows CACHE STRING "")
set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "")
set(LIZZIE_ZIG_TARGET x86_64-windows-gnu CACHE STRING "")
set(LIZZIE_ZIG_CPU x86_64_v3 CACHE STRING "")
set(LIZZIE_LINK_LIBRARIES "c++ ws2_32 bcrypt" CACHE STRING "")
set(BUILD_TESTING OFF CACHE BOOL "")
include("${CMAKE_CURRENT_LIST_DIR}/zig.cmake")
