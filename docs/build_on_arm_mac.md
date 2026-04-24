# Build braft on ARM Mac

This note records the steps used to build `braft` and run the `example/counter` demo on an Apple Silicon Mac.

## Environment

- macOS on arm64, AppleClang from Command Line Tools.
- Homebrew prefix: `/opt/homebrew`.
- CMake is new enough that projects declaring `cmake_minimum_required(VERSION 2.8.10)` need `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.
- `brpc` is required before building `braft`. The examples below assume a sibling brpc checkout at `../brpc`; replace it with your own brpc source path if needed.

## Homebrew dependencies

Install or verify these packages:

```bash
brew install cmake gflags glog protobuf leveldb openssl@3 snappy gperftools
```

One verified Homebrew setup used `gflags 2.2.2`, `glog 0.6.0`, `protobuf 3.19.4`, `leveldb 1.23_2`, `openssl@3 3.6.0`, and `snappy 1.2.2`.

## Build brpc

Build a private brpc copy under this repository's `.deps` directory. This keeps the braft build self-contained and avoids modifying the brpc source checkout.

```bash
rm -rf .deps/brpc-src .deps/brpc-build .deps/brpc-install
mkdir -p .deps
rsync -a --exclude .git --exclude build --exclude .cache \
  ../brpc/ .deps/brpc-src/

# Optional: restore selected files from brpc HEAD if your brpc checkout has local edits.
git -C ../brpc show HEAD:CMakeLists.txt > .deps/brpc-src/CMakeLists.txt
git -C ../brpc show HEAD:src/CMakeLists.txt > .deps/brpc-src/src/CMakeLists.txt
git -C ../brpc show HEAD:src/idl_options.proto > .deps/brpc-src/src/idl_options.proto

cmake -S .deps/brpc-src -B .deps/brpc-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PWD/.deps/brpc-install" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_UNIT_TESTS=OFF
cmake --build .deps/brpc-build -j4
cmake --install .deps/brpc-build
```

Notes:

- `BUILD_UNIT_TESTS=OFF` avoids a Googletest dependency during the brpc build.
- The installed brpc static library is `.deps/brpc-install/lib/libbrpc.a`.
- This brpc CMake build detected `glog`, so `braft` and examples must also be compiled with `BRPC_WITH_GLOG=ON` / `BRPC_WITH_GLOG=1` to avoid mismatched logging symbols.

## Build braft

```bash
cmake -S . -B bld \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_PREFIX_PATH="$PWD/.deps/brpc-install" \
  -DBRPC_WITH_GLOG=ON
cmake --build bld --target braft-static -j4
```

Observed issues and fixes:

- Without `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`, new CMake rejects the old `cmake_minimum_required(VERSION 2.8.10)` policy range.
- Without `BRPC_WITH_GLOG=ON`, `braft` compiles against butil's non-glog logging path while brpc may be built with glog, causing unresolved `google::LogMessage`/`google::RawLog__`/`google::base::CheckOpMessageBuilder` symbols during linking.
- Building the default `all` target also tries to build the shared library and tools. For the counter demo, `braft-static` is sufficient.

## Build counter example

The counter example was adjusted for macOS:

- Link directly without GNU ld's `-(` / `-)` group options, which Apple ld does not support.
- Use absolute OpenSSL libraries from `find_package(OpenSSL)` instead of `-lssl -lcrypto`.
- Link `glog` and compile with `-DBRPC_WITH_GLOG=1` to match the brpc/braft build.
- Avoid BSD `getopt` long-option limitations by using a small script-local parser on macOS.
- Use the first non-loopback `ifconfig` IPv4 address on macOS because `butil::my_ip()` uses that address for raft peer identity; falling back to `127.0.0.1` prevents the node from matching its own peer id.
- Omit `crash_on_fatal_log` when building with Homebrew `glog 0.6.0`, which does not expose that gflags option.

Configure and build:

```bash
cmake -S example/counter -B example/counter/bld \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBRPC_INCLUDE_PATH="$PWD/.deps/brpc-install/include" \
  -DBRPC_LIB="$PWD/.deps/brpc-install/lib/libbrpc.a" \
  -DBRAFT_INCLUDE_PATH="$PWD/bld/output/include" \
  -DBRAFT_LIB="$PWD/bld/output/lib/libbraft.a"
cmake --build example/counter/bld -j4
```

## Run counter example

From `example/counter`:

```bash
cp bld/counter_server bld/counter_client .
bash run_server.sh --clean --server_num=3 --port=8100
# In another shell, or with a timeout for a quick smoke test:
timeout 10s bash run_client.sh --server_num=3 --server_port=8100 --log_each_request=true
bash stop.sh
```

Expected behavior:

- Three server processes start under `example/counter/runtime/0..2`.
- The client discovers the leader and logs successful `fetch_add` responses.
- `runtime/*/std.log` contains raft startup/election logs.

Example verification:

- `runtime/0/std.log` showed `become leader` for the first peer, for example `<local-ip>:8100:0:0`.
- `client.log` showed successful responses from the leader with increasing counter values during a short smoke test.
