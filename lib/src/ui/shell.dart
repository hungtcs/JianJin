import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/export_mode.dart';
import '../player/player_controller.dart';
import '../services/ffmpeg_service.dart';
import '../services/ffmpeg_locator.dart';
import '../services/reveal.dart';
import '../state/app_state.dart';
import 'about_dialog.dart';
import 'app_menu.dart';
import 'native_menu_bridge.dart';
import 'confirm_overwrite.dart';
import 'segment_list.dart';
import 'theme.dart';
import 'timeline/thumbnail_cache.dart';
import 'timeline/timeline_panel.dart';
import 'transport_bar.dart';
import 'video_pane.dart';
import 'window_menu.dart';
import 'widgets/button.dart';
import 'widgets/icons.dart' as ic;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _state = AppState();
  final _player = PlayerController();
  final _cache = ThumbnailCache();
  final _focus = FocusNode();

  bool _exporting = false;
  double _exportProgress = 0;
  String? _exportLabel;
  _ToastData? _toast;
  Timer? _toastTimer;

  /// 待用户确认的覆盖冲突。非 null 时弹框可见。
  _OverwritePrompt? _overwritePrompt;

  bool _aboutOpen = false;
  String? _ffmpegVersion;
  String? _version;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onChanged);
    _player.addListener(_onChanged);
    _probeFfmpeg();
    _loadVersion();
  }

  /// 启动时探一次 ffmpeg，结果显示在「关于」里。
  /// 找不到 ffmpeg 是这个应用最常见的故障原因，值得给个明确出口。
  Future<void> _probeFfmpeg() async {
    final v = await FfmpegLocator.probeVersion();
    if (!mounted) return;
    setState(() => _ffmpegVersion = v);
  }

  /// 版本来自 pubspec 注入的 bundle 信息，不是代码里的常量
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = info.version);
      NativeMenuBridge.instance.setAbout(version: info.version);
    } catch (_) {
      // 读不到就不显示版本，不影响其它功能
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _state.removeListener(_onChanged);
    _player.removeListener(_onChanged);
    _state.dispose();
    _player.dispose();
    _cache.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showToast(
    String msg, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _toastTimer?.cancel();
    setState(() => _toast = _ToastData(msg, actionLabel, onAction));
    _toastTimer = Timer(duration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // -------------------------------------------------------------- 打开/导出

  Future<void> _open() async {
    const group = XTypeGroup(
      label: '视频',
      extensions: <String>[
        'mp4',
        'mkv',
        'mov',
        'avi',
        'webm',
        'flv',
        'ts',
        'm2ts',
        'wmv',
        'mpg',
        'mpeg',
        'm4v',
        '3gp',
      ],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _loadPath(file.path);
  }

  Future<void> _loadPath(String path) async {
    _cache.clear();
    await _state.open(path);
    if (_state.phase == LoadPhase.failed) {
      _showToast('打不开：${_state.error}');
      return;
    }
    await _player.open(path);
  }

  Future<void> _closeFile() async {
    _cache.clear();
    _state.closeFile();
    await _player.close();
  }

  /// 弹出覆盖确认，返回用户选择；null 表示取消。
  Future<OverwritePolicy?> _askOverwrite(
    List<String> conflicts,
    String dir,
  ) {
    final completer = Completer<OverwritePolicy?>();
    setState(() {
      _overwritePrompt = _OverwritePrompt(
        conflicts: conflicts,
        outputDir: dir,
        completer: completer,
      );
    });
    return completer.future;
  }

  void _resolveOverwrite(OverwritePolicy? policy) {
    final prompt = _overwritePrompt;
    if (prompt == null) return;
    setState(() => _overwritePrompt = null);
    if (!prompt.completer.isCompleted) prompt.completer.complete(policy);
  }

  Future<void> _export() async {
    if (_state.segments.isEmpty || _exporting) return;

    final info = _state.info;
    if (info == null) return;

    final dir = await getDirectoryPath(
      confirmButtonText: '导出到此处',
      initialDirectory: p.dirname(info.path),
    );
    if (dir == null) return;

    // 导出前检查同名文件。此前是 ffmpeg -y 静默覆盖，
    // 会不声不响地毁掉上一次的导出结果。
    final conflicts = _state.conflictingOutputs(dir);
    var policy = OverwritePolicy.overwrite;
    if (conflicts.isNotEmpty) {
      final choice = await _askOverwrite(conflicts, dir);
      if (choice == null) return; // 用户取消
      policy = choice;
    }

    final total = _state.segments.length;
    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportLabel = '1/$total';
    });

    final errors = <String>[];
    var skipped = 0;
    try {
      await for (final ExportProgress e in _state.export(dir, policy: policy)) {
        if (e.skipped) skipped++;
        if (e.error != null) errors.add(e.error!);
        if (!mounted) return;
        setState(() {
          _exportProgress = e.overall;
          if (!e.done) {
            _exportLabel = '${(e.segmentIndex + 1).clamp(1, total)}/$total';
          }
        });
      }
    } catch (e) {
      errors.add('$e');
    }

    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportProgress = 0;
      _exportLabel = null;
    });

    if (errors.isEmpty) {
      final skipNote = skipped > 0 ? '，跳过 $skipped 个已存在' : '';
      _showToast(
        '已导出 ${total - skipped} 个片段 · ${_state.mode.label}$skipNote',
        actionLabel: '打开文件夹',
        onAction: () => Reveal.directory(dir),
        duration: const Duration(seconds: 10),
      );
    } else {
      _showToast(
        '${total - errors.length}/$total 成功，${errors.length} 个失败：${errors.first}',
        actionLabel: '打开文件夹',
        onAction: () => Reveal.directory(dir),
        duration: const Duration(seconds: 12),
      );
    }
  }

  // -------------------------------------------------------------- 键盘

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final keys = HardwareKeyboard.instance;
    final mod = keys.isMetaPressed || keys.isControlPressed;
    final shift = keys.isShiftPressed;
    final k = e.logicalKey;
    final pos = _player.position;

    // 带修饰键的先处理，避免和单键冲突
    if (mod) {
      if (k == LogicalKeyboardKey.keyO) {
        _open();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyZ) {
        _state.undo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyW) {
        if (_state.info != null) _closeFile();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyE) {
        _export();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.space) {
      _player.playPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyI) {
      _state.markIn(pos);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyO) {
      if (_state.pendingIn == null) {
        _showToast('先按 I 标入点');
      } else {
        _state.markOut(pos);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyL) {
      _player.faster();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyJ) {
      _player.slower();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyK) {
      _player.resetRate();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyX ||
        k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      _state.deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_overwritePrompt != null) {
        _resolveOverwrite(null);
      } else if (_aboutOpen) {
        setState(() => _aboutOpen = false);
      } else {
        _state.cancelPending();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _export();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _player.nudge(Duration(seconds: shift ? -30 : -5));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _player.nudge(Duration(seconds: shift ? 30 : 5));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.comma) {
      _player.nudge(
          -(_state.info?.frameDuration ?? const Duration(milliseconds: 40)));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.period) {
      _player.nudge(
          _state.info?.frameDuration ?? const Duration(milliseconds: 40));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final info = _state.info;
    final hasVideo = info != null && _state.phase == LoadPhase.ready;

    final menuActions = AppMenuActions(
      onOpen: _open,
      onAbout: () => setState(() => _aboutOpen = true),
      onCloseFile: hasVideo ? _closeFile : null,
      onExport: _state.segments.isNotEmpty && !_exporting ? _export : null,
      onUndo: _state.canUndo ? _state.undo : null,
      onDeleteSelected:
          _state.selectedId != null ? _state.deleteSelected : null,
      onClearAll: _state.segments.isNotEmpty ? _state.clearAll : null,
      onPlayPause: hasVideo ? _player.playPause : null,
      onFaster: hasVideo ? _player.faster : null,
      onSlower: hasVideo ? _player.slower : null,
      onResetRate: hasVideo ? _player.resetRate : null,
      onBack5:
          hasVideo ? () => _player.nudge(const Duration(seconds: -5)) : null,
      onForward5:
          hasVideo ? () => _player.nudge(const Duration(seconds: 5)) : null,
      onPrevFrame: hasVideo ? () => _player.nudge(-info.frameDuration) : null,
      onNextFrame: hasVideo ? () => _player.nudge(info.frameDuration) : null,
      onMarkIn: hasVideo ? () => _state.markIn(_player.position) : null,
      onMarkOut: hasVideo && _state.pendingIn != null
          ? () => _state.markOut(_player.position)
          : null,
      onCancelPending: _state.pendingIn != null ? _state.cancelPending : null,
    );

    NativeMenuBridge.instance.sync(menuActions);

    return AppMenu(
      actions: menuActions,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Container(
              color: AppColors.bg,
              child: Column(
                children: [
                  _TitleBar(
                    info: info,
                    keyframesLoading: _state.keyframesLoading,
                    onOpen: _open,
                    menuActions: menuActions,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: VideoPane(
                                  player: _player,
                                  hasVideo: hasVideo,
                                  onOpen: _open,
                                ),
                              ),
                              if (_toast != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 16,
                                  child: Center(child: _Toast(data: _toast!)),
                                ),
                            ],
                          ),
                        ),
                        SegmentList(
                          segments: _state.segments,
                          selectedId: _state.selectedId,
                          onSelect: _state.select,
                          onPlay: (s) => _player.playRange(s.start, s.end),
                          onDelete: _state.deleteAt,
                          onClearAll: _state.clearAll,
                          rangeOf: _state.rangeOf,
                        ),
                      ],
                    ),
                  ),
                  TransportBar(
                    player: _player,
                    segmentCount: _state.segments.length,
                    totalKept: _state.totalKept,
                    canUndo: _state.canUndo,
                    pendingIn: _state.pendingIn,
                    onMarkIn: () => _state.markIn(_player.position),
                    onMarkOut: () => _state.markOut(_player.position),
                    onUndo: _state.undo,
                          onExport: _export,
                    exporting: _exporting,
                    exportProgress: _exportProgress,
                    exportLabel: _exportLabel,
                    mode: _state.mode,
                    onModeChanged: (m) => _state.mode = m,
                    totalExported: _state.totalExported,
                  ),
                  TimelinePanel(
                    duration: _player.duration,
                    position: _player.position,
                    segments: _state.segments,
                    keyframes: info?.keyframes ?? const <Duration>[],
                    waveform: _state.waveform,
                    thumbnails: _state.thumbnails,
                    cache: _cache,
                    thumbnailsLoading: _state.thumbnailsLoading,
                    waveformLoading: _state.waveformLoading,
                    selectedId: _state.selectedId,
                    pendingIn: _state.pendingIn,
                    onScrubStart: _player.beginScrub,
                    onScrub: _player.scrubTo,
                    onScrubEnd: _player.endScrub,
                    onSelect: _state.select,
                    onResize: (id, st, e, commit) => _state.resizeSegment(id,
                        start: st, end: e, commit: commit),
                  ),
                ],
              ),
            ),
            if (_overwritePrompt != null)
              Positioned.fill(
                child: ConfirmOverwrite(
                  conflicts: _overwritePrompt!.conflicts,
                  total: _state.segments.length,
                  outputDir: _overwritePrompt!.outputDir,
                  onChoose: _resolveOverwrite,
                  onCancel: () => _resolveOverwrite(null),
                ),
              ),
            if (_aboutOpen)
              Positioned.fill(
                child: AboutPanel(
                  version: _version,
                  ffmpegVersion: _ffmpegVersion,
                  onClose: () => setState(() => _aboutOpen = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.info,
    required this.keyframesLoading,
    required this.onOpen,
    required this.menuActions,
  });

  final dynamic info;
  final bool keyframesLoading;
  final VoidCallback onOpen;
  final AppMenuActions menuActions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppMetrics.titleBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.padding),
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpen,
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: EdgeInsets.only(right: 10),
                child: ic.Icon(ic.AppIcon.folder,
                    size: 15, color: AppColors.textDim),
              ),
            ),
          ),
          if (info == null)
            const Text('未打开文件', style: AppText.dim)
          else ...[
            Text(p.basename(info.path as String), style: AppText.base),
            const SizedBox(width: 12),
            Text(
              '${info.width}×${info.height} · ${info.videoCodec} · '
              '${(info.frameRate as double).toStringAsFixed(2)}fps · '
              '${formatTime(info.duration as Duration)}',
              style: AppText.dim,
            ),
            const SizedBox(width: 12),
            if (keyframesLoading)
              const Text('正在扫描关键帧…', style: AppText.label)
            else if ((info.keyframes as List).isNotEmpty)
              Text('${(info.keyframes as List).length} 关键帧',
                  style: AppText.label),
          ],
          const Spacer(),
          // macOS 有原生 NSMenu；Linux 在 GNOME 下有标题栏原生菜单。
          // 只有确实没有原生入口时才显示窗口内的汉堡按钮。
          if (!Platform.isMacOS)
            ValueListenableBuilder<bool>(
              valueListenable: NativeMenuBridge.instance.hasNativeMenu,
              builder: (context, hasNative, _) => hasNative
                  ? const SizedBox.shrink()
                  : WindowMenuButton(actions: menuActions),
            ),
        ],
      ),
    );
  }
}

/// 一次待确认的覆盖冲突
class _OverwritePrompt {
  const _OverwritePrompt({
    required this.conflicts,
    required this.outputDir,
    required this.completer,
  });

  final List<String> conflicts;
  final String outputDir;
  final Completer<OverwritePolicy?> completer;
}

class _ToastData {
  const _ToastData(this.message, this.actionLabel, this.onAction);
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _Toast extends StatelessWidget {
  const _Toast({required this.data});
  final _ToastData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 9, 9),
      decoration: BoxDecoration(
        color: const Color(0xF21F1F22),
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(data.message, style: AppText.base),
          if (data.actionLabel != null) ...[
            const SizedBox(width: 12),
            AppButton(
              label: data.actionLabel!,
              icon: ic.AppIcon.folder,
              onPressed: data.onAction,
            ),
          ],
        ],
      ),
    );
  }
}
