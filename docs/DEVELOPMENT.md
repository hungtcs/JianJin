# 剪金 JianJin — 开发文档

项目介绍见 [README](../README.md)。

## 技术栈

| 层        | 选型                    | 说明                                                     |
| --------- | ----------------------- | -------------------------------------------------------- |
| UI        | Flutter，**全部自绘**   | 不引入 `material.dart`，入口用 `WidgetsApp`              |
| 播放      | `media_kit`（libmpv）   | libmpv 即 ffmpeg，你的文件都能播；各平台预编译库随包分发 |
| 切割/探测 | ffmpeg / ffprobe 子进程 | 无损 `-c copy`                                           |

跨平台：macOS / Windows / Linux。

## 品牌资源

Logo 源文件在 `design/logo/`（**不打包进应用**），产物在 `assets/logo/`
与各平台图标目录。改动 SVG 后重新生成：

```bash
# macOS 图标：图形内缩到画布 80.5%（Apple 的 824/1024 网格）。
# 满幅会让它在 Dock 里比别的应用大一圈。
for S in 16 32 64 128 256 512 1024; do
  ART=$(python3 -c "print(round($S*0.8047))")
  rsvg-convert -w $ART -h $ART design/logo/jianjin-logo-icon.svg -o /tmp/a.png
  magick /tmp/a.png -background none -gravity center -extent ${S}x${S} \
    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$S.png
done

# 界面内资源（1x/2x/3x）
for M in 1 2 3; do
  D=assets/logo; [ $M -ne 1 ] && D=assets/logo/${M}.0x
  rsvg-convert -w $((200*M)) -h $((62*M)) design/logo/jianjin-logo-full-dark.svg -o $D/logo_full.png
  rsvg-convert -w $((64*M))  -h $((64*M)) design/logo/jianjin-logo-icon-dark.svg  -o $D/logo_icon.png
done
```

深色界面用 `*-dark.svg` 变体：原 logo 的「剪金」是深色字，放在深色界面上看不见，
故改为浅色；图标底框也从 `#1E1B18` 提到 `#2A2521`，否则和面板底色 `#1F1F22`
几乎一样，圆角框会整个消失。

## 依赖

需要本机有 `ffmpeg` 和 `ffprobe`。程序会依次在应用同级目录、macOS `.app` 内
`Resources/`、常见安装路径、系统 `PATH` 中查找（GUI 应用继承的 `PATH` 往往很贫瘠，
所以不能只靠 `PATH`）。

```bash
brew install ffmpeg              # macOS
sudo dnf install ffmpeg-free     # Fedora（主仓即可，无需 RPM Fusion）
sudo apt install ffmpeg          # Debian/Ubuntu
winget install ffmpeg            # Windows
```

## 运行

```bash
flutter pub get
flutter run -d macos     # 或 windows / linux
```

## Linux 打包

`flutter build linux --release` 产出的是一个**便携目录**
`build/linux/x64/release/bundle/`：

```
bundle/
├── jianjin              可执行文件
├── lib/                 Flutter 引擎与各插件的 .so（含 libmpv 相关）
└── data/
    ├── flutter_assets/  应用资源
    └── icons/app_icon.png   窗口图标
```

整个目录可直接压缩分发，解压即可运行——可执行文件通过 `/proc/self/exe`
定位同级的 `lib/` 与 `data/`。

### 安装到系统

裸 bundle 在应用菜单里既没有名字也没有图标，需要装 `.desktop` 与主题图标：

```bash
flutter build linux --release
linux/packaging/install.sh          # 装到 ~/.local，无需 root
linux/packaging/install.sh --uninstall
```

脚本会把 bundle 放进 `~/.local/lib/jianjin`，在 `~/.local/bin` 建符号链接，
并安装 `.desktop` 与 8 档 hicolor 主题图标（16–512）。

### 运行时依赖

| 依赖 | 用途 | Debian/Ubuntu | Fedora | Arch |
|---|---|---|---|---|
| `libmpv` | 播放（media_kit） | `libmpv2` | `mpv-libs` | `mpv` |
| `ffmpeg` | 切割与分析 | `ffmpeg` | `ffmpeg` | `ffmpeg` |
| GTK 3 | 窗口 | `libgtk-3-0` | `gtk3` | `gtk3` |

### 构建依赖

**Fedora**（以下组合已在纯净 `fedora:41` 容器中实测通过，**无需 RPM Fusion**）：

```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config \
                 gtk3-devel xz-devel libstdc++-devel mpv-libs-devel
# 打 RPM 另需：
sudo dnf install rpm-build desktop-file-utils
```

注意包名是 **`mpv-libs-devel`**（Fedora 没有 `libmpv-devel` 这个包）。
它在 Fedora 主仓即可获得，`pkg-config --modversion mpv` 应输出 2.3.0 或更高。

**Debian / Ubuntu**：

```bash
sudo apt install clang cmake ninja-build pkg-config \
                 libgtk-3-dev liblzma-dev libmpv-dev
```

### RPM（Fedora）

```bash
flutter build linux --release
linux/packaging/rpm/build-rpm.sh      # 需要 rpm-build desktop-file-utils
sudo dnf install build/rpm/jianjin-*.rpm
```

打的是**预编译产物**而非在 rpmbuild 里编译源码——Flutter SDK 不在 Fedora
仓库中，没法作为 `BuildRequires`。版本号从 pubspec 解析，不另设常量。

spec 里有两处依赖是刻意这么写的：

- `Requires: libmpv.so.2()(64bit)` —— 按 **soname** 而非包名。libmpv
  在 Fedora 主仓和 RPM Fusion 都可能由 `mpv-libs` 提供，写死包名会在其中
  一种情况下解析失败。
- `Requires: /usr/bin/ffmpeg` —— 按**路径**声明，`ffmpeg` 与 `ffmpeg-free`
  都能满足，不强制你启用 RPM Fusion。

另外应用自带的 `.so` 都在私有目录 `%{_libdir}/jianjin/` 下，spec 用
`__provides_exclude_from` / `__requires_exclude_from` 把它们排除在自动
依赖分析之外——否则 Flutter 引擎和插件的 so 会被当成系统库对外提供，
污染整个系统的依赖解析。

**尚未提供** AppImage / deb / Flatpak——目前是便携目录 + 安装脚本 + RPM。

## 测试

```bash
flutter test                      # 全部
flutter test -x integration       # 跳过需要 ffmpeg 的端到端测试
```

视觉快照（默认跳过：测试环境无真实字体、像素结果依机器而异）：

```bash
flutter test --run-skipped -t shots --update-goldens
# 产物在 test/shots/
```

`test/export_integration_test.dart` 会用 ffmpeg 造一个 GOP=2s 的素材，
走真实管线导出并校验产物时长与编码。其中包含一条**回归测试**锁定
「终点不得被吸附」——这是「标 5 秒导出 13 秒」的主因。

## macOS 沙箱

`macos/Runner/*.entitlements` 中 App Sandbox 已**关闭**：沙箱进程无法 exec
bundle 之外的可执行文件，开启会导致 ffmpeg 调用失败。若要上架 Mac App Store，
需把 ffmpeg 打进 bundle 后重新开启。
