import 'package:flutter/widgets.dart';

import '../app_info.dart';
import '../services/reveal.dart';
import 'theme.dart';
import 'widgets/button.dart';
import 'widgets/icons.dart' as ic;

/// 关于弹框。自绘，不用 Material 的 Dialog。
class AboutPanel extends StatelessWidget {
  const AboutPanel({
    super.key,
    required this.onClose,
    this.version,
    this.ffmpegVersion,
  });

  final VoidCallback onClose;

  /// 运行时从 bundle 读到的版本，null 表示还没读到
  final String? version;

  /// 启动时探测到的 ffmpeg 版本，null 表示没找到——
  /// 这是最常见的故障原因，放在这里方便排查
  final String? ffmpegVersion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 点击遮罩关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: const Color(0x99000000)),
          ),
        ),
        Center(
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Image.asset(
                      'assets/logo/logo_full.png',
                      width: 200,
                      height: 62,
                      filterQuality: FilterQuality.medium,
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        version == null ? '' : 'v$version',
                        style: AppText.monoDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(AppInfo.tagline, style: AppText.dim),
                const SizedBox(height: 18),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                const _Row(
                  label: '解码 / 播放',
                  value: 'libmpv (media_kit)',
                ),
                const SizedBox(height: 7),
                _Row(
                  label: '切割 / 分析',
                  value: ffmpegVersion ?? '未找到 ffmpeg',
                  warn: ffmpegVersion == null,
                ),
                const SizedBox(height: 7),
                const _Row(label: '界面', value: 'Flutter'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    AppButton(
                      label: 'GitHub',
                      icon: ic.AppIcon.export,
                      onPressed: () => Reveal.url(AppInfo.repository),
                    ),
                    const Spacer(),
                    AppButton(
                      label: '关闭',
                      primary: true,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: AppText.label),
        ),
        Expanded(
          child: Text(
            value,
            style: AppText.dim.copyWith(
              color: warn ? AppColors.danger : AppColors.textDim,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}
