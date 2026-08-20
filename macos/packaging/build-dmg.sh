#!/usr/bin/env bash
# 打包 macOS 的 .dmg 安装镜像。
#
#   macos/packaging/build-dmg.sh              # 构建 release 后打包
#   macos/packaging/build-dmg.sh --skip-build # 复用已有的 release 产物
#
# 只用系统自带的 hdiutil，不依赖 create-dmg 之类的第三方工具。
set -euo pipefail

APP_NAME=JianJin
VOL_NAME=剪金
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)"
[[ -n "$VERSION" ]] || { echo "无法从 pubspec.yaml 解析版本号" >&2; exit 1; }

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> 构建 release"
  flutter build macos --release
fi

APP="build/macos/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || {
  echo "找不到 $APP" >&2
  echo "请先运行：flutter build macos --release" >&2
  exit 1
}

case "$(uname -m)" in
  arm64)  ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *)      ARCH="$(uname -m)" ;;
esac

OUT_DIR="build/dmg"
OUT="$OUT_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
mkdir -p "$OUT_DIR"
rm -f "$OUT"

# 暂存目录只放两样东西：应用本体，以及指向 /Applications 的符号链接。
# 这就是 macOS 上「拖进去安装」的标准形态，不需要背景图或图标定位——
# 那些要靠 AppleScript 操纵 Finder 写 .DS_Store，既脆弱又难以复现。
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> 生成 $OUT"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUT" >/dev/null

SIZE="$(du -h "$OUT" | cut -f1 | tr -d ' ')"
echo
echo "已生成：$OUT  ($SIZE)"
echo
echo "注意：该镜像未经 Apple 签名与公证。别人首次打开会被 Gatekeeper 拦下，"
echo "需要右键点应用选「打开」，或执行："
echo "  xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
