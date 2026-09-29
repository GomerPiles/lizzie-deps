# Packages the libraries ngtcp2/build produced as
# <OUTPUT_DIR>/ngtcp2-<version>-boringssl-<tag>-<TARGET>.tar.gz plus a matching
# .sha256 file. Run in script mode:
#
#   cmake -D SOURCE_DIR=s -D BINARY_DIR=b -D TARGET=... -D RECIPE_COMMIT=...
#         -D OUTPUT_DIR=o -P ngtcp2/package.cmake
#
# The archive has one root directory named like the archive, containing
# include/ (ngtcp2/ and openssl/), lib/, notices/ and BUILDINFO.txt.
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

# Each checkout must be the commit SOURCES pins.
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/SOURCES" pins REGEX "^[a-z]")
foreach(pin IN LISTS pins)
    string(REPLACE " " ";" fields "${pin}")
    list(GET fields 0 pin_name)
    list(GET fields 1 tag_${pin_name})
    list(GET fields 2 commit_${pin_name})
    list(GET fields 3 url_${pin_name})
    execute_process(
        COMMAND git -C "${SOURCE_DIR}/${pin_name}" rev-parse HEAD
        OUTPUT_VARIABLE checkout OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY)
    if(NOT checkout STREQUAL commit_${pin_name})
        message(FATAL_ERROR "${pin_name} checkout is ${checkout}; SOURCES pins ${commit_${pin_name}}")
    endif()
endforeach()

string(REGEX REPLACE "^v" "" ngtcp2_version "${tag_ngtcp2}")
set(name "ngtcp2-${ngtcp2_version}-boringssl-${tag_boringssl}-${TARGET}")
set(stage "${OUTPUT_DIR}/${name}")
file(REMOVE_RECURSE "${stage}")
file(REMOVE "${OUTPUT_DIR}/${name}.tar.gz" "${OUTPUT_DIR}/${name}.tar.gz.sha256")

# Headers: BoringSSL's public headers, and ngtcp2's with its generated version.h.
set(ngtcp2 "${SOURCE_DIR}/ngtcp2")
set(boringssl "${SOURCE_DIR}/boringssl")
file(COPY "${boringssl}/include/openssl" DESTINATION "${stage}/include")
file(COPY
        "${ngtcp2}/lib/includes/ngtcp2/ngtcp2.h"
        "${BINARY_DIR}/ngtcp2/lib/includes/ngtcp2/version.h"
        "${ngtcp2}/crypto/includes/ngtcp2/ngtcp2_crypto.h"
        "${ngtcp2}/crypto/includes/ngtcp2/ngtcp2_crypto_boringssl.h"
    DESTINATION "${stage}/include/ngtcp2")

# Libraries keep the names their toolchain gives them: libX.a, or X.lib for MSVC.
if("${TARGET}" MATCHES "msvc")
    set(prefix "")
    set(suffix ".lib")
else()
    set(prefix "lib")
    set(suffix ".a")
endif()
foreach(library
        ngtcp2/lib/ngtcp2
        ngtcp2/crypto/boringssl/ngtcp2_crypto_boringssl
        boringssl/ssl
        boringssl/crypto)
    cmake_path(GET library PARENT_PATH directory)
    cmake_path(GET library FILENAME library_name)
    set(path "${BINARY_DIR}/${directory}/${prefix}${library_name}${suffix}")
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Build is missing ${path}")
    endif()
    file(COPY "${path}" DESTINATION "${stage}/lib")
endforeach()

# Licenses of everything compiled into the libraries. ngtcp2 includes PCG, whose
# notice lives only in its source file.
file(COPY "${ngtcp2}/COPYING" DESTINATION "${stage}/notices/ngtcp2")
file(COPY "${boringssl}/LICENSE" DESTINATION "${stage}/notices/boringssl")
file(COPY "${boringssl}/third_party/fiat/LICENSE" DESTINATION "${stage}/notices/fiat")
file(READ "${ngtcp2}/lib/ngtcp2_pcg.c" pcg)
set(pcg_first "PCG Random Number Generation for C.")
set(pcg_last "visit http://www.pcg-random.org/.")
string(FIND "${pcg}" "${pcg_first}" pcg_begin)
string(FIND "${pcg}" "${pcg_last}" pcg_end)
if(pcg_begin EQUAL -1 OR pcg_end LESS pcg_begin)
    message(FATAL_ERROR "No PCG notice found in ngtcp2_pcg.c")
endif()
string(LENGTH "${pcg_last}" pcg_last_length)
math(EXPR pcg_length "${pcg_end} + ${pcg_last_length} - ${pcg_begin}")
string(SUBSTRING "${pcg}" ${pcg_begin} ${pcg_length} pcg)
string(REGEX REPLACE "\n \\* ?" "\n" pcg "${pcg}")
file(WRITE "${stage}/notices/pcg/NOTICE" "${pcg}\n")

# Record the provenance, effective build settings and link requirements.
load_cache("${BINARY_DIR}/boringssl" READ_WITH_PREFIX cache_ LIZZIE_LINK_LIBRARIES)
set(cmake_settings "CMAKE_BUILD_TYPE|CMAKE_OSX_(ARCHITECTURES|DEPLOYMENT_TARGET)|CMAKE_MSVC_RUNTIME_LIBRARY|CMAKE_EXE_LINKER_FLAGS:|CMAKE_(C|CXX|ASM)_COMPILER_TARGET|CMAKE_(C|CXX|ASM)_FLAGS(_RELEASE)?:|CMAKE_GENERATOR:")
set(boringssl_settings "BUILD_SHARED_LIBS|BUILD_TESTING|OPENSSL_")
set(ngtcp2_settings "BUILD_TESTING|ENABLE_")
set(settings)
foreach(project boringssl ngtcp2)
    file(STRINGS "${BINARY_DIR}/${project}/CMakeCache.txt" project_settings
        REGEX "^(${${project}_settings}|${cmake_settings})")
    list(TRANSFORM project_settings PREPEND "${project} ")
    list(APPEND settings ${project_settings})
endforeach()
file(GLOB compiler_files "${BINARY_DIR}/boringssl/CMakeFiles/*/CMakeCXXCompiler.cmake")
list(GET compiler_files 0 compiler_file)
file(STRINGS "${compiler_file}" compiler REGEX "^set\\(CMAKE_CXX_COMPILER_(ID|VERSION) ")
string(JOIN "\n" settings ${settings})
string(JOIN "\n" compiler ${compiler})
file(WRITE "${stage}/BUILDINFO.txt"
    "target: ${TARGET}\n"
    "ngtcp2: ${tag_ngtcp2} ${url_ngtcp2} ${commit_ngtcp2}\n"
    "boringssl: ${tag_boringssl} ${url_boringssl} ${commit_boringssl}\n"
    "recipe: https://github.com/GomerPiles/lizzie-deps/tree/${RECIPE_COMMIT}\n"
    "define: NGTCP2_STATICLIB\n"
    "link: ${cache_LIZZIE_LINK_LIBRARIES}\n"
    "\n${compiler}\n\n${settings}\n")

set(archive "${OUTPUT_DIR}/${name}.tar.gz")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar czf "${archive}" --format=gnutar
        "--mtime=2000-01-01 00:00:00 UTC" "${name}"
    WORKING_DIRECTORY "${OUTPUT_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
file(SHA256 "${archive}" digest)
file(SIZE "${archive}" size)
file(WRITE "${archive}.sha256" "${digest}  ${name}.tar.gz\n")
message(STATUS "${name}.tar.gz ${size} bytes sha256 ${digest}")
