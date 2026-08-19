import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 菜单要触发的动作。为 null 表示当前不可用（菜单项会自动置灰）。
class AppMenuActions {
  const AppMenuActions({
    required this.onOpen,
    this.onAbout,
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
    this.onRetro,
    this.onCancelPending,
    this.retroSeconds = 12,
  });

  final VoidCallback onOpen;
  final VoidCallback? onAbout;
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
  final VoidCallback? onRetro;
  final VoidCallback? onCancelPending;

  final int retroSeconds;
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
    // 窗口内菜单待 Windows/Linux 再补。
    if (!Platform.isMacOS) return child;

    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: '剪金',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformMenuItemGroup(members: [
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
            PlatformMenuItemGroup(members: [
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
            PlatformMenuItem(
              label: '回补 ${actions.retroSeconds} 秒  (A)',
              onSelected: actions.onRetro,
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
      ],
      child: child,
    );
  }
}
