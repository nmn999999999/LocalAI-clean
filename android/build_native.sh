#!/usr/bin/env bash
# 用 Android NDK 把 llama.cpp + mtmd 编译成 liblocalai.so（放入 app/src/main/jniLibs/arm64-v8a/）。
# 前置：Android SDK/NDK 已安装（NDK 26.x）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA=/tmp/llama.cpp
ANDROID_NDK="${ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/26.3.11579264}"
BUILD=/tmp/llama-android

echo ">>> 交叉编译 llama.cpp + mtmd（arm64-v8a）"
cmake -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_OPENMP=OFF -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_LLAMAFILE=OFF \
  -DLLAMA_BUILD_COMMON=ON -DLLAMA_BUILD_MTMD=ON \
  -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF \
  "$LLAMA"
cmake --build "$BUILD" --config Release -j 8 \
  --target llama llama-common mtmd ggml ggml-base ggml-cpu vendor-hash

echo ">>> 链接 liblocalai.so"
CLANG="$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android26-clang++"
OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$OUT"
"$CLANG" -std=c++17 -O2 -fPIC -shared \
  -I"$LLAMA/include" -I"$LLAMA/ggml/include" -I"$LLAMA/common" \
  -I"$LLAMA/tools/mtmd" -I"$LLAMA/vendor" \
  -I"$ROOT/android/app/src/main/cpp" \
  "$ROOT/android/app/src/main/cpp/JniBridge.cpp" "$ROOT/android/app/src/main/cpp/LlamaBridge.cpp" \
  "$BUILD/src/libllama.a" \
  "$BUILD/common/libllama-common.a" "$BUILD/common/libllama-common-base.a" \
  "$BUILD/ggml/src/libggml.a" "$BUILD/ggml/src/libggml-base.a" "$BUILD/ggml/src/libggml-cpu.a" \
  "$BUILD/tools/mtmd/libmtmd.a" "$BUILD/vendor/hash/libvendor-hash.a" \
  -o "$OUT/liblocalai.so"

# 运行时依赖 libc++_shared.so
cp "$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$OUT/"

echo "=== 完成: $OUT/liblocalai.so ==="
