# Packages an installed Dawn build as <OUTPUT_DIR>/dawn-<rev12>-<TARGET>.tar.gz
# plus a matching .sha256 file. Windows instead gets separate -static and
# -shared packages, each with a -symbols package holding its PDB. Run in
# script mode:
#
#   cmake -D SOURCE_DIR=... -D BINARY_DIR=... -D TARGET=... -D RECIPE_COMMIT=...
#         -D OUTPUT_DIR=... -P dawn/package.cmake
#
# The archive has one root directory named like the archive, containing
# include/, lib/ (and bin/ for the Windows DLL), LICENSE, notices/ and
# BUILDINFO.txt. A symbols archive holds a PDB, LICENSE and the same BUILDINFO.txt.
cmake_minimum_required(VERSION 3.22)

foreach(var SOURCE_DIR BINARY_DIR TARGET RECIPE_COMMIT OUTPUT_DIR)
    if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
        message(FATAL_ERROR "package.cmake: ${var} is required")
    endif()
endforeach()
file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(var SOURCE_DIR BINARY_DIR OUTPUT_DIR)
    file(REAL_PATH "${${var}}" ${var})
endforeach()

file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/REVISION" revision LIMIT_COUNT 1)
execute_process(
    COMMAND git -C "${SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE source_revision OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
if(NOT source_revision STREQUAL revision)
    message(FATAL_ERROR "Dawn checkout is ${source_revision}; REVISION pins ${revision}")
endif()

string(SUBSTRING "${revision}" 0 12 short_revision)
set(name "dawn-${short_revision}-${TARGET}")
set(stage "${OUTPUT_DIR}/${name}")
file(GLOB stale "${OUTPUT_DIR}/${name}" "${OUTPUT_DIR}/${name}[.-]*")
file(REMOVE_RECURSE ${stale})

execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --config Release --prefix "${stage}"
    COMMAND_ERROR_IS_FATAL ANY)

load_cache("${BINARY_DIR}" READ_WITH_PREFIX cache_
    DAWN_BUILD_MONOLITHIC_LIBRARY LIZZIE_NOTICE_DIRS)
if("${TARGET}" MATCHES "windows")
    set(required include/dawn/webgpu.h lib/webgpu_dawn.lib
        lib/webgpu_dawn_dll.lib bin/webgpu_dawn.dll)
    set(static_symbols lib/webgpu_dawn_static.pdb)
    set(shared_symbols bin/webgpu_dawn.pdb)
else()
    set(required include/dawn/webgpu.h lib/libwebgpu_dawn.a)
endif()
foreach(path IN LISTS required static_symbols shared_symbols)
    if(NOT EXISTS "${stage}/${path}")
        message(FATAL_ERROR "Installed Dawn is missing ${path}")
    endif()
endforeach()

# Debuggers find the PDB by the bare file name recorded in the DLL. Linkers
# find the static PDB by the file name recorded in its objects, looking beside
# the archive when the build directory's path does not exist.
if(shared_symbols)
    file(STRINGS "${stage}/bin/webgpu_dawn.dll" pdb_names REGEX "\\.pdb")
    if(NOT "webgpu_dawn.pdb" IN_LIST pdb_names)
        message(FATAL_ERROR "webgpu_dawn.dll does not name webgpu_dawn.pdb: ${pdb_names}")
    endif()
endif()
if(static_symbols)
    file(STRINGS "${stage}/lib/webgpu_dawn.lib" pdb_names
        REGEX "webgpu_dawn_static\\.pdb" LIMIT_COUNT 1)
    if(NOT pdb_names)
        message(FATAL_ERROR "webgpu_dawn.lib objects do not name webgpu_dawn_static.pdb")
    endif()
endif()

# Dawn's own license, then the license files of each compiled-in dependency.
file(COPY "${SOURCE_DIR}/LICENSE" DESTINATION "${stage}")
foreach(dir IN LISTS cache_LIZZIE_NOTICE_DIRS)
    file(GLOB notices LIST_DIRECTORIES false
        "${SOURCE_DIR}/third_party/${dir}/LICENSE*"
        "${SOURCE_DIR}/third_party/${dir}/COPYING*"
        "${SOURCE_DIR}/third_party/${dir}/NOTICE*")
    if(NOT notices)
        message(FATAL_ERROR "No license file found in third_party/${dir}")
    endif()
    string(REPLACE "/src" "" notice_name "${dir}")
    file(COPY ${notices} DESTINATION "${stage}/notices/${notice_name}")
