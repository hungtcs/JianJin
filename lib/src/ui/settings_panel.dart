import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/export_mode.dart';
import '../services/ffmpeg_locator.dart';
import '../settings.dart';
import 'theme.dart';
import 'widgets/button.dart';

/// 设置面板。改动即时生效并写盘，所以没有「保存」按钮。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onClose,
    this.probe,
  });

  final AppSettings settings;
  final VoidCallback onClose;

  /// 测试用：替换掉真实的版本探测，免得渲染测试去起 ffmpeg 子进程
  @visibleForTesting
  final VersionProbe? probe;

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
        // 加上外部程序一节后面板已经不算矮，小窗口下必须能滚，
        // 否则直接是渲染溢出。见 test/settings_panel_layout_test.dart
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ListenableBuilder(
              listenable: settings,
              // 窄窗口下要能收窄而不是横向溢出，所以是 maxWidth 而非固定宽度
              builder: (context, _) => Container(
                constraints: const BoxConstraints(maxWidth: 460),
                width: double.infinity,
                // 左右内边距**不在这里**：滚动条由 ScrollBehavior 加在
                // SingleChildScrollView 外面，容器一旦有左右内边距，滚动条就被
                // 挤进内边距里侧，离面板边缘 24px 悬在半空。改由各行自己缩进，
                // 让滚动视口铺满面板宽度。
                padding: const EdgeInsets.only(top: 20, bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '设置',
                        style: AppText.base.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 标题与底部按钮固定，中间内容滚动。
                    // 右侧留 6px 给滚动条，内容再缩进 18px，两边合计都是 24。
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ScrollConfiguration(
                          behavior: const _PanelScrollBehavior(),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(left: 24, right: 18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _SectionLabel('时间轴分析'),
                                _ToggleRow(
                                  title: '缩略图',
                                  subtitle: '打开文件后解码全部关键帧生成。素材很大时最耗时的一项，'
                                      '关掉可立刻消除卡顿。',
                                  value: settings.thumbnailsEnabled,
                                  onChanged: (v) =>
                                      settings.thumbnailsEnabled = v,
                                ),
                                _ToggleRow(
                                  title: '音频波形',
                                  subtitle: '需要解码整条音轨。用来一眼找出静音段。',
                                  value: settings.waveformEnabled,
                                  onChanged: (v) =>
                                      settings.waveformEnabled = v,
                                ),
                                const SizedBox(height: 18),
                                const _SectionLabel('导出'),
                                _ChoiceRow(
                                  title: '默认模式',
                                  subtitle:
                                      settings.exportMode == ExportMode.lossless
                                          ? '零重编码，画质不变；起点会对齐到关键帧'
                                          : '边界与标记完全一致；较慢且有画质损失',
                                  options: ExportMode.values
                                      .map((m) => m.label)
                                      .toList(),
                                  selected: settings.exportMode.index,
                                  onSelected: (i) => settings.exportMode =
                                      ExportMode.values[i],
                                ),
                                const SizedBox(height: 18),
                                ExternalToolsSection(
                                  settings: settings,
                                  probe: probe,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 面板内的滚动条外观。默认的 [ScrollBehavior] 在桌面平台会套一层灰色
/// [RawScrollbar]，在这个全自绘的界面里是唯一一处「别人的样式」。
/// 只覆盖 buildScrollbar，其余行为（拖拽设备、overscroll）保持默认。
class _PanelScrollBehavior extends ScrollBehavior {
  const _PanelScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return RawScrollbar(
      controller: details.controller,
      thumbColor: AppColors.textFaint,
      radius: const Radius.circular(3),
      thickness: 6,
      child: child,
    );
  }
}

/// 外部二进制（ffmpeg / ffprobe）的路径设置。
///
/// 放进设置界面的理由：自动查找链再长也覆盖不到所有机器（解压版、多版本共存、
/// 装在自定义前缀下）。这里是用户最后的自救出口，所以它必须**如实显示当前
/// 到底会调用哪个文件**，而不只是提供一个输入框。
/// 探测一个可执行文件的版本首行，跑不起来返回 null
typedef VersionProbe = Future<String?> Function(String exe);

class ExternalToolsSection extends StatefulWidget {
  const ExternalToolsSection({
    super.key,
    required this.settings,
    this.probe,
  });

  final AppSettings settings;

  /// 测试用：见 [SettingsPanel.probe]
  @visibleForTesting
  final VersionProbe? probe;

  @override
  State<ExternalToolsSection> createState() => _ExternalToolsSectionState();
}

class _ExternalToolsSectionState extends State<ExternalToolsSection> {
  VersionProbe get _probeVersion => widget.probe ?? FfmpegLocator.versionOf;

  BinaryStatus? _ffmpeg;
  BinaryStatus? _ffprobe;
  String? _ffmpegVersion;
  String? _ffprobeVersion;
  bool _probing = false;

  /// 手选失败的原因，选中后立刻显示在对应行下方
  String? _ffmpegError;
  String? _ffprobeError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _probing = true);
    // 自己应用一次设置，不依赖 main.dart 的监听先跑：这段代码是路径设置的
    // 唯一入口，让它自洽比让它依赖调用顺序更可靠。setOverrides 是幂等的。
    FfmpegLocator.setOverrides(
      ffmpeg: widget.settings.ffmpegPath,
      ffprobe: widget.settings.ffprobePath,
    );
    // 用户可能刚在应用外装好 ffmpeg，必须丢掉启动时缓存的「没找到」
    FfmpegLocator.invalidate();
    final mpeg = FfmpegLocator.ffmpegStatus;
    final probe = FfmpegLocator.ffprobeStatus;
    final vm = await _probeVersion(mpeg.resolved);
    final vp = await _probeVersion(probe.resolved);
    if (!mounted) return;
    setState(() {
      _ffmpeg = mpeg;
      _ffprobe = probe;
      _ffmpegVersion = vm;
      _ffprobeVersion = vp;
      _probing = false;
    });
  }

  /// 选一个可执行文件。**先验证能不能跑再保存**——保存一个跑不起来的路径
  /// 等于把应用锁死在坏状态，而用户在设置界面看不出哪一步错了。
  Future<void> _pick({required bool isFfmpeg}) async {
    final file = await openFile();
    if (file == null) return;
    final path = file.path;
    final version = await _probeVersion(path);
    if (!mounted) return;

    if (version == null) {
      setState(() {
        final msg = '这个文件跑不起来（${p.basename(path)} -version 失败），未保存';
        if (isFfmpeg) {
          _ffmpegError = msg;
        } else {
          _ffprobeError = msg;
        }
      });
      return;
    }

    setState(() {
      _ffmpegError = null;
      _ffprobeError = null;
    });

    if (isFfmpeg) {
      widget.settings.ffmpegPath = path;
      // ffprobe 几乎总在 ffmpeg 旁边。用户手动下载解压的那份尤其如此，
      // 而它所在的目录恰恰是自动查找覆盖不到的——顺手补上省一次操作。
      if (widget.settings.ffprobePath == null) {
        final sibling = p.join(p.dirname(path), _probeNameFor(path));
        if (await _probeVersion(sibling) != null) {
          widget.settings.ffprobePath = sibling;
        }
      }
    } else {
      widget.settings.ffprobePath = path;
    }
    await _refresh();
  }

  /// 按选中的 ffmpeg 推 ffprobe 的文件名，保留原扩展名（Windows 是 .exe）
  static String _probeNameFor(String ffmpegPath) {
    final ext = p.extension(ffmpegPath);
    return 'ffprobe$ext';
  }

  Future<void> _clear({required bool isFfmpeg}) async {
    setState(() {
      _ffmpegError = null;
      _ffprobeError = null;
    });
    if (isFfmpeg) {
      widget.settings.ffmpegPath = null;
    } else {
      widget.settings.ffprobePath = null;
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(child: _SectionLabel('外部程序')),
            _MiniButton(
              label: _probing ? '检测中…' : '重新检测',
              onPressed: _probing ? null : _refresh,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '切割与分析依赖 ffmpeg / ffprobe，未安装时无法打开和导出文件'
            '（播放不受影响，它走内置解码器）。留空由程序自动查找，'
            '装在非常规位置时可以在这里手动指定。',
            style: AppText.label.copyWith(height: 1.5),
          ),
        ),
        _BinaryRow(
          name: 'ffmpeg',
          status: _ffmpeg,
          version: _ffmpegVersion,
          error: _ffmpegError,
          onPick: () => _pick(isFfmpeg: true),
          onClear: widget.settings.ffmpegPath == null
              ? null
              : () => _clear(isFfmpeg: true),
        ),
        const SizedBox(height: 8),
        _BinaryRow(
          name: 'ffprobe',
          status: _ffprobe,
          version: _ffprobeVersion,
          error: _ffprobeError,
          onPick: () => _pick(isFfmpeg: false),
          onClear: widget.settings.ffprobePath == null
              ? null
              : () => _clear(isFfmpeg: false),
        ),
      ],
    );
  }
}

/// 一行：名称 + 来源徽标 + 实际路径 + 版本，右侧是「选择/清除」。
class _BinaryRow extends StatelessWidget {
  const _BinaryRow({
    required this.name,
    required this.status,
    required this.version,
    required this.error,
    required this.onPick,
    required this.onClear,
  });

  final String name;
  final BinaryStatus? status;
  final String? version;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final ok = version != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        border: Border.all(
          color: s == null || ok ? AppColors.border : AppColors.danger,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: AppText.base.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 7),
                        if (s != null) _SourceBadge(status: s),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      s?.resolved ?? '检测中…',
                      style: AppText.monoDim.copyWith(
                        fontSize: 11,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MiniButton(label: '选择…', onPressed: onPick),
                  if (onClear != null) ...[
                    const SizedBox(height: 6),
                    _MiniButton(label: '清除', onPressed: onClear),
                  ],
                ],
              ),
            ],
          ),
          if (s != null) ...[
            const SizedBox(height: 6),
            Text(
              ok ? version! : '无法运行，切割与分析会失败',
              style: AppText.label.copyWith(
                fontSize: 10.5,
                height: 1.35,
                color: ok ? AppColors.textFaint : AppColors.danger,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (s != null && s.customStale) ...[
            const SizedBox(height: 5),
            Text(
              '指定的 ${s.custom} 已不存在，暂时回退到自动查找',
              style: AppText.label.copyWith(
                  fontSize: 10.5, height: 1.35, color: AppColors.pending),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 5),
            Text(
              error!,
              style: AppText.label.copyWith(
                  fontSize: 10.5, height: 1.35, color: AppColors.danger),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.status});

  final BinaryStatus status;

  @override
  Widget build(BuildContext context) {
    final custom = status.fromCustom;
    final color = custom ? AppColors.accent : AppColors.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: custom ? AppColors.accentDim : const Color(0x00000000),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: custom ? 0.0 : 0.5)),
      ),
      child: Text(
        custom ? '自定义' : '自动查找',
        style: AppText.label.copyWith(fontSize: 9.5, color: color),
      ),
    );
  }
}

/// 比 AppButton 小一号的次要按钮。设置面板里一行要塞两个，
/// 用标准按钮会把行撑得很高。
class _MiniButton extends StatefulWidget {
  const _MiniButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_MiniButton> createState() => _MiniButtonState();
}

class _MiniButtonState extends State<_MiniButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hover && enabled ? AppColors.border : AppColors.panel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Text(
            widget.label,
            style: AppText.label.copyWith(
              fontSize: 11,
              color: enabled ? AppColors.text : AppColors.textFaint,
            ),
          ),
        ),
      ),
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
