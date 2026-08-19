import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_menu.dart';

/// 与 Linux 原生 GTK 菜单之间的桥。
///
/// C 侧在标题栏放了 GNOME 规范的「主菜单」（汉堡 + popover），菜单项被点击时
/// 通过本通道把动作名发过来执行；反过来，Dart 侧的可用状态变化时把整张
/// 启用表推回去，让菜单项该灰的灰。
///
/// **动作名必须与 `linux/runner/my_application.cc` 中的 `kMenuActions` 完全一致**，
/// 这是两侧唯一的契约，改一边必须改另一边。
class NativeMenuBridge {
  NativeMenuBridge._();

  static final NativeMenuBridge instance = NativeMenuBridge._();

  static const _channel = MethodChannel('jianjin/menu');

  /// 只有 Linux 有原生菜单；其余平台由各自方式提供（macOS 原生 NSMenu、
  /// Windows 窗口内菜单），不必建立通道。
  static bool get isSupported => Platform.isLinux;

  /// 原生菜单是否已就位。C 侧在标题栏挂上汉堡按钮后会通知过来；
  /// 在收到通知前保守地按「没有」处理，宁可短暂多显示一个按钮，
  /// 也不要出现一个菜单入口都没有的窗口。
  final ValueNotifier<bool> hasNativeMenu = ValueNotifier<bool>(false);

  AppMenuActions? _actions;
  Map<String, bool>? _lastEnabled;
  bool _installed = false;

  /// 把当前动作集同步给原生菜单。可安全地在每次 build 调用——
  /// 启用表没变化时不会产生通道往返。
  void sync(AppMenuActions actions) {
    if (!isSupported) return;
    _actions = actions;

    if (!_installed) {
      _channel.setMethodCallHandler(_onNativeCall);
      _installed = true;
    }

    final enabled = _enabledMap(actions);
    if (_mapEquals(enabled, _lastEnabled)) return;
    _lastEnabled = enabled;
    _channel.invokeMethod<void>('setEnabled', enabled);
  }

  /// 「关于」对话框由 GTK 原生绘制，但内容来自这里
  void setAbout({String? version, String? ffmpeg}) {
    if (!isSupported) return;
    _channel.invokeMethod<void>('setAbout', <String, String>{
      if (version != null) 'version': version,
      if (ffmpeg != null) 'ffmpeg': ffmpeg,
    });
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'nativeMenu') {
      hasNativeMenu.value = call.arguments as bool? ?? false;
      return null;
    }
    if (call.method != 'activate') return null;
    final id = call.arguments as String?;
    final a = _actions;
    if (id == null || a == null) return null;
    _dispatch(a, id)?.call();
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
        _ => null,
      };

  Map<String, bool> _enabledMap(AppMenuActions a) => <String, bool>{
        'open': true,
        'close': a.onCloseFile != null,
        'export': a.onExport != null,
        'undo': a.onUndo != null,
        'delete': a.onDeleteSelected != null,
        'clearAll': a.onClearAll != null,
        'markIn': a.onMarkIn != null,
        'markOut': a.onMarkOut != null,
        'playPause': a.onPlayPause != null,
        'faster': a.onFaster != null,
        'slower': a.onSlower != null,
        'resetRate': a.onResetRate != null,
        'back5': a.onBack5 != null,
        'forward5': a.onForward5 != null,
        'prevFrame': a.onPrevFrame != null,
        'nextFrame': a.onNextFrame != null,
      };

  static bool _mapEquals(Map<String, bool> a, Map<String, bool>? b) {
    if (b == null || a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
