# Windows x64: D3D12, D3D11 and Vulkan in one DLL with an import library, so
# consumers link without an MSVC C++ toolchain. The MSVC runtime is static.
# Shader compilation uses the system d3dcompiler_47.dll (FXC); DXC is not built.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded CACHE STRING "")
set(ABSL_MSVC_STATIC_RUNTIME ON CACHE BOOL "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY SHARED CACHE STRING "")
set(DAWN_ENABLE_D3D12 ON CACHE BOOL "")
set(DAWN_ENABLE_D3D11 ON CACHE BOOL "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_BUILT_DXC OFF CACHE BOOL "")
set(DAWN_FORCE_SYSTEM_COMPONENT_LOAD ON CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;directx-headers/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
