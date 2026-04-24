# 在 ARM Mac 上构建 braft

本文记录在 Apple Silicon Mac 上构建 `braft` 并运行 `example/counter` 示例的步骤。

## 环境

- macOS arm64，使用 Command Line Tools 提供的 AppleClang。
- Homebrew 前缀通常是 `/opt/homebrew`。
- 新版本 CMake 对旧项目策略更严格。由于本项目声明了 `cmake_minimum_required(VERSION 2.8.10)`，配置时需要增加 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`。
- 构建 `braft` 前需要先构建 `brpc`。下文假设 `brpc` 源码位于同级目录 `../brpc`；如果你的路径不同，请替换成自己的 brpc 源码路径。

## Homebrew 依赖

安装或确认以下依赖已存在：

```bash
brew install cmake gflags glog protobuf leveldb openssl@3 snappy gperftools
```

一个已验证可用的 Homebrew 组合是：`gflags 2.2.2`、`glog 0.6.0`、`protobuf 3.19.4`、`leveldb 1.23_2`、`openssl@3 3.6.0`、`snappy 1.2.2`。

## 构建 brpc

建议在本仓库的 `.deps` 目录下构建一份私有 brpc 副本。这样可以让 braft 的构建过程相对自包含，也避免修改 brpc 源码仓库。

```bash
rm -rf .deps/brpc-src .deps/brpc-build .deps/brpc-install
mkdir -p .deps
rsync -a --exclude .git --exclude build --exclude .cache \
  ../brpc/ .deps/brpc-src/

# 可选：如果 brpc 工作区有本地改动，可以从 brpc HEAD 恢复构建相关文件。
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

说明：

- `BUILD_UNIT_TESTS=OFF` 可以避免 brpc 构建阶段依赖 Googletest。
- 安装后的 brpc 静态库路径是 `.deps/brpc-install/lib/libbrpc.a`。
- 如果 brpc 的 CMake 构建检测到了 `glog`，那么 `braft` 和示例程序也需要使用 `BRPC_WITH_GLOG=ON` / `BRPC_WITH_GLOG=1` 编译，否则会出现日志符号不匹配。

## 构建 braft

```bash
cmake -S . -B bld \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_PREFIX_PATH="$PWD/.deps/brpc-install" \
  -DBRPC_WITH_GLOG=ON
cmake --build bld --target braft-static -j4
```

常见问题与处理：

- 如果不加 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`，新版本 CMake 会拒绝旧的 `cmake_minimum_required(VERSION 2.8.10)` 策略范围。
- 如果不加 `BRPC_WITH_GLOG=ON`，`braft` 会按 butil 的非 glog 日志路径编译，而 brpc 可能已经按 glog 路径编译，链接时会出现 `google::LogMessage`、`google::RawLog__`、`google::base::CheckOpMessageBuilder` 等未定义符号。
- 默认 `all` 目标还会尝试构建动态库和工具。运行 counter 示例时，构建 `braft-static` 已足够。

## 构建 counter 示例

为了在 macOS 上构建 counter 示例，需要处理以下兼容性问题：

- Apple ld 不支持 GNU ld 的 `-(` / `-)` 链接分组选项，因此 macOS 下需要直接链接。
- OpenSSL 使用 `find_package(OpenSSL)` 找到的绝对库路径，而不是直接使用 `-lssl -lcrypto`。
- 示例需要链接 `glog`，并使用 `-DBRPC_WITH_GLOG=1`，以匹配 brpc/braft 的构建方式。
- macOS 自带 BSD `getopt` 对长选项支持有限，因此脚本中使用了一个 macOS 专用的简单参数解析分支。
- macOS 下通过 `ifconfig` 获取第一个非 loopback IPv4 地址，因为 `butil::my_ip()` 会用这个地址作为 raft peer identity；如果直接回退到 `127.0.0.1`，节点可能无法匹配自己的 peer id。
- 使用 Homebrew `glog 0.6.0` 时跳过 `crash_on_fatal_log`，因为该版本没有暴露这个 gflags 选项。

配置并构建：

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

## 运行 counter 示例

进入 `example/counter` 目录：

```bash
cp bld/counter_server bld/counter_client .
bash run_server.sh --clean --server_num=3 --port=8100
# 另开一个 shell，或者用 timeout 做一次快速 smoke test：
timeout 10s bash run_client.sh --server_num=3 --server_port=8100 --log_each_request=true
bash stop.sh
```

预期结果：

- 三个 server 进程会在 `example/counter/runtime/0..2` 下启动。
- client 能发现 leader，并输出成功的 `fetch_add` 响应。
- `runtime/*/std.log` 中可以看到 raft 启动、选主等日志。

示例验证方式：

- `runtime/0/std.log` 中出现第一个 peer 成为 leader 的日志，例如 `<local-ip>:8100:0:0` 对应的 `become leader`。
- `client.log` 中出现来自 leader 的成功响应，并且 counter value 在短时间 smoke test 中持续递增。
