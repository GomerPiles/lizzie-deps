# Packages an installed Dawn build as <OUTPUT_DIR>/dawn-<rev12>-<TARGET>.tar.gz
# plus a matching .sha256 file. A build that produces PDBs also gets a
# separate dawn-<rev12>-<TARGET>-symbols.tar.gz. Run in script mode:
#
#   cmake -D SOURCE_DIR=... -D BINARY_DIR=... -D TARGET=... -D RECIPE_COMMIT=...
#         -D OUTPUT_DIR=... -P dawn/package.cmake
#
# The archive has one root directory named like the archive, containing
# include/, lib/ (and bin/ on Windows), LICENSE, notices/ and BUILDINFO.txt.
# The symbols archive holds the PDBs, LICENSE and the same BUILDINFO.txt.
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
set(symbols_name "${name}-symbols")
set(symbols_stage "${OUTPUT_DIR}/${symbols_name}")
file(REMOVE_RECURSE "${stage}" "${symbols_stage}")
file(REMOVE
    "${OUTPUT_DIR}/${name}.tar.gz" "${OUTPUT_DIR}/${name}.tar.gz.sha256"
    "${OUTPUT_DIR}/${symbols_name}.tar.gz" "${OUTPUT_DIR}/${symbols_name}.tar.gz.sha256")

execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --config Release --prefix "${stage}"
    COMMAND_ERROR_IS_FATAL ANY)

load_cache("${BINARY_DIR}" READ_WITH_PREFIX cache_ LIZZIE_NOTICE_DIRS)
if("${TARGET}" MATCHES "windows")
    # Windows ships only the DLL. Upstream installs the static archive it was
    # linked from, plus a CMake export describing that archive; drop both and
    # give the import library the conventional name.
    file(REMOVE "${stage}/lib/webgpu_dawn.lib")
    file(REMOVE_RECURSE "${stage}/lib/cmake")
    file(RENAME "${stage}/lib/webgpu_dawn_dll.lib" "${stage}/lib/webgpu_dawn.lib")
    set(required include/dawn/webgpu.h lib/webgpu_dawn.lib bin/webgpu_dawn.dll
        bin/dxcompiler.dll)
    set(symbols bin/webgpu_dawn.pdb bin/dxcompiler.pdb)
else()
    set(required include/dawn/webgpu.h lib/libwebgpu_dawn.a)
endif()
foreach(path IN LISTS required symbols)
    if(NOT EXISTS "${stage}/${path}")
        message(FATAL_ERROR "Installed Dawn is missing ${path}")
    endif()
endforeach()

# Debuggers find each PDB by the bare file name recorded in its DLL.
foreach(pdb IN LISTS symbols)
    string(REGEX REPLACE "\\.pdb$" ".dll" dll "${pdb}")
    cmake_path(GET pdb FILENAME pdb_name)
    file(STRINGS "${stage}/${dll}" pdb_names REGEX "\\.pdb")
    if(NOT "${pdb_name}" IN_LIST pdb_names)
        message(FATAL_ERROR "${dll} does not name ${pdb_name}: ${pdb_names}")
    endif()
endforeach()

# Dawn's own license, then the license files of each compiled-in dependency.
file(COPY "${SOURCE_DIR}/LICENSE" DESTINATION "${stage}")
foreach(dir IN LISTS cache_LIZZIE_NOTICE_DIRS)
    file(GLOB notices LIST_DIRECTORIES false
        "${SOURCE_DIR}/third_party/${dir}/LICENSE*"
        "${SOURCE_DIR}/third_party/${dir}/COPYING*"
        "${SOURCE_DIR}/third_party/${dir}/NOTICE*"
        "${SOURCE_DIR}/third_party/${dir}/ThirdPartyNotices*")
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

# Symbols download separately; the binaries archive keeps only what links.
if(symbols)
    file(MAKE_DIRECTORY "${symbols_stage}")
    foreach(path IN LISTS symbols)
        cmake_path(GET path FILENAME file_name)
        file(RENAME "${stage}/${path}" "${symbols_stage}/${file_name}")
    endforeach()
    file(COPY "${stage}/LICENSE" "${stage}/BUILDINFO.txt" DESTINATION "${symbols_stage}")
endif()

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

write_archive("${name}")
if(symbols)
    write_archive("${symbols_name}")
endif()
