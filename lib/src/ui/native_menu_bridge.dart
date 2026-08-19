import 'dart:io';

import 'package:flutter/services.dart';

import 'app_menu.dart';

/// 与 Linux 原生 GTK 菜单之间的桥。**只有 C → Dart 一个方向**：
/// 菜单项被点击时把动作名发过来执行。
///
/// 刻意不做反向的启用状态同步。那需要两侧维护一致的启用表，而 Dart 首帧的
/// 推送可能早于 C 侧注册处理器而被丢弃，菜单会因此永久变灰——曾经就是这样。
/// 现在菜单项一律可用，不适用的动作在 Dart 侧自然是空操作；若点击时 Flutter
/// 尚未就绪，这一次没反应，再点一次即可。
///
/// **动作名必须与 `linux/runner/my_application.cc` 中的 `kMenuActions` 完全一致**，
/// 这是两侧唯一的契约，改一边必须改另一边。
class NativeMenuBridge {
  NativeMenuBridge._();

  static final NativeMenuBridge instance = NativeMenuBridge._();

  static const _channel = MethodChannel('jianjin/menu');

  /// 只有 Linux 走原生菜单；macOS 用 NSMenu，Windows 用窗口内菜单。
  static bool get isSupported => Platform.isLinux;

  AppMenuActions? _actions;
  bool _installed = false;

  /// 更新可供菜单调用的动作集。每次 build 调用即可，开销只是一次赋值。
  void setActions(AppMenuActions actions) {
    if (!isSupported) return;
    _actions = actions;
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'activate') return null;
    final id = call.arguments as String?;
    final actions = _actions;
    if (id == null || actions == null) return null;
    _dispatch(actions, id)?.call();
    return null;
  }

  VoidCallback? _dispatch(AppMenuActions a, String id) => switch (id) {
        'open' => a.onOpen,
        'close' => a.onCloseFile,
        'export' => a.onExport,
        'undo' => a.onUndo,
        'delete' => a.onDeleteSelected,
        'clearAll' => a.onClearAll,
        'markIn' => a.onMarkIn,
        'markOut' => a.onMarkOut,
        'playPause' => a.onPlayPause,
        'faster' => a.onFaster,
        'slower' => a.onSlower,
        'resetRate' => a.onResetRate,
        'back5' => a.onBack5,
        'forward5' => a.onForward5,
        'prevFrame' => a.onPrevFrame,
        'nextFrame' => a.onNextFrame,
        'settings' => a.onSettings,
        'about' => a.onAbout,
        _ => null,
      };
}
