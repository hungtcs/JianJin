import 'package:flutter/widgets.dart';

import 'app_menu.dart';
import 'theme.dart';
import 'widgets/button.dart';
import 'widgets/icons.dart' as ic;

/// 窗口内菜单（汉堡按钮 + 弹出面板）。
///
/// GNOME 自 3.32 起移除了应用菜单，HIG 规范是标题栏右侧的「主菜单」——
/// 也就是这个汉堡。Flutter 的 PlatformMenuBar 只在 macOS 落到原生 NSMenu，
/// Linux/Windows 上什么也不做，因此这两个平台由这里补齐。
///
/// 与 [AppMenu] 共用同一份 [AppMenuActions]：一套动作，两种呈现。
class WindowMenuButton extends StatefulWidget {
  const WindowMenuButton({super.key, required this.actions});

  final AppMenuActions actions;

  @override
  State<WindowMenuButton> createState() => _WindowMenuButtonState();
}

class _WindowMenuButtonState extends State<WindowMenuButton> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  void _close() {
    if (_portal.isShowing) _portal.hide();
  }

  /// 菜单项按功能分组。播放与标记也列出来，因为这里同时承担快捷键的发现职责——
  /// 用户不必先读文档才知道有哪些操作。
  List<_Entry> _entries() {
    final a = widget.actions;
    return [
      _Item('打开…', '⌘O', a.onOpen),
      _Item('关闭文件', '⌘W', a.onCloseFile),
      const _Sep(),
      _Item('导出片段…', '⌘E', a.onExport),
      const _Sep(),
      _Item('撤销', '⌘Z', a.onUndo),
      _Item('删除选中片段', 'X', a.onDeleteSelected),
      _Item('清空全部片段', null, a.onClearAll),
      const _Sep(),
      _Item('标入点', 'I', a.onMarkIn),
      _Item('标出点', 'O', a.onMarkOut),
      _Item('回补 ${a.retroSeconds} 秒', 'A', a.onRetro),
      const _Sep(),
      _Item('播放 / 暂停', 'Space', a.onPlayPause),
      _Item('加速', 'L', a.onFaster),
      _Item('减速', 'J', a.onSlower),
      _Item('恢复 1x', 'K', a.onResetRate),
      const _Sep(),
      _Item('关于剪金', null, a.onAbout),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          return Stack(
            children: [
              // 点击别处关闭
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 4),
                child: _MenuPanel(
                  entries: _entries(),
                  onDismiss: _close,
                ),
              ),
            ],
          );
        },
        child: AppIconButton(
          icon: ic.AppIcon.menu,
          size: 26,
          iconSize: 14,
          onPressed: _portal.toggle,
        ),
      ),
    );
  }
}

sealed class _Entry {
  const _Entry();
}

class _Sep extends _Entry {
  const _Sep();
}

class _Item extends _Entry {
  const _Item(this.label, this.shortcut, this.onTap);
  final String label;
  final String? shortcut;

  /// null 表示当前不可用，菜单项置灰
  final VoidCallback? onTap;
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.entries, required this.onDismiss});

  final List<_Entry> entries;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Container(
        width: 232,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.panelAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in entries)
              switch (e) {
                _Sep() => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: SizedBox(
                      height: 1,
                      child: ColoredBox(color: AppColors.border),
                    ),
                  ),
                _Item() => _MenuRow(item: e, onDismiss: onDismiss),
              },
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onDismiss});

  final _Item item;
  final VoidCallback onDismiss;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled
            ? () {
                widget.onDismiss();
                widget.item.onTap!();
              }
            : null,
        child: Container(
          height: 27,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover && enabled ? AppColors.accent : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.item.label,
                  style: AppText.base.copyWith(
                    fontSize: 12.5,
                    color: !enabled
                        ? AppColors.textFaint
                        : (_hover ? const Color(0xFF0B1220) : AppColors.text),
                  ),
                ),
              ),
              if (widget.item.shortcut != null)
                Text(
                  widget.item.shortcut!,
                  style: AppText.label.copyWith(
                    fontSize: 10.5,
                    color: !enabled
                        ? AppColors.textFaint
                        : (_hover
                            ? const Color(0x990B1220)
                            : AppColors.textFaint),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
