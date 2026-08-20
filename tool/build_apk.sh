#!/usr/bin/env bash
# FnMusic 打包脚本：编译 release / debug 安装包。
#
# 用法：
#   ./tool/build_apk.sh             # 编译 release + debug（fat APK）
#   ./tool/build_apk.sh release     # 仅 release
#   ./tool/build_apk.sh debug       # 仅 debug
#   ./tool/build_apk.sh release --split   # 按 ABI 拆分（arm64-v8a / armeabi-v7a / x86_64）
#
# 构建环境（见 memory「FnMusic 构建环境」）：本机网络受限，依赖已在离线
# pub cache；Gradle 9.2.0 / AGP 9.0.0，已关闭 Kotlin 增量编译。
# 产物输出到 build/app/outputs/flutter-apk/。

set -euo pipefail

cd "$(dirname "$0")/.."

# 定位 Flutter
FLUTTER=""
if command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
elif [ -x "/c/dev/flutter/bin/flutter" ]; then
  FLUTTER="/c/dev/flutter/bin/flutter"
else
  echo "[错误] 未找到 flutter，请确认已安装并加入 PATH。" >&2
  exit 1
fi

MODE="${1:-all}"
EXTRA=""
if [[ " ${*:2} " == *" --split "* ]]; then
  EXTRA="--split-per-abi"
fi

echo "==> flutter pub get"
"$FLUTTER" pub get

build_one() {
  local variant="$1"
  echo ""
  echo "==> flutter build apk --$variant $EXTRA"
  # shellcheck disable=SC2086
  "$FLUTTER" build apk "--$variant" $EXTRA
}

case "$MODE" in
  release) build_one release ;;
  debug) build_one debug ;;
  all) build_one release; build_one debug ;;
  *)
    echo "[错误] 未知模式: $MODE（可用: all / release / debug）" >&2
    exit 1
    ;;
esac

echo ""
echo "==================== 构建完成 ===================="
OUT_DIR="build/app/outputs/flutter-apk"
if [ -d "$OUT_DIR" ]; then
  # shellcheck disable=SC2012
  ls -lh "$OUT_DIR"/*.apk 2>/dev/null | awk '{print $5, $9}'
else
  echo "[提示] 未找到产物目录 $OUT_DIR"
fi