endforeach()

# Record the provenance and effective build settings next to the binaries.
file(STRINGS "${BINARY_DIR}/CMakeCache.txt" settings
    REGEX "^(DAWN_|TINT_|ABSL_MSVC|CMAKE_BUILD_TYPE|CMAKE_OSX_|CMAKE_MSVC_|CMAKE_SHARED_LINKER_FLAGS_RELEASE|CMAKE_C_COMPILER_TARGET|CMAKE_C_FLAGS:|CMAKE_CXX_FLAGS:|CMAKE_GENERATOR:)")
# Directory entries hold machine-local paths; *-STRINGS entries are UI hints.
list(FILTER settings EXCLUDE REGEX "(_DIR|-STRINGS):|:PATH=")
file(GLOB compiler_files "${BINARY_DIR}/CMakeFiles/*/CMakeCXXCompiler.cmake")
list(GET compiler_files 0 compiler_file)
file(STRINGS "${compiler_file}" compiler REGEX "^set\\(CMAKE_CXX_COMPILER_(ID|VERSION) ")
list(SORT settings)
string(JOIN "\n" settings ${settings})
string(JOIN "\n" compiler ${compiler})
file(WRITE "${stage}/BUILDINFO.txt"
    "target: ${TARGET}\n"
    "dawn: https://github.com/google/dawn/tree/${revision}\n"
    "recipe: https://github.com/GomerPiles/lizzie-deps/tree/${RECIPE_COMMIT}\n"
    "\n${compiler}\n\n${settings}\n")

function(write_archive archive_name)
    set(archive "${OUTPUT_DIR}/${archive_name}.tar.gz")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar czf "${archive}" --format=gnutar
            "--mtime=2000-01-01 00:00:00 UTC" "${archive_name}"
        WORKING_DIRECTORY "${OUTPUT_DIR}"
        COMMAND_ERROR_IS_FATAL ANY)
    file(SHA256 "${archive}" digest)
    file(SIZE "${archive}" size)
    file(WRITE "${archive}.sha256" "${digest}  ${archive_name}.tar.gz\n")
    message(STATUS "${archive_name}.tar.gz ${size} bytes sha256 ${digest}")
endfunction()

# Symbols download separately; each package keeps only what links or runs.
function(write_symbols_archive package_name path)
    set(package_stage "${OUTPUT_DIR}/${package_name}")
    set(symbols_stage "${package_stage}-symbols")
    cmake_path(GET path FILENAME file_name)
    file(MAKE_DIRECTORY "${symbols_stage}")
    file(RENAME "${package_stage}/${path}" "${symbols_stage}/${file_name}")
    file(COPY "${package_stage}/LICENSE" "${package_stage}/BUILDINFO.txt"
        DESTINATION "${symbols_stage}")
    write_archive("${package_name}-symbols")
endfunction()

if("${TARGET}" MATCHES "windows")
    # Each package is independently usable, with its own headers and notices.
    set(static_name "${name}-static")
    set(shared_name "${name}-shared")
    set(static_stage "${OUTPUT_DIR}/${static_name}")
    set(shared_stage "${OUTPUT_DIR}/${shared_name}")
    file(COPY "${stage}/" DESTINATION "${shared_stage}")
    file(REMOVE "${shared_stage}/lib/webgpu_dawn.lib" "${shared_stage}/${static_symbols}")
    # Upstream's CMake export describes the static target, not this DLL wrapper.
    file(REMOVE_RECURSE "${shared_stage}/lib/cmake")
    file(REMOVE_RECURSE "${stage}/bin")
    file(REMOVE "${stage}/lib/webgpu_dawn_dll.lib")
    file(RENAME "${stage}" "${static_stage}")
    write_symbols_archive("${static_name}" "${static_symbols}")
    write_symbols_archive("${shared_name}" "${shared_symbols}")
    write_archive("${static_name}")
    write_archive("${shared_name}")
else()
    write_archive("${name}")
endif()
