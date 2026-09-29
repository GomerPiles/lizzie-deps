# Settings shared by every target, for both BoringSSL and ngtcp2; each project
# ignores the other's options. Each target cache file includes this first, then
# states its toolchain, minimum CPU and the libraries a consumer links.

set(CMAKE_BUILD_TYPE Release CACHE STRING "")

# Static libraries only. Tests build beside them and do not change them;
# ngtcp2/build runs them wherever the runner can execute the target.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
set(BUILD_TESTING ON CACHE BOOL "")

# ngtcp2: the library and its BoringSSL crypto helper, without examples.
set(ENABLE_LIB_ONLY ON CACHE BOOL "")
set(ENABLE_SHARED_LIB OFF CACHE BOOL "")
set(ENABLE_STATIC_LIB ON CACHE BOOL "")
set(ENABLE_OPENSSL OFF CACHE BOOL "")
set(ENABLE_BORINGSSL ON CACHE BOOL "")
