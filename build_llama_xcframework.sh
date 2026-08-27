#!/usr/bin/env bash
# 用 Xcode 26.1 的 iOS SDK 把 llama.cpp + mtmd 交叉编译成 iOS arm64 的 xcframework。
# 前置：sudo xcodebuild -license accept （Xcode 26.1 许可已同意）
set -euo pipefail

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

LLAMA=/tmp/llama.cpp
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/llama.xcframework"
BUILD="$ROOT/build-ios"

rm -rf "$BUILD" "$OUT"

echo ">>> cmake configure (iOS arm64)"
cmake -B "$BUILD" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_COMMON=ON \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_MTMD=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_BUILD_UI=OFF \
  -DGGML_METAL=ON \
  -DGGML_BLAS=OFF \
  "$LLAMA"

echo ">>> cmake build (Release) — 仅构建静态库，跳过 iOS 上会报 bundle id 的命令行工具"
cmake --build "$BUILD" --config Release \
  --target ggml --target ggml-base --target ggml-cpu --target ggml-metal \
  --target llama --target llama-common --target llama-common-base \
  --target mtmd --target vendor-hash

echo ">>> collect static libs"
LIBS=$(find "$BUILD" -name "*.a" -path "*Release-iphoneos*" \
  | grep -E "libllama\.a|libmtmd\.a|libllama-common\.a|libllama-common-base\.a|libggml\.a|libggml-base\.a|libggml-cpu\.a|libggml-metal\.a|libvendor-hash\.a" \
  | tr '\n' ' ')
echo "libs: $LIBS"
[ -n "${LIBS// }" ] || { echo "未找到任何静态库"; exit 1; }

MERGED="$BUILD/libllama-ios.a"
libtool -static -o "$MERGED" $LIBS

echo ">>> gather headers"
HDR=$(mktemp -d)
cp "$LLAMA"/include/*.h "$HDR"/
cp "$LLAMA"/ggml/include/*.h "$HDR"/
cp -R "$LLAMA"/common/. "$HDR"/
cp "$LLAMA"/tools/mtmd/*.h "$HDR"/
mkdir -p "$HDR/nlohmann" && cp "$LLAMA"/vendor/nlohmann/json.hpp "$HDR/nlohmann/"
cp "$ROOT/LocalAI/LlamaCore/LlamaBridge.h" "$HDR"/

echo ">>> create xcframework"
xcodebuild -create-xcframework \
  -library "$MERGED" \
  -headers "$HDR" \
  -output "$OUT"

echo "=== 完成: $OUT ==="
