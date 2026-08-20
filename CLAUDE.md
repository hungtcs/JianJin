# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

剪金 JianJin —— 从视频中快速挑选有用片段并无损导出的桌面应用。
功能与交互见 [README](README.md)，构建与打包细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 常用命令

```bash
flutter pub get
flutter analyze                       # 提交前必跑，仓库保持零 issue
flutter run -d macos                  # 或 linux / windows

flutter test                          # 全量
flutter test test/settings_test.dart  # 单个文件
flutter test --plain-name '关键帧吸附'  # 按用例名筛选
flutter test -x integration           # 跳过需要本机 ffmpeg 的端到端用例
```

视觉快照默认跳过（测试环境无真实字体、像素依机器而异），按需运行：

```bash
flutter test --run-skipped -t shots --update-goldens   # 产物在 test/shots/
```

打包脚本：`macos/packaging/build-dmg.sh`、`linux/packaging/install.sh`、
`linux/packaging/rpm/build-rpm.sh`。

## 架构

三层，边界清晰：

```
services/   ffmpeg / ffprobe 子进程。所有编解码知识集中在这里
state/      AppState（ChangeNotifier）持有片段、撤销栈、分析任务编排
ui/         全部自绘。入口是 WidgetsApp 而非 MaterialApp
player/     media_kit(libmpv) 的薄封装
```

**播放与切割是两套独立管线**：播放走 libmpv（`PlayerController`），切割与分析走
ffmpeg 子进程（`FfmpegService` / `FfprobeService`）。两者不共享解码器，改一边不影响
另一边。

**时间轴的两条轨共享一个 `TimelineViewController`**（`ui/timeline/`）。这是刻意的：
「播放跟随」与「用户手动平移」必须只有一个裁决点，否则二者每帧互相覆盖，表现为抖动。
全片条只控制视口，从不改播放进度。

**打开文件后的三项分析串行执行**（`AppState._runAnalysis`）：关键帧 → 波形 → 缩略图。
顺序按「先决条件 + 代价」排，并行会和 mpv 解码抢 CPU。

## 必须遵守的约定

这些都是踩过之后用测试锁住的。改相关代码前先看对应测试。

**无损切割只吸附起点，终点必须精确。** 终点向后吸附会白白多包一整个 GOP，并在末尾
留下属于后续内容的关键帧（表现为「结尾画面跳一下」）。
`test/export_integration_test.dart` 有回归测试。

**吸附造成的时长偏差必须在界面上可见。** 不允许出现「标 5 秒导出 10 秒」这类沉默差异；
`ExportRange` 负责计算真实导出区间，片段列表按它显示。

**导出不得静默覆盖同名文件。** 命名规则集中在 `FfmpegService.outputNameFor`。

**命中区必须与可见区一致。** 刻度尺带没有绘制片段就不能拖动片段；全片条视口框的
绘制宽度与命中宽度必须取同一个最小值，否则用户抓可见边缘时抓到的是中段。
见 `test/timeline_interaction_test.dart`、`test/overview_bar_test.dart`。

**布局改动必须有渲染测试。** `flutter analyze` 与 `flutter build` 全绿的代码仍可能
一运行就崩（如 `Row(stretch)` 放进 `Column` 触发无限高度约束）。改 widget 树后要在
**贴近真实的约束环境**下 pump 一次并断言无异常，见 `test/timeline_layout_test.dart`。

**Linux 原生菜单的动作名是跨语言契约。** `linux/runner/my_application.cc` 的
`kMenuActions` 与 `ui/native_menu_bridge.dart` 的分发分支必须一一对应——多一个是死
代码，少一个是菜单项永久变灰或点击无反应，而两边单独看都「没问题」。
`test/native_menu_contract_test.dart` 会跨语言核对。

**关闭缩略图/波形要真的不起 ffmpeg 进程**，而不只是不显示——它们正是打开大文件时的
主要开销。设置变化时还需按需补算（分析只在打开文件时跑一次，那时开关若是关的就完全
没有数据）。见 `test/app_state_analysis_test.dart`。

**不要引入 `package:flutter/material.dart`。** 全部 UI 自绘，`uses-material-design: false`。
需要 Material 才有的东西（Tooltip、Dialog 等）请用 `OverlayPortal` 自行实现，
`ui/widgets/button.dart` 里有现成的例子。

**`media_kit_video` 锁在 1.x，不要升到 2.x。** 2.x 的 Swift 代码要用 libmpv 的 C 类型，
而配套的 `media_kit_libs_macos_video` 至今没有随包提供头文件，macOS 上直接编译失败。
Linux 因链接系统 libmpv 而不受影响，所以升级后问题只在 macOS 暴露。

**macOS 的 App Sandbox 必须保持关闭**（`macos/Runner/*.entitlements`）。沙箱进程无法
exec bundle 之外的可执行文件，开启会让 ffmpeg 调用静默失败。

## 编辑代码时

对 Dart 源码做锚点式文本替换容易**静默失败**——`dart format` 会在两次编辑之间重排
缩进，使先前记下的锚点失效，而替换找不到锚点时不会报错。改完立刻 grep 验证目标内容
确实存在；能交给编译器兜底的（如把永远该接线的回调设为 `required`）就别靠注释提醒。
