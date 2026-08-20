import 'dart:io';

import 'package:flutter/services.dart';

import 'app_menu.dart';

/// 与 Linux 原生 GTK 菜单之间的桥，双向：
/// C → Dart 发送被点击的动作名；Dart → C 推送菜单项的可用状态。
///
/// 曾经菜单永久变灰，我一度归咎于这套同步机制并把它整个删掉，那是**误判**——
/// 真凶是 onSettings 从未接线。不过当时暴露的时序问题是真的：Dart 首帧的推送
/// 可能早于 C 侧注册处理器而被丢弃，加上变化检测缓存不会重推，状态就永久过期。
/// 现在由 C 侧在处理器就绪后发 `ready`，Dart 收到即清缓存重推一次。
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
  Map<String, bool>? _lastPushed;
  bool _installed = false;

  /// 更新动作集并按需同步可用状态。每次 build 调用即可——
  /// 启用表没变化时不会产生通道往返，播放时每秒十几次重建也不会刷屏。
  void setActions(AppMenuActions actions) {
    if (!isSupported) return;
    _actions = actions;
    if (!_installed) {
      _installed = true;
      _channel.setMethodCallHandler(_onNativeCall);
    }
    _pushEnabled(actions);
  }

  void _pushEnabled(AppMenuActions actions) {
    final enabled = _enabledMap(actions);
    if (_mapEquals(enabled, _lastPushed)) return;
    _lastPushed = enabled;
    _channel.invokeMethod<void>('setEnabled', enabled);
  }

  Map<String, bool> _enabledMap(AppMenuActions a) => <String, bool>{
        'open': true,
        'close': a.onCloseFile != null,
        'export': a.onExport != null,
        'undo': a.onUndo != null,
        'clearAll': a.onClearAll != null,
        // 这两项不依赖任何应用状态，构造时即为必填，恒可用
        'settings': true,
        'about': true,
      };

  static bool _mapEquals(Map<String, bool> a, Map<String, bool>? b) {
    if (b == null || a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'ready') {
      // C 侧到此刻才注册好处理器，之前的推送可能已被丢弃。清缓存重推，
      // 否则变化检测会认为「已经推过了」，菜单停在过期状态。
      _lastPushed = null;
      final actions = _actions;
      if (actions != null) _pushEnabled(actions);
      return null;
    }
    if (call.method != 'activate') return null;
    final id = call.arguments as String?;
    final actions = _actions;
    if (id == null || actions == null) return null;
    _dispatch(actions, id)?.call();
    return null;
  }

  /// 分支必须与 C 侧 kMenuActions 一一对应，多一个是死代码、少一个是点了没
  /// 反应。`native_menu_contract_test.dart` 会跨语言核对这一点。
  VoidCallback? _dispatch(AppMenuActions a, String id) => switch (id) {
        'open' => a.onOpen,
        'close' => a.onCloseFile,
        'export' => a.onExport,
        'undo' => a.onUndo,
        'clearAll' => a.onClearAll,
        'settings' => a.onSettings,
        'about' => a.onAbout,
        _ => null,
      };
}
