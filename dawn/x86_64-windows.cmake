# Windows x64: compile D3D12, D3D11 and Vulkan into a static archive that
# dawn/windows links into webgpu_dawn.dll, using the static MSVC runtime. D3D12
# compiles shaders with the built DXC (dxcompiler.dll plus the Windows SDK's
# dxil.dll) on Shader Model 6+ hardware and FXC otherwise; D3D11 uses FXC.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded CACHE STRING "")
set(ABSL_MSVC_STATIC_RUNTIME ON CACHE BOOL "")

# CMake's MSVC defaults plus /arch:AVX2, MSVC's x86-64-v3 baseline.
set(CMAKE_C_FLAGS "/DWIN32 /D_WINDOWS /arch:AVX2" CACHE STRING "")
set(CMAKE_CXX_FLAGS "/DWIN32 /D_WINDOWS /GR /EHsc /arch:AVX2" CACHE STRING "")

# Optimized code with PDBs, published as a separate symbols archive. /Z7 keeps
# debug info in each object so parallel compiles never share a PDB; /DEBUG
# turns off /OPT:REF and /OPT:ICF, so they are restored. dawn/windows makes
# each DLL record only its PDB's file name instead of the runner's path.
set(CMAKE_POLICY_DEFAULT_CMP0141 NEW CACHE STRING "")
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded CACHE STRING "")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "/INCREMENTAL:NO /DEBUG /OPT:REF /OPT:ICF" CACHE STRING "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE STRING "")
set(DAWN_ENABLE_D3D12 ON CACHE BOOL "")
set(DAWN_ENABLE_D3D11 ON CACHE BOOL "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_BUILT_DXC ON CACHE BOOL "")
set(DAWN_FORCE_SYSTEM_COMPONENT_LOAD ON CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;directx-headers/src;directx-shader-compiler/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
