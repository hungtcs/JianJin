# 剪金 JianJin

从视频里**快速挑选出有用的片段**并无损导出。不是剪辑器——它假设你还不知道要什么，
所以整个界面为「比实时更快地扫描」而设计。

仓库：<https://github.com/hungtcs/JianJin>

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
brew install ffmpeg          # macOS
sudo apt install ffmpeg      # Debian/Ubuntu
winget install ffmpeg        # Windows
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

构建时另需 `libmpv-dev`、`libgtk-3-dev`、`clang`、`cmake`、`ninja-build`、
`pkg-config`、`liblzma-dev`。

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

## 键盘映射

工具为单手键盘操作设计，鼠标只用于事后微调。

| 键             | 行为                                   |
| -------------- | -------------------------------------- |
| `Space`        | 播放 / 暂停                            |
| `L` / `J`      | 加速 / 减速（1→2→4→8→16x）             |
| `K`            | 恢复 1x                                |
| `←` / `→`      | ±5s（按住 `Shift` 为 ±30s）            |
| `,` / `.`      | 逐帧后退 / 前进                        |
| `I`            | 标入点                                 |
| `O`            | 标出点                                 |
| `A`            | **回补**：生成「12 秒前 → 现在」的片段 |
| `X` / `Delete` | 删除选中片段                           |
| `Esc`          | 取消未完成的入点                       |
| `⌘/Ctrl+Z`     | 撤销                                   |
| `⌘/Ctrl+O`     | 打开文件                               |
| `Enter`        | 导出                                   |

## 时间轴交互

双层结构，两层共享同一份视图状态：

- **全片**（上）—— 整片地图。绿色块是已标片段，蓝框是下方细节轨正在看的范围。
  - **拖蓝框主体** → 平移细节轨
  - **拖蓝框左右边缘** → 缩放细节轨（改变可见范围）
  - **点空白处** → 视口移过去并跳转

  背景那层很淡的波形用来一眼找出静音段。播放位置是底边的小三角——这里
  **不画竖线**，因为它和下方处在不同缩放下，永远对不齐，反而误导。
- **细节**（下）—— 可缩放轨。滚轮平移，`⌘/Ctrl`+滚轮缩放，触控板双指捏合缩放。

### 片段编辑

鼠标移上去光标就会变，不用按下去试：

| 光标 | 位置 | 操作 |
|---|---|---|
| ↔ | 片段边缘 | 拖动调整该端点 |
| ✋ | 片段内部 | 拖动整体平移，**时长保持不变** |
| ✛ | 空白处 / 刻度尺 | 拖动 scrub |

**刻度尺那一条不参与片段交互**：它没有绘制片段，就不该能拖动片段。
交互区必须和可见区一致，否则会出现「看着不在框里却能拖」的错位。

选中的片段两端会显示抓手。

### 播放跟随

播放时视图自动跟随播放头。**一旦手动平移或缩放，立即交出跟随权**，此后视图
纹丝不动——这样滚动查看时不会和自动跟随打架。等播放头自己走进当前视野，
跟随权无声收回（此刻视图无需移动，所以不会跳）。

脱离期间「全片」标签下会出现一个黄色的 **「跟随」按钮**，点一下即回到播放头
并恢复跟随。这里给的是补救动作而不是一句解释——52px 宽的标签栏里也写不清楚。

## 三个让它「快」的设计

1. **回补打点（`A`）** —— 你永远是在片段*开始之后*才意识到「这段有用」。
   `I`/`O` 要求你预知起点，`A` 不要求，看到好东西随手一按。
2. **自动留白** —— 打点时前后各多留 600ms，避免把第一个字切掉。
3. **重叠自动合并** —— 标重叠了不报错，直接并成一段。

## 导出模式

界面右下角可切换，直接决定产物时长准不准：

| 模式             | 产物边界                   | 速度             | 画质         |
| ---------------- | -------------------------- | ---------------- | ------------ |
| **无损**（默认） | 起点对齐到关键帧，终点精确 | 极快（零重编码） | 不变         |
| **精确**         | 与标记完全一致             | 慢               | 重编码，有损 |

### 为什么无损模式起点会偏

`-c copy` 无法从 GOP 中间开始——必须从关键帧起。所以起点会**向前**吸附到最近的
关键帧，产物因此比标记的长一点。偏差等于起点到前一个关键帧的距离，取决于素材的
GOP 长度（录屏常见 2–10 秒）。

**终点不做吸附**，精确切即可：解码器读到指定时长就停。曾经的实现把终点也向后吸附
到下一个关键帧，那会白白多包一整个 GOP，并在末尾留下一个属于后续内容的关键帧，
表现为「结尾画面跳一下」。已修复，并有回归测试锁定。

### 偏差是可见的

片段列表会同时显示标记时长与**实际导出时长**，差额用黄色徽章标出（如 `+2.2s`）。
时间轴刻度尺下方画有关键帧位置，可以主动把入点对到关键帧上以消除偏差。
需要严格一致时切到「精确」模式。

关键帧提取用 `-show_entries packet=...` 读容器索引而非解码整个文件，长视频快一个数量级。

## 尚未实现

- 静音自动分割（`silencedetect`）与镜头切换检测 —— 数据模型已预留
  `SegmentOrigin.silenceGap` / `sceneCut`，产出的「提议」走同一套审核交互
- 片段列表持久化 / 工程文件
- smart cut（首尾 GOP 重编码 + 中间 copy 后拼接）—— 可同时拿到
  「边界精确」和「几乎无损」，是无损/精确两档之间的理想第三档

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
