import 'package:flutter/widgets.dart';

import '../models/export_mode.dart';
import '../player/player_controller.dart';
import 'theme.dart';
import 'widgets/button.dart';
import 'widgets/icons.dart' as ic;

class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.player,
    required this.segmentCount,
    required this.totalKept,
    required this.canUndo,
    required this.pendingIn,
    required this.onMarkIn,
    required this.onMarkOut,
    required this.onUndo,
    required this.onExport,
    required this.exporting,
    required this.exportProgress,
    required this.exportLabel,
    required this.mode,
    required this.onModeChanged,
    required this.totalExported,
  });

  final PlayerController player;
  final int segmentCount;
  final Duration totalKept;
  final bool canUndo;
  final Duration? pendingIn;

  final VoidCallback onMarkIn;
  final VoidCallback onMarkOut;
  final VoidCallback onUndo;
  final VoidCallback onExport;
  final bool exporting;
  final double exportProgress;

  /// 形如「2/5」，让用户知道批量导出到哪一个了
  final String? exportLabel;

  final ExportMode mode;
  final ValueChanged<ExportMode> onModeChanged;

  /// 实际会导出的总时长（可能大于标记总时长）
  final Duration totalExported;

  @override
  Widget build(BuildContext context) {
    final hasVideo = player.duration > Duration.zero;

    return Container(
      height: AppMetrics.transportHeight,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.padding),
      child: Row(
        children: [
          AppIconButton(
            icon: player.playing ? ic.AppIcon.pause : ic.AppIcon.play,
            onPressed: hasVideo ? player.playPause : null,
            size: 30,
            iconSize: 14,
          ),
          const SizedBox(width: AppMetrics.gap),

          // 时间码等宽，播放时数字不会左右抖动
          Text(formatTime(player.position, withMillis: true),
              style: AppText.mono),
          Text(' / ${formatTime(player.duration)}', style: AppText.monoDim),

          if (player.rate != 1.0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${player.rate.toStringAsFixed(player.rate % 1 == 0 ? 0 : 1)}x',
                style: AppText.label.copyWith(color: AppColors.accent),
              ),
            ),
          ],

          const SizedBox(width: 16),

          AppButton(
            label: '入点',
            icon: ic.AppIcon.markIn,
            shortcut: 'I',
            onPressed: hasVideo ? onMarkIn : null,
          ),
          const SizedBox(width: 6),
          AppButton(
            label: '出点',
            icon: ic.AppIcon.markOut,
            shortcut: 'O',
            onPressed: hasVideo && pendingIn != null ? onMarkOut : null,
          ),
          const SizedBox(width: 6),
          AppIconButton(
            icon: ic.AppIcon.undo,
            onPressed: canUndo ? onUndo : null,
            size: 28,
            iconSize: 14,
          ),

          const Spacer(),

          if (segmentCount > 0) ...[
            const Text('已选 ', style: AppText.dim),
            Text(formatTime(totalKept), style: AppText.mono),
            if (totalExported != totalKept) ...[
              const Text(' → ', style: AppText.monoDim),
              Text(
                formatTime(totalExported),
                style: AppText.mono.copyWith(color: AppColors.pending),
              ),
            ],
            const SizedBox(width: 12),
          ],
          if (!exporting) ...[
            _ModeToggle(mode: mode, onChanged: onModeChanged),
            const SizedBox(width: 8),
          ],

          if (exporting)
            SizedBox(
              width: 150,
              child: _ProgressBar(value: exportProgress, label: exportLabel),
            )
          else
            AppButton(
              label: segmentCount > 0 ? '导出 $segmentCount 个片段' : '导出',
              icon: ic.AppIcon.export,
              shortcut: '⏎',
              primary: true,
              onPressed: segmentCount > 0 ? onExport : null,
            ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, this.label});
  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label == null
              ? '导出中 ${(value * 100).toStringAsFixed(0)}%'
              : '导出中 $label · ${(value * 100).toStringAsFixed(0)}%',
          style: AppText.label,
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// 导出模式切换。放在导出按钮旁边，因为它直接决定产物时长准不准。
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final ExportMode mode;
  final ValueChanged<ExportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in ExportMode.values)
            _ModeChip(
              label: m.label,
              active: m == mode,
              onTap: () => onChanged(m),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatefulWidget {
  const _ModeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ModeChip> createState() => _ModeChipState();
}

class _ModeChipState extends State<_ModeChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.accent
                : (_hover ? AppColors.panel : null),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.label,
            style: AppText.label.copyWith(
              fontSize: 11,
              color: widget.active
                  ? const Color(0xFF0B1220)
                  : AppColors.textDim,
              fontWeight:
                  widget.active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
