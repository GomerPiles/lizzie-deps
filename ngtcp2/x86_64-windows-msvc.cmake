# Windows x86_64 MSVC, Lizzie's official Windows target: static libraries
# compiled by MSVC, with NASM for BoringSSL's assembly.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# /Zl records no C runtime in the objects, so the final link chooses it: Zig
# links the static release or debug runtime to match its optimize mode. The
# code is compiled for the static release runtime, which the executables built
# here (tests, and CMake's and ngtcp2's configure checks) name themselves.
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded CACHE STRING "")
set(CMAKE_EXE_LINKER_FLAGS
    "/machine:x64 /DEFAULTLIB:libcmt /DEFAULTLIB:libvcruntime /DEFAULTLIB:libucrt /DEFAULTLIB:libcpmt /DEFAULTLIB:oldnames"
    CACHE STRING "")

# CMake's MSVC defaults plus /arch:AVX2, MSVC's x86-64-v3 baseline, and /Zl.
set(CMAKE_C_FLAGS "/DWIN32 /D_WINDOWS /arch:AVX2 /Zl" CACHE STRING "")
set(CMAKE_CXX_FLAGS "/DWIN32 /D_WINDOWS /GR /EHsc /arch:AVX2 /Zl" CACHE STRING "")

set(LIZZIE_LINK_LIBRARIES "ws2_32 bcrypt" CACHE STRING "")
