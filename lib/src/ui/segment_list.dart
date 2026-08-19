import 'package:flutter/widgets.dart';

import '../models/export_mode.dart';
import '../models/segment.dart';
import 'theme.dart';
import 'widgets/icons.dart' as ic;

class SegmentList extends StatelessWidget {
  const SegmentList({
    super.key,
    required this.segments,
    required this.selectedId,
    required this.onSelect,
    required this.onPlay,
    required this.onDelete,
    required this.onClearAll,
    required this.rangeOf,
  });

  final List<Segment> segments;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// 点击片段即试看：跳到起点播放，到终点自动暂停
  final ValueChanged<Segment> onPlay;
  final ValueChanged<String> onDelete;
  final VoidCallback onClearAll;

  /// 该片段实际会导出的区间。界面按这个显示，不按标记区间。
  final ExportRange? Function(Segment) rangeOf;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppMetrics.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Text('片段', style: AppText.label),
                const SizedBox(width: 6),
                Text('${segments.length}',
                    style: AppText.label.copyWith(color: AppColors.textFaint)),
                const Spacer(),
                if (segments.isNotEmpty)
                  _TextAction(label: '清空', onTap: onClearAll),
              ],
            ),
          ),
          Expanded(
            child: segments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '按 I 标入点\n按 O 标出点\n\n或按 A 回补前 ${AppMetrics.retroSeconds} 秒',
                        textAlign: TextAlign.center,
                        style: AppText.dim.copyWith(
                          color: AppColors.textFaint,
                          height: 1.7,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    // 桌面滚动不该有 iOS 的回弹过冲
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: segments.length,
                    itemBuilder: (context, i) {
                      final s = segments[i];
                      return _SegmentRow(
                        index: i + 1,
                        segment: s,
                        range: rangeOf(s),
                        selected: s.id == selectedId,
                        onTap: () {
                          onSelect(s.id);
                          onPlay(s);
                        },
                        onDelete: () => onDelete(s.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: AppText.label.copyWith(
            color: _hover ? AppColors.danger : AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _SegmentRow extends StatefulWidget {
  const _SegmentRow({
    required this.index,
    required this.segment,
    required this.range,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final Segment segment;
  final ExportRange? range;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SegmentRow> createState() => _SegmentRowState();
}

class _SegmentRowState extends State<_SegmentRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    final accent =
        widget.selected ? AppColors.segmentSelected : AppColors.segment;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 7, 7),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accentDim
                : (_hover ? AppColors.panelAlt : null),
            border: Border(
              bottom: const BorderSide(color: AppColors.border, width: 0.5),
              left: BorderSide(
                color: widget.selected ? accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text('${widget.index}',
                    style: AppText.label.copyWith(color: AppColors.textFaint)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatTime(s.start)} → ${formatTime(s.end)}',
                      style: AppText.mono.copyWith(fontSize: 11.5),
                    ),
                    const SizedBox(height: 2),
                    _DurationLine(
                      segment: s,
                      range: widget.range,
                      accent: accent,
                    ),
                  ],
                ),
              ),
              if (_hover)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: ic.Icon(ic.AppIcon.delete,
                        size: 12, color: AppColors.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 时长行。当实际导出区间与标记区间不一致时，把差额明确画出来——
/// 「标 5 秒导出 10 秒」这种偏差必须可见，不能让用户导出后才发现。
class _DurationLine extends StatelessWidget {
  const _DurationLine({
    required this.segment,
    required this.range,
    required this.accent,
  });

  final Segment segment;
  final ExportRange? range;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final r = range;
    if (r == null || !r.hasDrift) {
      return Text(
        formatTime(segment.duration),
        style: AppText.monoDim.copyWith(fontSize: 10.5, color: accent),
      );
    }

    return Row(
      children: [
        Text(
          formatTime(segment.duration),
          style: AppText.monoDim.copyWith(
            fontSize: 10.5,
            color: AppColors.textFaint,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          formatTime(r.duration),
          style: AppText.monoDim.copyWith(fontSize: 10.5, color: accent),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.pending.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            '+${formatTime(r.drift)}',
            style: AppText.label.copyWith(
              fontSize: 9.5,
              color: AppColors.pending,
            ),
          ),
        ),
      ],
    );
  }
}
