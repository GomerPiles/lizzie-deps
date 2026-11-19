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
set(name "harfbuzz-${tag}-${TARGET}")
set(stage "${OUTPUT_DIR}/${name}")
if("${TARGET}" STREQUAL "wasm32-freestanding")
    set(wasm_build "${build}/${TARGET}")
    file(READ "${wasm_build}/buildinfo.txt" settings)
    file(REMOVE_RECURSE "${stage}")
    file(COPY "${wasm_build}/libharfbuzz.a" DESTINATION "${stage}/lib")
    # Match project_headers in the pinned upstream CMakeLists.txt.
    set(headers
        hb-aat-layout.h hb-aat.h hb-blob.h hb-buffer.h hb-common.h hb-cplusplus.hh
        hb-deprecated.h hb-draw.h hb-face.h hb-font.h hb-map.h hb-ot-color.h
        hb-ot-deprecated.h hb-ot-fetch.h hb-ot-font.h hb-ot-layout.h hb-ot-math.h
        hb-ot-meta.h hb-ot-metrics.h hb-ot-name.h hb-ot-shape.h hb-ot-var.h
        hb-ot.h hb-paint.h hb-set.h hb-script-list.h hb-shape-plan.h hb-shape.h
        hb-style.h hb-unicode.h hb-version.h hb.h)
    list(TRANSFORM headers PREPEND "${source}/src/")
    file(COPY ${headers} DESTINATION "${stage}/include/harfbuzz")
    # The core build leaves all optional integrations and libraries disabled.
    file(READ "${source}/src/hb-features.h.in" features)
    string(REGEX REPLACE "#mesondefine (HB_HAS_[A-Z0-9_]+)" "/* #undef \\1 */" features "${features}")
    file(WRITE "${stage}/include/harfbuzz/hb-features.h" "${features}")
    set(link "wasm32-freestanding without libc or libc++")
else()
    load_cache("${build}" READ_WITH_PREFIX cache_ LIZZIE_TARGET LIZZIE_LINK_LIBRARIES)
    if(NOT cache_LIZZIE_TARGET STREQUAL "${TARGET}")
        message(FATAL_ERROR "Build target is ${cache_LIZZIE_TARGET}, expected ${TARGET}")
    endif()
    file(REMOVE_RECURSE "${stage}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" --install "${build}" --prefix "${stage}"
        COMMAND_ERROR_IS_FATAL ANY)
    file(REMOVE_RECURSE "${stage}/lib/cmake" "${stage}/lib/pkgconfig")
    set(link "${cache_LIZZIE_LINK_LIBRARIES}")
    file(GLOB compiler_files "${build}/CMakeFiles/*/CMakeCXXCompiler.cmake")
    list(GET compiler_files 0 compiler_file)
    file(STRINGS "${compiler_file}" compiler REGEX "^set\\(CMAKE_CXX_COMPILER_(ID|VERSION) ")
    file(STRINGS "${build}/CMakeCache.txt" cache_settings
        REGEX "^(BUILD_SHARED_LIBS:|HB_(BUILD|HAVE)_|CMAKE_(BUILD_TYPE|CXX_COMPILER_TARGET|CXX_FLAGS(_RELEASE)?|MSVC_RUNTIME_LIBRARY|OSX_ARCHITECTURES|OSX_DEPLOYMENT_TARGET):)")
    string(JOIN "\n" compiler ${compiler})
    string(JOIN "\n" cache_settings ${cache_settings})
    set(settings "${compiler}\n${cache_settings}\n")
endif()
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

string(CONCAT buildinfo
    "target: ${TARGET}\n"
    "harfbuzz: ${tag} ${url} ${commit}\n"
    "recipe: https://github.com/GomerPiles/lizzie-deps/tree/${RECIPE_COMMIT}\n"
    "link: ${link}\n"
    "\n${settings}")
# Git Bash tools and release-note generation read this metadata on every OS.
file(CONFIGURE OUTPUT "${stage}/BUILDINFO.txt" CONTENT "${buildinfo}" @ONLY NEWLINE_STYLE UNIX)

set(archive "${OUTPUT_DIR}/${name}.tar.gz")
set(tar_options --format=gnutar "--mtime=2000-01-01 00:00:00 UTC" "${name}")
if("${TARGET}" STREQUAL "wasm32-freestanding")
    # CMake fixes the tar entry times. gzip -n also clears the gzip timestamp.
    set(tar "${OUTPUT_DIR}/${name}.tar")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar cf "${tar}" ${tar_options}
        WORKING_DIRECTORY "${OUTPUT_DIR}"
        COMMAND_ERROR_IS_FATAL ANY)
    execute_process(COMMAND gzip -n -c "${tar}" OUTPUT_FILE "${archive}" COMMAND_ERROR_IS_FATAL ANY)
    file(REMOVE "${tar}")
else()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar czf "${archive}" ${tar_options}
        WORKING_DIRECTORY "${OUTPUT_DIR}"
        COMMAND_ERROR_IS_FATAL ANY)
endif()
file(SHA256 "${archive}" digest)
file(SIZE "${archive}" size)
file(CONFIGURE OUTPUT "${archive}.sha256" CONTENT "${digest}  ${name}.tar.gz\n" @ONLY NEWLINE_STYLE UNIX)
message(STATUS "${name}.tar.gz ${size} bytes sha256 ${digest}")
