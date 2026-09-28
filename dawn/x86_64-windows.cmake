# Windows x64: compile D3D12, D3D11 and Vulkan once into a static library.
# dawn/windows links a DLL from that archive. Both use the static MSVC runtime.
# Shader compilation uses the system d3dcompiler_47.dll (FXC); DXC is not built.
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded CACHE STRING "")
set(ABSL_MSVC_STATIC_RUNTIME ON CACHE BOOL "")

# Optimized code with separate PDBs for the static library and the DLL, each
# published as its own symbols archive. /Zi keeps debug info out of the objects;
# dawn/windows names a compiler PDB for each target in the static archive.
# /DEBUG turns off /OPT:REF and /OPT:ICF, so they are restored, and
# /PDBALTPATH records only the DLL PDB's file name instead of the runner's path.
# The name is literal because MSBuild mangles the linker's %_PDB% to
# %webgpu_dawn.pdb%; webgpu_dawn is the only shared library in this build, and
# package.cmake checks the recorded name.
set(CMAKE_POLICY_DEFAULT_CMP0141 NEW CACHE STRING "")
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT ProgramDatabase CACHE STRING "")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE
    "/INCREMENTAL:NO /DEBUG /OPT:REF /OPT:ICF /PDBALTPATH:webgpu_dawn.pdb" CACHE STRING "")

set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE STRING "")
set(DAWN_ENABLE_D3D12 ON CACHE BOOL "")
set(DAWN_ENABLE_D3D11 ON CACHE BOOL "")
set(DAWN_ENABLE_VULKAN ON CACHE BOOL "")
set(DAWN_USE_BUILT_DXC OFF CACHE BOOL "")
set(DAWN_FORCE_SYSTEM_COMPONENT_LOAD ON CACHE BOOL "")

set(LIZZIE_NOTICE_DIRS
    "abseil-cpp;webgpu-headers/src;directx-headers/src;spirv-headers/src;spirv-tools/src;vulkan-headers/src;vulkan-utility-libraries/src"
    CACHE STRING "")
