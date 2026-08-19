import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'icons.dart' as ic;

/// 桌面按钮：hover 高亮 + 按下反馈，没有 Material 的水波纹。
/// 触点尺寸按桌面调（28px 高），不是 Material 的 48dp 触屏规范。
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.shortcut,
  });

  final String label;
  final ic.AppIcon? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  /// 显示在标签右侧的快捷键提示，键盘优先的工具应该处处提醒快捷键
  final String? shortcut;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    Color bg;
    Color fg;
    Color? border;

    if (!enabled) {
      bg = AppColors.panelAlt;
      fg = AppColors.textFaint;
      border = AppColors.border;
    } else if (widget.primary) {
      bg = _down
          ? const Color(0xFF3A82D9)
          : (_hover ? const Color(0xFF5AA8FF) : AppColors.accent);
      fg = const Color(0xFF0B1220);
      border = null;
    } else if (widget.danger) {
      bg = _down
          ? const Color(0x40FF5A5A)
          : (_hover ? const Color(0x26FF5A5A) : AppColors.panelAlt);
      fg = AppColors.danger;
      border =
          _hover ? AppColors.danger.withValues(alpha: 0.5) : AppColors.border;
    } else {
      bg = _down
          ? const Color(0xFF303036)
          : (_hover ? AppColors.panelAlt : AppColors.panel);
      fg = AppColors.text;
      border = _hover ? AppColors.borderStrong : AppColors.border;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppMetrics.radius),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                ic.Icon(widget.icon!, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: AppText.base.copyWith(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight:
                      widget.primary ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (widget.shortcut != null) ...[
                const SizedBox(width: 7),
                Text(
                  widget.shortcut!,
                  style: AppText.label.copyWith(
                    color: fg.withValues(alpha: 0.55),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 纯图标按钮，用于 transport 区
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 30,
    this.iconSize = 15,
    this.tooltip,
  });

  final ic.AppIcon icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;

  // 图标按钮没有文字，不给提示就只能靠猜。Flutter 的 Tooltip 在 Material 里，
  // 这里用 OverlayPortal 自行实现一个。
  final _tip = OverlayPortalController();
  final _link = LayerLink();
  Timer? _tipTimer;

  void _scheduleTip() {
    if (widget.tooltip == null || widget.onPressed == null) return;
    _tipTimer?.cancel();
    // 延迟出现，避免鼠标划过一排按钮时提示乱闪
    _tipTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _hover) _tip.show();
    });
  }

  void _hideTip() {
    _tipTimer?.cancel();
    if (_tip.isShowing) _tip.hide();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    Widget button = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _hover && enabled ? AppColors.panelAlt : null,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
      ),
      child: Center(
        child: ic.Icon(
          widget.icon,
          size: widget.iconSize,
          color: enabled
              ? (_hover ? AppColors.text : AppColors.textDim)
              : AppColors.textFaint,
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _tip,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -6),
            child: _Tooltip(message: widget.tooltip!),
          ),
          child: button,
        ),
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        setState(() => _hover = true);
        _scheduleTip();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _hideTip();
      },
      child: GestureDetector(
        onTap: () {
          _hideTip();
          widget.onPressed?.call();
        },
        child: button,
      ),
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xF20E0E10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Text(
          message,
          style: AppText.label.copyWith(fontSize: 11, color: AppColors.text),
        ),
      ),
    );
  }
}
