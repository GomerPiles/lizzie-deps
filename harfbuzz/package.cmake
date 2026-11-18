# Install the core library, headers and notices in a single checksummed archive.
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

file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/SOURCES" pin REGEX "^harfbuzz ")
string(REPLACE " " ";" pin "${pin}")
list(GET pin 1 tag)
list(GET pin 2 commit)
list(GET pin 3 url)
set(source "${SOURCE_DIR}/harfbuzz")
execute_process(
    COMMAND git -C "${source}" rev-parse HEAD
    OUTPUT_VARIABLE checkout OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
if(NOT checkout STREQUAL commit)
    message(FATAL_ERROR "HarfBuzz checkout is ${checkout}; SOURCES pins ${commit}")
endif()

set(build "${BINARY_DIR}/harfbuzz")
load_cache("${build}" READ_WITH_PREFIX cache_ LIZZIE_TARGET LIZZIE_LINK_LIBRARIES)
if(NOT cache_LIZZIE_TARGET STREQUAL "${TARGET}")
    message(FATAL_ERROR "Build target is ${cache_LIZZIE_TARGET}, expected ${TARGET}")
endif()
set(name "harfbuzz-${tag}-${TARGET}")
set(stage "${OUTPUT_DIR}/${name}")
file(REMOVE_RECURSE "${stage}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${build}" --prefix "${stage}"
    COMMAND_ERROR_IS_FATAL ANY)
file(REMOVE_RECURSE "${stage}/lib/cmake" "${stage}/lib/pkgconfig")
if("${TARGET}" STREQUAL "x86_64-windows")
    set(libraries lib/harfbuzz.lib bin/harfbuzz.dll)
else()
    set(libraries lib/libharfbuzz.a)
endif()
foreach(path IN LISTS libraries)
    if(NOT EXISTS "${stage}/${path}")
        message(FATAL_ERROR "Package is missing ${path}")
    endif()
endforeach()

file(COPY "${source}/COPYING" DESTINATION "${stage}/notices/harfbuzz")
file(COPY "${source}/src/ms-use/COPYING" DESTINATION "${stage}/notices/ms-use")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/UNICODE-LICENSE.txt" DESTINATION "${stage}/notices")

file(GLOB compiler_files "${build}/CMakeFiles/*/CMakeCXXCompiler.cmake")
list(GET compiler_files 0 compiler_file)
file(STRINGS "${compiler_file}" compiler REGEX "^set\\(CMAKE_CXX_COMPILER_(ID|VERSION) ")
file(STRINGS "${build}/CMakeCache.txt" settings
    REGEX "^(BUILD_SHARED_LIBS:|HB_(BUILD|HAVE)_|CMAKE_(BUILD_TYPE|CXX_COMPILER_TARGET|CXX_FLAGS(_RELEASE)?|MSVC_RUNTIME_LIBRARY|OSX_ARCHITECTURES|OSX_DEPLOYMENT_TARGET):)")
string(JOIN "\n" compiler ${compiler})
string(JOIN "\n" settings ${settings})
string(CONCAT buildinfo
    "target: ${TARGET}\n"
    "harfbuzz: ${tag} ${url} ${commit}\n"
    "recipe: https://github.com/GomerPiles/lizzie-deps/tree/${RECIPE_COMMIT}\n"
    "link: ${cache_LIZZIE_LINK_LIBRARIES}\n"
    "\n${compiler}\n${settings}\n")
# Git Bash tools and release-note generation read this metadata on every OS.
file(CONFIGURE OUTPUT "${stage}/BUILDINFO.txt" CONTENT "${buildinfo}" @ONLY NEWLINE_STYLE UNIX)

set(archive "${OUTPUT_DIR}/${name}.tar.gz")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar czf "${archive}" --format=gnutar
        "--mtime=2000-01-01 00:00:00 UTC" "${name}"
    WORKING_DIRECTORY "${OUTPUT_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${archive}" digest)
file(SIZE "${archive}" size)
file(CONFIGURE OUTPUT "${archive}.sha256" CONTENT "${digest}  ${name}.tar.gz\n" @ONLY NEWLINE_STYLE UNIX)
message(STATUS "${name}.tar.gz ${size} bytes sha256 ${digest}")
