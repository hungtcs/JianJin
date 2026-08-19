#!/usr/bin/env bash
# 把 flutter build linux 的产物安装到当前用户目录（无需 root）。
#
#   flutter build linux --release
#   linux/packaging/install.sh
#
# 卸载：linux/packaging/install.sh --uninstall
set -euo pipefail

APP=jianjin
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"

PREFIX="${PREFIX:-$HOME/.local}"
OPT_DIR="$PREFIX/lib/$APP"
BIN_DIR="$PREFIX/bin"
DESKTOP_DIR="$PREFIX/share/applications"
ICON_ROOT="$PREFIX/share/icons/hicolor"

uninstall() {
  rm -rf "$OPT_DIR" "$BIN_DIR/$APP" "$DESKTOP_DIR/$APP.desktop"
  find "$ICON_ROOT" -name "$APP.png" -delete 2>/dev/null || true
  echo "已卸载 $APP"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
else
  [[ -d "$BUNDLE" ]] || {
    echo "找不到 $BUNDLE" >&2
    echo "请先运行：flutter build linux --release" >&2
    exit 1
  }

  mkdir -p "$OPT_DIR" "$BIN_DIR" "$DESKTOP_DIR"
  rm -rf "${OPT_DIR:?}/"*
  cp -r "$BUNDLE/." "$OPT_DIR/"

  # 用符号链接而非 wrapper：可执行文件靠 /proc/self/exe 定位
  # 同级的 lib/ 与 data/，符号链接会被解析到真实路径，不会失效
  ln -sf "$OPT_DIR/$APP" "$BIN_DIR/$APP"

  install -m644 "$REPO_ROOT/linux/packaging/$APP.desktop" "$DESKTOP_DIR/$APP.desktop"
  for dir in "$REPO_ROOT/linux/packaging/icons"/*/; do
    size="$(basename "$dir")"
    install -Dm644 "$dir/$APP.png" "$ICON_ROOT/$size/apps/$APP.png"
  done

  command -v update-desktop-database >/dev/null && \
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && \
    gtk-update-icon-cache -f -t "$ICON_ROOT" 2>/dev/null || true

  echo "已安装到 $OPT_DIR"
  echo "可执行文件：$BIN_DIR/$APP"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "提示：$BIN_DIR 不在 PATH 中" ;;
  esac
fi
