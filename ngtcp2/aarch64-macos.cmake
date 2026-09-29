# macOS arm64: static libraries compiled by AppleClang against the system
# libc++, which consumers link (`c++.1` in Zig), as for Dawn.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "")
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "")
foreach(lang C CXX)
    # Apple M1 is the minimum CPU.
    set(CMAKE_${lang}_FLAGS "-mcpu=apple-m1" CACHE STRING "")
    # BoringSSL appends -ggdb to CMAKE_<LANG>_FLAGS. Release flags come last.
    set(CMAKE_${lang}_FLAGS_RELEASE "-O3 -DNDEBUG -g0" CACHE STRING "")
endforeach()

set(LIZZIE_LINK_LIBRARIES "c++.1" CACHE STRING "")
