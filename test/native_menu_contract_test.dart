import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Linux 原生菜单横跨 C 与 Dart，动作名是两侧唯一的契约。
/// 这个契约被破坏过——菜单项引用了一个并不存在的动作，表现为永久变灰，
/// 而两边单独看都「没问题」。靠注释提醒不够，这里用测试锁住。
String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    fail('找不到 $path；本测试需要从仓库根目录运行');
  }
  return f.readAsStringSync();
}

void main() {
  late Set<String> registered;
  late Set<String> referenced;
  late Set<String> dispatched;

  setUpAll(() {
    final c = _read('linux/runner/my_application.cc');

    // C 侧注册的动作：kMenuActions 数组
    final arr = RegExp(r'kMenuActions\[\]\s*=\s*\{(.*?)\};', dotAll: true)
        .firstMatch(c);
    expect(arr, isNotNull, reason: '未能在 C 源码中找到 kMenuActions');
    registered = RegExp(r'"(\w+)"')
        .allMatches(arr!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    // 菜单项引用的动作：g_menu_append(..., "win.xxx")
    referenced = RegExp(r'"win\.(\w+)"')
        .allMatches(c)
        .map((m) => m.group(1)!)
        .toSet();

    // Dart 侧能分发的动作：_dispatch 的 switch 分支
    final dart = _read('lib/src/ui/native_menu_bridge.dart');
    final sw = RegExp(r'_dispatch\(.*?\)\s*=>\s*switch \(id\) \{(.*?)\n      \};',
            dotAll: true)
        .firstMatch(dart);
    expect(sw, isNotNull, reason: '未能在 bridge 中找到 _dispatch 的 switch');
    dispatched = RegExp(r"'(\w+)' =>")
        .allMatches(sw!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  });

  test('菜单项引用的动作必须都已在 C 侧注册', () {
    final missing = referenced.difference(registered);
    expect(missing, isEmpty,
        reason: '这些动作被菜单引用却未注册，菜单项会永久变灰：$missing');
  });

  test('C 侧注册的动作必须都能被 Dart 分发', () {
    final missing = registered.difference(dispatched);
    expect(missing, isEmpty,
        reason: '这些动作点了会没有反应，因为 Dart 侧没有对应分支：$missing');
  });

  test('Dart 侧不应分发 C 侧并不存在的动作', () {
    final extra = dispatched.difference(registered);
    expect(extra, isEmpty, reason: '这些分支永远不会被触发：$extra');
  });

  test('契约非空——避免正则失配导致三条断言全部空过', () {
    expect(registered.length, greaterThan(3));
    expect(referenced.length, greaterThan(3));
    expect(dispatched.length, greaterThan(3));
  });
}
