#!/usr/bin/env bash
# 把 flutter build linux 的产物打成 RPM。
#
#   flutter build linux --release
#   linux/packaging/rpm/build-rpm.sh
#
# 需要 rpm-build 与 desktop-file-utils。产物路径会在结尾打印。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NAME=jianjin

# 版本以 pubspec 为准，不另设常量——常量迟早忘记同步
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$REPO_ROOT/pubspec.yaml")"
[[ -n "$VERSION" ]] || { echo "无法从 pubspec.yaml 解析版本号" >&2; exit 1; }

case "$(uname -m)" in
  x86_64)  BUNDLE_ARCH=x64 ;;
  aarch64) BUNDLE_ARCH=arm64 ;;
  *) echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

BUNDLE="$REPO_ROOT/build/linux/$BUNDLE_ARCH/release/bundle"
[[ -d "$BUNDLE" ]] || {
  echo "找不到 $BUNDLE" >&2
  echo "请先运行：flutter build linux --release" >&2
  exit 1
}

command -v rpmbuild >/dev/null || {
  echo "缺少 rpmbuild，请先安装：sudo dnf install rpm-build desktop-file-utils" >&2
  exit 1
}

TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT
mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

STAGE="$TOP/$NAME-$VERSION"
mkdir -p "$STAGE"
cp -a "$BUNDLE" "$STAGE/bundle"
cp "$REPO_ROOT/linux/packaging/$NAME.desktop" "$STAGE/"
cp -a "$REPO_ROOT/linux/packaging/icons" "$STAGE/"

tar -C "$TOP" -czf "$TOP/SOURCES/$NAME-$VERSION.tar.gz" "$NAME-$VERSION"

rpmbuild \
  --define "_topdir $TOP" \
  --define "version $VERSION" \
  -bb "$REPO_ROOT/linux/packaging/rpm/$NAME.spec"

OUT_DIR="$REPO_ROOT/build/rpm"
mkdir -p "$OUT_DIR"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT_DIR/" \;

echo
echo "已生成："
ls -1 "$OUT_DIR"/*.rpm
echo
echo "安装：sudo dnf install $OUT_DIR/$NAME-$VERSION-1.*.rpm"
