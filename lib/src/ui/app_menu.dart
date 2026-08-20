import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 菜单要触发的动作。为 null 表示当前不可用（菜单项会自动置灰）。
class AppMenuActions {
  const AppMenuActions({
    required this.onOpen,
    // 关于与设置不依赖任何应用状态，永远可用。设为必填是为了让漏接线
    // 变成编译错误——它们曾因一次静默失败的编辑而未接上，表现为菜单项
    // 点了没反应，很难查。
    required this.onAbout,
    required this.onSettings,
    this.onCloseFile,
    this.onExport,
    this.onUndo,
    this.onDeleteSelected,
    this.onClearAll,
    this.onPlayPause,
    this.onFaster,
    this.onSlower,
    this.onResetRate,
    this.onBack5,
    this.onForward5,
    this.onPrevFrame,
    this.onNextFrame,
    this.onMarkIn,
    this.onMarkOut,
    this.onCancelPending,
  });

  final VoidCallback onOpen;
  final VoidCallback onAbout;
  final VoidCallback onSettings;
  final VoidCallback? onCloseFile;
  final VoidCallback? onExport;

  final VoidCallback? onUndo;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onClearAll;

  final VoidCallback? onPlayPause;
  final VoidCallback? onFaster;
  final VoidCallback? onSlower;
  final VoidCallback? onResetRate;
  final VoidCallback? onBack5;
  final VoidCallback? onForward5;
  final VoidCallback? onPrevFrame;
  final VoidCallback? onNextFrame;

  final VoidCallback? onMarkIn;
  final VoidCallback? onMarkOut;
  final VoidCallback? onCancelPending;
}

/// 真正的系统菜单栏（macOS 上是原生 NSMenu）。
///
/// 单键快捷键（I/O/A/Space/J/K/L 等）**刻意不绑定到菜单项**：
/// 菜单快捷键会全局拦截按键，绑定无修饰键会让这些键在任何地方都被吃掉。
/// 它们由窗口内的 Focus 处理，菜单里只在标签上标注按键作为提示。
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.actions, required this.child});

  final AppMenuActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // PlatformMenuBar 目前只在 macOS 落到原生菜单；其余平台原样透传，
    // 窗口内菜单由 WindowMenuButton（Windows）与 GTK 原生菜单（Linux）承担。
    if (!Platform.isMacOS) return child;

    return PlatformMenuBar(menus: macMenus(actions), child: child);
  }
}

/// macOS 菜单栏的完整定义。
///
/// 独立成纯函数是为了能测：这里漏接一个回调不会有任何编译错误，
/// 表现只是「菜单里没这一项」或「点了没反应」，而 macOS 上又没有窗口内菜单
/// 可以兜底。`AppMenuActions` 把 onAbout / onSettings 设为必填只能保证
/// **调用方传了**，保证不了**菜单用了**——这一段正是之前漏掉的那一层。
/// 见 test/mac_menu_test.dart。
List<PlatformMenuItem> macMenus(AppMenuActions actions) {
  return [
    PlatformMenu(
      label: '剪金',
      menus: [
        // 刻意不用 PlatformProvidedMenuItemType.about：那个映射到 AppKit
        // 的标准关于面板（orderFrontStandardAboutPanel:），根本不会走
        // onAbout，应用内置的「关于」也就永远打不开。
        PlatformMenuItem(
          label: '关于剪金',
          onSelected: actions.onAbout,
        ),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '设置…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: actions.onSettings,
          ),
        ]),
        const PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hide,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.showAllApplications,
          ),
        ]),
        const PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ]),
      ],
    ),
    PlatformMenu(
      label: '文件',
      menus: [
        PlatformMenuItem(
          label: '打开…',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyO,
            meta: true,
          ),
          onSelected: actions.onOpen,
        ),
        PlatformMenuItem(
          label: '关闭文件',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyW,
            meta: true,
          ),
          onSelected: actions.onCloseFile,
        ),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '导出片段…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyE,
              meta: true,
            ),
            onSelected: actions.onExport,
          ),
        ]),
      ],
    ),
    PlatformMenu(
      label: '编辑',
      menus: [
        PlatformMenuItem(
          label: '撤销',
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
          ),
          onSelected: actions.onUndo,
        ),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '删除选中片段  (X)',
            onSelected: actions.onDeleteSelected,
          ),
          PlatformMenuItem(
            label: '清空全部片段',
            onSelected: actions.onClearAll,
          ),
        ]),
      ],
    ),
    PlatformMenu(
      label: '播放',
      menus: [
        PlatformMenuItem(
          label: '播放 / 暂停  (Space)',
          onSelected: actions.onPlayPause,
        ),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '加速  (L)',
            onSelected: actions.onFaster,
          ),
          PlatformMenuItem(
            label: '减速  (J)',
            onSelected: actions.onSlower,
          ),
          PlatformMenuItem(
            label: '恢复 1x  (K)',
            onSelected: actions.onResetRate,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '后退 5 秒  (←)',
            onSelected: actions.onBack5,
          ),
          PlatformMenuItem(
            label: '前进 5 秒  (→)',
            onSelected: actions.onForward5,
          ),
          PlatformMenuItem(
            label: '上一帧  (,)',
            onSelected: actions.onPrevFrame,
          ),
          PlatformMenuItem(
            label: '下一帧  (.)',
            onSelected: actions.onNextFrame,
          ),
        ]),
      ],
    ),
    PlatformMenu(
      label: '标记',
      menus: [
        PlatformMenuItem(
          label: '标入点  (I)',
          onSelected: actions.onMarkIn,
        ),
        PlatformMenuItem(
          label: '标出点  (O)',
          onSelected: actions.onMarkOut,
        ),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: '取消未完成的入点  (Esc)',
            onSelected: actions.onCancelPending,
          ),
        ]),
      ],
    ),
    const PlatformMenu(
      label: '窗口',
      menus: [
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.minimizeWindow,
        ),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.zoomWindow,
        ),
        PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ]),
      ],
    ),
  ];
}
