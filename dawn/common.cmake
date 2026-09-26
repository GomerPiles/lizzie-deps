# Settings shared by every Dawn target. Each target cache file includes this
# first, then states its backends and platform-specific settings.

set(CMAKE_BUILD_TYPE Release CACHE STRING "")

# Fetch Dawn's DEPS-pinned sources without depot_tools.
set(DAWN_FETCH_DEPENDENCIES ON CACHE BOOL "")
set(DAWN_ENABLE_INSTALL ON CACHE BOOL "")

# Consumers link one library and include webgpu.h; nothing else is shipped.
set(DAWN_BUILD_SAMPLES OFF CACHE BOOL "")
set(DAWN_BUILD_TESTS OFF CACHE BOOL "")
set(DAWN_BUILD_BENCHMARKS OFF CACHE BOOL "")
set(DAWN_BUILD_PROTOBUF OFF CACHE BOOL "")
set(DAWN_USE_GLFW OFF CACHE BOOL "")
set(TINT_BUILD_CMD_TOOLS OFF CACHE BOOL "")
set(TINT_BUILD_TESTS OFF CACHE BOOL "")
set(TINT_BUILD_BENCHMARKS OFF CACHE BOOL "")
set(TINT_BUILD_IR_BINARY OFF CACHE BOOL "")
set(TINT_BUILD_GLSL_VALIDATOR OFF CACHE BOOL "")
set(DAWN_SUPPORTS_CXX_MODULES OFF CACHE BOOL "")

# No OpenGL backends on any target; each target enables its own native APIs.
set(DAWN_ENABLE_DESKTOP_GL OFF CACHE BOOL "")
set(DAWN_ENABLE_OPENGLES OFF CACHE BOOL "")
set(DAWN_ENABLE_NULL ON CACHE BOOL "")

