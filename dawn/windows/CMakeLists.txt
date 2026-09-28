cmake_minimum_required(VERSION 3.24)
project(DawnWindowsPackages LANGUAGES C CXX)
if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "Windows packages require the native MSVC toolchain")
endif()
if(NOT DEFINED DAWN_SOURCE_DIR)
    message(FATAL_ERROR "DAWN_SOURCE_DIR is required")
endif()
add_subdirectory("${DAWN_SOURCE_DIR}" upstream)

# Dawn is compiled into a static archive. Export only its public C API when
# linking the DLL; static objects contain no dllexport directives.
set(exports "${CMAKE_CURRENT_BINARY_DIR}/webgpu_dawn.def")
set(header "${CMAKE_CURRENT_BINARY_DIR}/upstream/gen/include/dawn/webgpu.h")
add_custom_command(OUTPUT "${exports}"
    COMMAND "${CMAKE_COMMAND}" "-DHEADER=${header}" "-DOUTPUT=${exports}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/exports.cmake"
    DEPENDS webgpu_dawn "${CMAKE_CURRENT_SOURCE_DIR}/exports.cmake"
    VERBATIM)
add_library(webgpu_dawn_shared SHARED shared_anchor.cpp "${exports}")
set_target_properties(webgpu_dawn_shared PROPERTIES
    LINKER_LANGUAGE CXX
    OUTPUT_NAME webgpu_dawn
    ARCHIVE_OUTPUT_NAME webgpu_dawn_dll)
target_link_libraries(webgpu_dawn_shared PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,webgpu_dawn>")

# /PDBALTPATH records only each PDB's file name instead of the runner's path.
# The names are literal because MSBuild mangles the linker's %_PDB% to
# %webgpu_dawn.pdb%; package.cmake checks the recorded names.
target_link_options(webgpu_dawn_shared PRIVATE /PDBALTPATH:webgpu_dawn.pdb)
target_link_options(dxcompiler PRIVATE /PDBALTPATH:dxcompiler.pdb)

# The archive's install rule is upstream's; package.cmake keeps only the DLL,
# its import library and the DXC libraries Dawn loads at runtime.
install(TARGETS webgpu_dawn_shared
    RUNTIME DESTINATION bin
    ARCHIVE DESTINATION lib)
install(FILES
        "$<TARGET_FILE:dxcompiler>"
        "$<TARGET_PDB_FILE:webgpu_dawn_shared>"
        "$<TARGET_PDB_FILE:dxcompiler>"
        # Copied from the Windows SDK by upstream's copy_dxil_dll target.
        "${CMAKE_BINARY_DIR}/$<CONFIG>/dxil.dll"
    DESTINATION bin)

# Link and load the DLL from a public, dependency-free C fixture.
enable_testing()
add_executable(smoke smoke.c)
target_include_directories(smoke PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/upstream/gen/include")
target_compile_definitions(smoke PRIVATE WGPU_SHARED_LIBRARY)
target_link_libraries(smoke PRIVATE webgpu_dawn_shared)
add_dependencies(smoke webgpu_dawn_shared)
set_target_properties(smoke PROPERTIES LINKER_LANGUAGE CXX)
add_test(NAME smoke COMMAND smoke)
