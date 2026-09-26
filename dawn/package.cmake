# Packages an installed Dawn build as <OUTPUT_DIR>/dawn-<rev12>-<TARGET>.tar.gz
# plus a matching .sha256 file. Run in script mode:
#
#   cmake -D SOURCE_DIR=... -D BINARY_DIR=... -D TARGET=... -D RECIPE_COMMIT=...
#         -D OUTPUT_DIR=... -P dawn/package.cmake
#
# The archive has one root directory named like the archive, containing
# include/, lib/ (and bin/ on Windows), LICENSE, notices/ and BUILDINFO.txt.
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
set(archive "${OUTPUT_DIR}/${name}.tar.gz")
file(REMOVE_RECURSE "${stage}" "${archive}" "${archive}.sha256")

execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BINARY_DIR}" --config Release --prefix "${stage}"
    COMMAND_ERROR_IS_FATAL ANY)

load_cache("${BINARY_DIR}" READ_WITH_PREFIX cache_
    DAWN_BUILD_MONOLITHIC_LIBRARY LIZZIE_NOTICE_DIRS)
if(cache_DAWN_BUILD_MONOLITHIC_LIBRARY STREQUAL "SHARED")
    if(TARGET MATCHES "windows")
        set(required include/dawn/webgpu.h lib/webgpu_dawn.lib bin/webgpu_dawn.dll)
    else()
        message(FATAL_ERROR "No shared-library layout is defined for ${TARGET}")
    endif()
else()
    set(required include/dawn/webgpu.h lib/libwebgpu_dawn.a)
endif()
foreach(path IN LISTS required)
    if(NOT EXISTS "${stage}/${path}")
        message(FATAL_ERROR "Installed Dawn is missing ${path}")
    endif()
endforeach()

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
    REGEX "^(DAWN_|TINT_|ABSL_MSVC|CMAKE_BUILD_TYPE|CMAKE_OSX_|CMAKE_MSVC_RUNTIME|CMAKE_GENERATOR:)")
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

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar czf "${archive}" --format=gnutar "--mtime=2000-01-01 00:00:00 UTC"
        "${name}"
    WORKING_DIRECTORY "${OUTPUT_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${archive}" digest)
file(SIZE "${archive}" size)
file(WRITE "${archive}.sha256" "${digest}  ${name}.tar.gz\n")
message(STATUS "${name}.tar.gz ${size} bytes sha256 ${digest}")
