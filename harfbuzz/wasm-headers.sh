# shellcheck shell=bash
# WASI headers supply C declarations for a freestanding compile.
zig=${ZIG:-zig}
zig_lib=$("$zig" env | sed -n 's/^ *\.lib_dir = "\(.*\)",$/\1/p')
: "${zig_lib:?could not locate Zig bundled headers}"
wasm_c_headers=(
  -isystem "$zig_lib/libc/include/wasm-wasi-musl"
  -isystem "$zig_lib/libc/include/generic-musl"
)
