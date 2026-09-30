# macOS arm64: static libraries compiled by AppleClang against the system
# libc++, which consumers link (`c++.1` in Zig), as for Dawn.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "")
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "")
# Apple M1 is the minimum CPU. libssl, like libcrypto, needs no exceptions or
# RTTI (see zig.cmake).
set(CMAKE_C_FLAGS "-mcpu=apple-m1" CACHE STRING "")
set(CMAKE_CXX_FLAGS "-mcpu=apple-m1 -fno-exceptions -fno-rtti" CACHE STRING "")
foreach(lang C CXX)
    # BoringSSL appends -ggdb to CMAKE_<LANG>_FLAGS. Release flags come last.
    set(CMAKE_${lang}_FLAGS_RELEASE "-O3 -DNDEBUG -g0" CACHE STRING "")
endforeach()

set(LIZZIE_LINK_LIBRARIES "c++.1" CACHE STRING "")
