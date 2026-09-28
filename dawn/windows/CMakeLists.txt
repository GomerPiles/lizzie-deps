cmake_minimum_required(VERSION 3.24)
project(DawnWindowsPackages LANGUAGES C CXX)
if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "Windows packages require the native MSVC toolchain")
endif()
if(NOT DEFINED DAWN_SOURCE_DIR)
    message(FATAL_ERROR "DAWN_SOURCE_DIR is required")
endif()
add_subdirectory("${DAWN_SOURCE_DIR}" upstream)

# Dawn is compiled once into a static archive. Export only its public C API
# when linking the DLL; static objects contain no dllexport directives.
set(exports "${CMAKE_CURRENT_BINARY_DIR}/webgpu_dawn.def")
set(header "${CMAKE_CURRENT_BINARY_DIR}/upstream/gen/include/dawn/webgpu.h")
add_custom_command(OUTPUT "${exports}"
    COMMAND "${CMAKE_COMMAND}" "-DHEADER=${header}" "-DOUTPUT=${exports}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/exports.cmake"
    DEPENDS webgpu_dawn "${CMAKE_CURRENT_SOURCE_DIR}/exports.cmake"
    VERBATIM)
add_library(webgpu_dawn_shared SHARED "${exports}")
set_target_properties(webgpu_dawn_shared PROPERTIES
    LINKER_LANGUAGE CXX
    OUTPUT_NAME webgpu_dawn
    ARCHIVE_OUTPUT_NAME webgpu_dawn_dll)
target_link_libraries(webgpu_dawn_shared PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,webgpu_dawn>")
install(TARGETS webgpu_dawn_shared
    RUNTIME DESTINATION bin
    ARCHIVE DESTINATION lib)
install(FILES "$<TARGET_PDB_FILE:webgpu_dawn_shared>" DESTINATION bin)

# Test both link forms through the same public, dependency-free C fixture.
enable_testing()
foreach(kind static shared)
    add_executable(smoke_${kind} smoke.c)
    target_include_directories(smoke_${kind} PRIVATE
        "${CMAKE_CURRENT_BINARY_DIR}/upstream/gen/include")
    if(kind STREQUAL "static")
        target_link_libraries(smoke_${kind} PRIVATE webgpu_dawn)
    else()
        target_compile_definitions(smoke_${kind} PRIVATE WGPU_SHARED_LIBRARY)
        target_link_libraries(smoke_${kind} PRIVATE webgpu_dawn_shared)
    endif()
    set_target_properties(smoke_${kind} PROPERTIES LINKER_LANGUAGE CXX)
    add_test(NAME smoke_${kind} COMMAND smoke_${kind})
endforeach()
