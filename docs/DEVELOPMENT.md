# 剪金 JianJin — 开发文档

功能与交互见 [README](../README.md)。

## 技术栈

| 层 | 选型 | 说明 |
| --- | --- | --- |
| UI | Flutter，**全部自绘** | 不引入 `material.dart`，入口用 `WidgetsApp` |
| 播放 | `media_kit`（libmpv） | libmpv 即 ffmpeg，ffmpeg 能解的都能播 |
| 切割 / 探测 | ffmpeg / ffprobe 子进程 | 无损 `-c copy` |

跨平台：macOS / Windows / Linux。

> **libmpv 的分发方式因平台而异**：macOS 与 Windows 由 `media_kit_libs_*`
> 随包提供预编译库；**Linux 链接系统的 libmpv**（`ldd` 可见
> `libmpv.so.2 => /lib64/libmpv.so.2`），因此 Linux 必须安装 `mpv-libs`，
> RPM 也据此声明依赖。

## 环境准备

三个平台都需要本机有 **ffmpeg / ffprobe**。程序按「应用同级目录 → macOS
`.app` 内 `Resources/` → 常见安装路径 → 系统 `PATH`」的顺序查找——GUI 应用
继承的 `PATH` 往往很贫瘠，不能只靠 `PATH`。

| 平台 | 运行时 | 额外的构建依赖 |
| --- | --- | --- |
| macOS | `brew install ffmpeg` | Xcode、CocoaPods（`brew install cocoapods`） |
| Fedora | `sudo dnf install ffmpeg-free mpv-libs gtk3` | `clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel mpv-libs-devel` |
| Debian/Ubuntu | `sudo apt install ffmpeg libmpv2 libgtk-3-0` | `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev` |
| Windows | `winget install ffmpeg` | Visual Studio（Desktop C++） |

Fedora 上的两个坑：包名是 **`mpv-libs-devel`**（没有 `libmpv-devel` 这个包），
且**无需 RPM Fusion**——上面这套依赖已在纯净 `fedora:41` 容器中实测通过。
装完可验证 `pkg-config --modversion mpv`，应为 2.3.0 或更高。

## 运行与构建

```bash
flutter pub get
flutter run -d macos                 # 或 windows / linux
flutter build linux --release        # 产物见下节
```

## 平台注意事项

### macOS：App Sandbox 必须关闭

`macos/Runner/*.entitlements` 中 App Sandbox 已关闭。沙箱进程无法 exec bundle
之外的可执行文件，开启会让 ffmpeg 调用**静默失败**。若要上架 Mac App Store，
需先把 ffmpeg 打进 bundle 再重新开启。

### Linux：install 前缀与窗口图标

`flutter build linux` 会执行 `ninja install`，但那只是用 CMake 的 install 机制
把产物归拢成便携 bundle，**不是安装到系统**。前缀由 `linux/CMakeLists.txt`
重定向到 `build/<arch>/<mode>/bundle`。

该重定向原本由 `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` 守卫，而它只在构建
目录**首次** configure 时为真——一旦首次 configure 中途失败（例如缺 `mpv-libs-devel`），
缓存会留下 CMake 默认的 `/usr/local`，此后每次重建都报 `Permission denied` 且无法自愈。
工程已加入校正逻辑：前缀落在构建树之外时自动重置并打印 warning。**不要用 sudo 绕过**，
那会真的把文件装进系统目录。

窗口图标从可执行文件同级的 `data/icons/app_icon.png` 读取（`/proc/self/exe` 定位），
这样便携 bundle 解压即可用，不依赖系统图标主题。

### Windows

图标与产品信息已配置，**构建尚未验证**。

## Linux 分发

`flutter build linux --release` 产出便携目录：

```
build/linux/<arch>/release/bundle/
├── jianjin              可执行文件
├── lib/                 Flutter 引擎与各插件的 .so
└── data/
    ├── flutter_assets/  应用资源
    └── icons/app_icon.png
```

可直接压缩分发，解压即跑。

### 装到当前用户

裸 bundle 在应用菜单里没有名字也没有图标：

