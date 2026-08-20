import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/ui/app_menu.dart';

/// macOS 菜单栏的接线契约。
///
/// 这里锁的是一类**编译期完全看不出来**的错误：菜单项忘了接回调、或者用了
/// `PlatformProvidedMenuItem` 把动作交给系统，于是应用内置的界面永远打不开。
/// macOS 上没有窗口内菜单兜底（那是 Linux/Windows 的路径），所以菜单一漏，
/// 功能就等于不存在。
///
/// 回归背景：「关于」曾用 PlatformProvidedMenuItemType.about，点开的是 AppKit
/// 的标准关于面板而不是应用内置的那个；「设置」则整个没进菜单。

void walk(List<PlatformMenuItem> items, void Function(PlatformMenuItem) visit) {
  for (final item in items) {
    if (item is PlatformMenu) {
      visit(item);
      walk(item.menus, visit);
    } else if (item is PlatformMenuItemGroup) {
      walk(item.members, visit);
    } else {
      visit(item);
    }
  }
}

/// 每个回调都把自己的名字记进 fired，用来断言「菜单确实用上了这个动作」
({AppMenuActions actions, Set<String> fired}) recordingActions() {
  final fired = <String>{};
  VoidCallback tag(String name) => () => fired.add(name);
  return (
    actions: AppMenuActions(
      onOpen: tag('onOpen'),
      onAbout: tag('onAbout'),
      onSettings: tag('onSettings'),
      onCloseFile: tag('onCloseFile'),
      onExport: tag('onExport'),
      onUndo: tag('onUndo'),
      onDeleteSelected: tag('onDeleteSelected'),
      onClearAll: tag('onClearAll'),
      onPlayPause: tag('onPlayPause'),
      onFaster: tag('onFaster'),
      onSlower: tag('onSlower'),
      onResetRate: tag('onResetRate'),
      onBack5: tag('onBack5'),
      onForward5: tag('onForward5'),
      onPrevFrame: tag('onPrevFrame'),
      onNextFrame: tag('onNextFrame'),
      onMarkIn: tag('onMarkIn'),
      onMarkOut: tag('onMarkOut'),
      onCancelPending: tag('onCancelPending'),
    ),
    fired: fired,
  );
}

void main() {
  test('每一个动作都能从菜单里触发到——漏接线的唯一防线', () {
    final r = recordingActions();
    walk(macMenus(r.actions), (item) => item.onSelected?.call());

    expect(
      r.fired,
      containsAll(<String>[
        'onOpen', 'onAbout', 'onSettings', 'onCloseFile', 'onExport',
        'onUndo', 'onDeleteSelected', 'onClearAll',
        'onPlayPause', 'onFaster', 'onSlower', 'onResetRate',
        'onBack5', 'onForward5', 'onPrevFrame', 'onNextFrame',
        'onMarkIn', 'onMarkOut', 'onCancelPending',
      ]),
      reason: '菜单里少了哪一项，这里就会指名道姓地报出来',
    );
  });

  test('「关于」走应用内置对话框，不是系统的标准关于面板', () {
    final r = recordingActions();
    final menus = macMenus(r.actions);

    final provided = <PlatformProvidedMenuItemType>[];
    walk(menus, (item) {
      if (item is PlatformProvidedMenuItem) provided.add(item.type);
    });
    expect(
      provided,
      isNot(contains(PlatformProvidedMenuItemType.about)),
      reason: 'PlatformProvidedMenuItemType.about 映射到 AppKit 的标准面板，'
          '根本不会调用 onAbout',
    );

    PlatformMenuItem? about;
    walk(menus, (item) {
      if (item.label == '关于剪金') about = item;
    });
    expect(about, isNotNull);
    about!.onSelected!();
    expect(r.fired, contains('onAbout'));
  });

  test('「设置…」在应用菜单里，快捷键是 ⌘,', () {
    final r = recordingActions();
    PlatformMenuItem? settings;
    walk(macMenus(r.actions), (item) {
      if (item.label == '设置…') settings = item;
    });

    expect(settings, isNotNull, reason: 'macOS 上没有窗口内菜单可以兜底');
    expect(
      settings!.shortcut,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true),
      reason: '⌘, 是 macOS 打开设置的约定俗成快捷键',
    );
    settings!.onSelected!();
    expect(r.fired, contains('onSettings'));
  });

  test('顶层菜单顺序符合 macOS 习惯', () {
    final r = recordingActions();
    final top = macMenus(r.actions)
        .whereType<PlatformMenu>()
        .map((m) => m.label)
        .toList();
    expect(top, ['剪金', '文件', '编辑', '播放', '标记', '窗口']);
  });
}
