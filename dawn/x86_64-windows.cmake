# Windows x64: D3D12, D3D11 and Vulkan in one DLL with an import library, so
# consumers link without an MSVC C++ toolchain. The MSVC runtime is static.
# Shader compilation uses the system d3dcompiler_47.dll (FXC); DXC is not built.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded CACHE STRING "")
set(ABSL_MSVC_STATIC_RUNTIME ON CACHE BOOL "")

# Optimized code with a PDB for the DLL, published as a separate symbols
# archive. /Z7 keeps debug info in each object so parallel compiles never share
# a PDB; /DEBUG turns off /OPT:REF and /OPT:ICF, so they are restored, and
# /PDBALTPATH records only the PDB's file name instead of the runner's path.
# The name is literal because MSBuild mangles the linker's %_PDB% to
# %webgpu_dawn.pdb%; webgpu_dawn is the only shared library in this build, and
# package.cmake checks the recorded name.
set(CMAKE_POLICY_DEFAULT_CMP0141 NEW CACHE STRING "")
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded CACHE STRING "")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE
    "/INCREMENTAL:NO /DEBUG /OPT:REF /OPT:ICF /PDBALTPATH:webgpu_dawn.pdb" CACHE STRING "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY SHARED CACHE STRING "")
set(DAWN_ENABLE_D3D12 ON CACHE BOOL "")
set(DAWN_ENABLE_D3D11 ON CACHE BOOL "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_BUILT_DXC OFF CACHE BOOL "")
set(DAWN_FORCE_SYSTEM_COMPONENT_LOAD ON CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;directx-headers/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