```bash
linux/packaging/install.sh              # 装到 ~/.local，无需 root
linux/packaging/install.sh --uninstall
```

放进 `~/.local/lib/jianjin`，在 `~/.local/bin` 建符号链接，并安装 `.desktop`
与 8 档 hicolor 图标（16–512）。

### RPM

```bash
sudo dnf install rpm-build desktop-file-utils
linux/packaging/rpm/build-rpm.sh
sudo dnf install build/rpm/jianjin-*.rpm
```

打的是**预编译产物**而非在 rpmbuild 里编译源码——Flutter SDK 不在 Fedora 仓库中，
没法作为 `BuildRequires`。版本号从 pubspec 解析，不另设常量。

spec 里三处刻意的写法：

- `Requires: libmpv.so.2()(64bit)` 按 **soname** 而非包名。libmpv 在 Fedora
  主仓和 RPM Fusion 都可能由 `mpv-libs` 提供，写死包名会在其中一种情况下解析失败。
- `Requires: /usr/bin/ffmpeg` 按**路径**声明，`ffmpeg` 与 `ffmpeg-free` 都能满足，
  不强制启用 RPM Fusion。
- `__provides_exclude_from` / `__requires_exclude_from` 把私有目录
  `%{_libdir}/jianjin/` 下自带的 `.so` 排除在自动依赖分析之外，否则 Flutter
  引擎与插件的 so 会被当成系统库对外提供，污染整个系统的依赖解析。

已在 fedora:41（aarch64）实测：构建、打包、`rpm -qpR` 依赖解析、`dnf install`
安装、`desktop-file-validate` 校验全流程通过。**x86_64 尚未验证。**

**尚未提供** AppImage / deb / Flatpak。

## 品牌资源

Logo 源文件在 `design/logo/`（**不打包进应用**），产物在 `assets/logo/` 与各平台
图标目录。深色界面用 `*-dark.svg` 变体：原 logo 的「剪金」是深色字，放在深色界面上
看不见；图标底框也从 `#1E1B18` 提到 `#2A2521`，否则和面板底色 `#1F1F22` 几乎一样，
圆角框会整个消失。

改动 SVG 后重新生成：

```bash
# macOS 图标：图形内缩到画布 80.5%（Apple 的 824/1024 网格），
# 满幅会让它在 Dock 里比别的应用大一圈
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

## 测试

```bash
flutter test                    # 全部
flutter test -x integration     # 跳过需要 ffmpeg 的端到端测试
```

视觉快照默认跳过（测试环境无真实字体、像素结果依机器而异），按需运行：

```bash
flutter test --run-skipped -t shots --update-goldens   # 产物在 test/shots/
```

`test/export_integration_test.dart` 会用 ffmpeg 造一个 GOP=2s 的素材，走真实管线
导出并校验产物时长与编码。

## 改动时容易踩的坑

这些约定都是踩过之后才补上测试锁住的，改相关代码前值得先看一眼：

- **终点不得吸附关键帧**。曾经起点终点都吸附，导致「标 5 秒导出 13 秒」并伴随
  结尾跳帧。`export_integration_test.dart` 有回归测试锁定。
- **命中区必须与可见区一致**。刻度尺没画片段就不能拖片段；全片条的视口框，
  绘制宽度与命中宽度必须取同一个最小值，否则用户抓可见边缘时抓到的是中段。
  `timeline_interaction_test.dart` / `overview_bar_test.dart` 覆盖。
- **布局改动必须有渲染测试**。`flutter analyze` 与 `flutter build` 全绿的代码
  仍可能一运行就崩（如 `Row(stretch)` 放进 `Column` 触发无限高度）。
  改 widget 树后要在**贴近真实的约束环境**下 pump 一次并断言无异常。
- **跟随与手动平移只能有一个裁决点**。二者若各自改视图状态会每帧互相覆盖，
  表现为抖动。逻辑集中在 `TimelineViewController`，规则由
  `timeline_view_controller_test.dart` 逐条锁定。
- **导出不得静默覆盖**。命名规则集中在 `FfmpegService.outputNameFor`，
  将来做「命名策略设置」也只需替换这一处。
