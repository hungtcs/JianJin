import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../services/ffmpeg_service.dart';
import 'theme.dart';
import 'widgets/button.dart';

/// 导出目标已存在时的确认弹框。
///
/// 给的是三种处置而不只是「覆盖 / 取消」：覆盖会毁掉上一次的成果，
/// 取消又让用户无路可走，跳过与改名才是多数时候真正想要的。
class ConfirmOverwrite extends StatelessWidget {
  const ConfirmOverwrite({
    super.key,
    required this.conflicts,
    required this.total,
    required this.outputDir,
    required this.onChoose,
    required this.onCancel,
  });

  /// 已存在、将被影响的目标文件
  final List<String> conflicts;

  /// 本次要导出的片段总数
  final int total;

  final String outputDir;
  final ValueChanged<OverwritePolicy> onChoose;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    const maxList = 6;
    final shown = conflicts.take(maxList).toList();
    final rest = conflicts.length - shown.length;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onCancel,
            child: Container(color: const Color(0x99000000)),
          ),
        ),
        Center(
          child: Container(
            width: 460,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '目标位置已有同名文件',
                  style: AppText.base.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '共 $total 个片段，其中 ${conflicts.length} 个的目标文件已存在于 '
                  '${p.basename(outputDir)}/',
                  style: AppText.dim,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(AppMetrics.radius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            p.basename(f),
                            style: AppText.monoDim.copyWith(fontSize: 11),
                          ),
                        ),
                      if (rest > 0)
                        Text(
                          '…还有 $rest 个',
                          style: AppText.label
                              .copyWith(color: AppColors.textFaint),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    AppButton(label: '取消', onPressed: onCancel),
                    const Spacer(),
                    AppButton(
                      label: '跳过已存在',
                      onPressed: () => onChoose(OverwritePolicy.skip),
                    ),
                    const SizedBox(width: 6),
                    AppButton(
                      label: '自动改名',
                      onPressed: () => onChoose(OverwritePolicy.rename),
                    ),
                    const SizedBox(width: 6),
                    AppButton(
                      label: '覆盖',
                      danger: true,
                      onPressed: () => onChoose(OverwritePolicy.overwrite),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '自动改名会保留原文件，新文件加序号后缀（如 name-2.mp4）',
                  style: AppText.label.copyWith(color: AppColors.textFaint),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
