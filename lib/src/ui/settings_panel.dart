import 'package:flutter/widgets.dart';

import '../models/export_mode.dart';
import '../settings.dart';
import 'theme.dart';
import 'widgets/button.dart';

/// 设置面板。改动即时生效并写盘，所以没有「保存」按钮。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onClose,
  });

  final AppSettings settings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: const Color(0x99000000)),
          ),
        ),
        Center(
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => Container(
              width: 460,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '设置',
                    style: AppText.base.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  const _SectionLabel('时间轴分析'),
                  _ToggleRow(
                    title: '缩略图',
                    subtitle: '打开文件后解码全部关键帧生成。素材很大时最耗时的一项，'
                        '关掉可立刻消除卡顿。',
                    value: settings.thumbnailsEnabled,
                    onChanged: (v) => settings.thumbnailsEnabled = v,
                  ),
                  _ToggleRow(
                    title: '音频波形',
                    subtitle: '需要解码整条音轨。用来一眼找出静音段。',
                    value: settings.waveformEnabled,
                    onChanged: (v) => settings.waveformEnabled = v,
                  ),

                  const SizedBox(height: 18),
                  const _SectionLabel('导出'),
                  _ChoiceRow(
                    title: '默认模式',
                    subtitle: settings.exportMode == ExportMode.lossless
                        ? '零重编码，画质不变；起点会对齐到关键帧'
                        : '边界与标记完全一致；较慢且有画质损失',
                    options: ExportMode.values.map((m) => m.label).toList(),
                    selected: settings.exportMode.index,
                    onSelected: (i) =>
                        settings.exportMode = ExportMode.values[i],
                  ),

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '改动即时生效并自动保存',
                        style: AppText.label
                            .copyWith(color: AppColors.textFaint),
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
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontSize: 10.5,
          color: AppColors.textFaint,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.base.copyWith(fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle, style: AppText.label.copyWith(height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppSwitch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.base.copyWith(fontSize: 13)),
              const SizedBox(height: 3),
              Text(subtitle, style: AppText.label.copyWith(height: 1.5)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        AppSegmented(
          options: options,
          selected: selected,
          onSelected: onSelected,
        ),
      ],
    );
  }
}
