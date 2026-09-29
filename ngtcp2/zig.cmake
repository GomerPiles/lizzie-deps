# Targets compiled by the pinned `zig cc`/`zig c++` against Zig's bundled libc
# and libc++. BoringSSL's libssl uses the C++ runtime, so consumers link Zig's
# libc++ (`link_libcpp`) from the same Zig version. The target file sets
# CMAKE_SYSTEM_NAME, CMAKE_SYSTEM_PROCESSOR, the Zig target LIZZIE_ZIG_TARGET
# and the minimum CPU LIZZIE_ZIG_CPU first.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

foreach(lang C CXX ASM)
    set(CMAKE_${lang}_COMPILER_TARGET "${LIZZIE_ZIG_TARGET}" CACHE STRING "")
endforeach()
foreach(lang C CXX)
    set(CMAKE_${lang}_FLAGS "-mcpu=${LIZZIE_ZIG_CPU}" CACHE STRING "")
    # Unlike clang and GCC, `zig cc` emits debug info unless told otherwise, and
    # BoringSSL appends -ggdb to CMAKE_<LANG>_FLAGS. Release flags come last.
    set(CMAKE_${lang}_FLAGS_RELEASE "-O3 -DNDEBUG -g0" CACHE STRING "")
endforeach()
set(CMAKE_ASM_FLAGS_RELEASE "-g0" CACHE STRING "")
set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig/cc" CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${CMAKE_CURRENT_LIST_DIR}/zig/c++" CACHE FILEPATH "")
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/zig/ar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/zig/ranlib" CACHE FILEPATH "")
