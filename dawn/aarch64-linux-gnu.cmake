# Linux aarch64 GNU.
set(CMAKE_SYSTEM_PROCESSOR aarch64 CACHE STRING "")
set(LIZZIE_ZIG_CPU generic+v8_2a CACHE STRING "")
include("${CMAKE_CURRENT_LIST_DIR}/linux-gnu.cmake")
