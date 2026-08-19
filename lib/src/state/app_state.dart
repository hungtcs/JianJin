import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/export_mode.dart';
import '../models/segment.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/ffprobe_service.dart';

enum LoadPhase { idle, probing, ready, failed }

class AppState extends ChangeNotifier {
  AppState({
    FfprobeService? probe,
    FfmpegService? ffmpeg,
  })  : _probe = probe ?? const FfprobeService(),
        _ffmpeg = ffmpeg ?? const FfmpegService();

  final FfprobeService _probe;
  final FfmpegService _ffmpeg;

  VideoInfo? _info;
  VideoInfo? get info => _info;

  LoadPhase _phase = LoadPhase.idle;
  LoadPhase get phase => _phase;

  String? _error;
  String? get error => _error;

  final List<Segment> _segments = [];
  List<Segment> get segments => List.unmodifiable(_segments);

  /// 按了 I 还没按 O 时的临时入点
  Duration? _pendingIn;
  Duration? get pendingIn => _pendingIn;

  String? _selectedId;
  String? get selectedId => _selectedId;
  Segment? get selected {
    if (_selectedId == null) return null;
    for (final s in _segments) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  List<double> _waveform = const [];
  List<double> get waveform => _waveform;

  List<String> _thumbnails = const [];
  List<String> get thumbnails => _thumbnails;

  bool _keyframesLoading = false;
  bool get keyframesLoading => _keyframesLoading;

  bool _thumbnailsLoading = false;
  bool get thumbnailsLoading => _thumbnailsLoading;

  bool _waveformLoading = false;
  bool get waveformLoading => _waveformLoading;

  /// 是否还有后台分析任务在跑
  bool get analyzing =>
      _keyframesLoading || _thumbnailsLoading || _waveformLoading;

  ExportMode _mode = ExportMode.lossless;
  ExportMode get mode => _mode;
  set mode(ExportMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  /// 某片段在当前模式下**实际会导出**的区间。
  /// 界面一律按这个显示，避免出现「标 5 秒导出 10 秒」这种沉默的偏差。
  ExportRange? rangeOf(Segment s) {
    final i = _info;
    if (i == null) return null;
    return ExportRange.of(i, s.start, s.end, _mode);
  }

  /// 所有片段实际导出的总时长
  Duration get totalExported {
    final i = _info;
    if (i == null) return Duration.zero;
    return _segments.fold(
      Duration.zero,
      (a, s) => a + ExportRange.of(i, s.start, s.end, _mode).duration,
    );
  }

  /// 撤销栈。挑片段是高频、易错的操作，撤销必须便宜。
  final List<List<Segment>> _undo = [];
  bool get canUndo => _undo.isNotEmpty;

  int _idSeq = 0;
  String _nextId() => 's${++_idSeq}';

  StreamSubscription<List<Duration>>? _kfSub;

  Duration get totalKept => _segments.fold(
        Duration.zero,
        (a, s) => a + s.duration,
      );

  // ---------------------------------------------------------------- 打开文件

  Future<void> open(String path) async {
    _kfSub?.cancel();
    _phase = LoadPhase.probing;
    _error = null;
    _segments.clear();
    _undo.clear();
    _pendingIn = null;
    _selectedId = null;
    _waveform = const [];
    _thumbnails = const [];
    _thumbnailsLoading = false;
    _waveformLoading = false;
    _keyframesLoading = false;
    notifyListeners();

    try {
      _info = await _probe.probe(path);
      _phase = LoadPhase.ready;
      notifyListeners();
    } catch (e) {
      _error = '$e';
      _phase = LoadPhase.failed;
      notifyListeners();
      return;
    }

    // 关键帧、波形、缩略图都在后台跑，各自就绪各自刷新，不阻塞播放
    _loadKeyframes(path);
    _loadWaveform(path);
    _loadThumbnails();
  }

  void _loadKeyframes(String path) {
    _keyframesLoading = true;
    notifyListeners();
    _kfSub = _probe.keyframes(path).listen(
      (list) {
        if (_info?.path != path) return;
        _info = _info!.copyWith(keyframes: list);
        notifyListeners();
      },
      onDone: () {
        _keyframesLoading = false;
        notifyListeners();
      },
      onError: (_) {
        _keyframesLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _loadWaveform(String path) async {
    _waveformLoading = true;
    notifyListeners();
    final w = await _ffmpeg.waveform(path);
    if (_info?.path != path) return;
    _waveform = w;
    _waveformLoading = false;
    notifyListeners();
  }

  Future<void> _loadThumbnails() async {
    final info = _info;
    if (info == null) return;
    _thumbnailsLoading = true;
    notifyListeners();
    final dir = p.join(
      Directory.systemTemp.path,
      'jianjin_thumbs',
      p.basenameWithoutExtension(info.path).hashCode.toRadixString(16),
    );
    final files = await _ffmpeg.thumbnails(info: info, cacheDir: dir);
    if (_info?.path != info.path) return;
    _thumbnails = files;
    _thumbnailsLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 打点

  void _pushUndo() {
    _undo.add(List.of(_segments));
    if (_undo.length > 100) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    _segments
      ..clear()
      ..addAll(prev);
    if (selected == null) _selectedId = null;
    notifyListeners();
  }

  void markIn(Duration at) {
    _pendingIn = at;
    notifyListeners();
  }

  /// 标出点。若没有入点，什么也不做（而不是报错打断流程）。
  void markOut(Duration at) {
    final start = _pendingIn;
    if (start == null) return;
    _pendingIn = null;
    _addSegment(start, at);
  }

  void _addSegment(Duration rawStart, Duration rawEnd) {
    var start = rawStart;
    var end = rawEnd;
    if (end < start) {
      final t = start;
      start = end;
      end = t;
    }

    // 显式打点不加留白：用户按 I/O 标的是哪就是哪，可预测优先。
    if (start < Duration.zero) start = Duration.zero;
    final dur = _info?.duration;
    if (dur != null && end > dur) end = dur;
    if (end <= start) return;

    _pushUndo();
    final seg = Segment(id: _nextId(), start: start, end: end);
    _segments.add(seg);
    _normalize();
    _selectedId = _segments
        .firstWhere(
          (s) => s.contains(start) || s.overlaps(seg),
          orElse: () => seg,
        )
        .id;
    notifyListeners();
  }

  void _normalize() {
    final merged = mergeSegments(_segments, tolerance: Duration.zero);
    _segments
      ..clear()
      ..addAll(merged);
  }

  void cancelPending() {
    if (_pendingIn == null) return;
    _pendingIn = null;
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void deleteSelected() {
    if (_selectedId == null) return;
    _pushUndo();
    _segments.removeWhere((s) => s.id == _selectedId);
    _selectedId = null;
    notifyListeners();
  }

  void deleteAt(String id) {
    _pushUndo();
    _segments.removeWhere((s) => s.id == id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// 拖动片段边缘。[commit] 为 false 时不入撤销栈（拖动过程中的连续更新）。
  void resizeSegment(
    String id, {
    Duration? start,
    Duration? end,
    bool commit = true,
  }) {
    final i = _segments.indexWhere((s) => s.id == id);
    if (i < 0) return;
    if (commit) _pushUndo();

    final cur = _segments[i];
    var ns = start ?? cur.start;
    var ne = end ?? cur.end;
    if (ns < Duration.zero) ns = Duration.zero;
    final dur = _info?.duration;
    if (dur != null && ne > dur) ne = dur;
    if (ne - ns < const Duration(milliseconds: 200)) return;

    _segments[i] = cur.copyWith(start: ns, end: ne);
    if (commit) _normalize();
    notifyListeners();
  }

  /// 关闭当前文件，回到空状态。
  /// 后台的关键帧扫描要一并取消，否则它还会往一个已关闭的文件上写结果。
  void closeFile() {
    _kfSub?.cancel();
    _kfSub = null;
    _info = null;
    _phase = LoadPhase.idle;
    _error = null;
    _segments.clear();
    _undo.clear();
    _pendingIn = null;
    _selectedId = null;
    _waveform = const [];
    _thumbnails = const [];
    _keyframesLoading = false;
    _thumbnailsLoading = false;
    _waveformLoading = false;
    notifyListeners();
  }

  void clearAll() {
    if (_segments.isEmpty) return;
    _pushUndo();
    _segments.clear();
    _selectedId = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 导出

  /// 本次导出会写入、且目标已存在的文件（用于导出前提示覆盖）
  List<String> conflictingOutputs(String outputDir) {
    final info = _info;
    if (info == null || _segments.isEmpty) return const [];
    return FfmpegService.plannedOutputs(
      info: info,
      segmentCount: _segments.length,
      outputDir: outputDir,
    ).where((f) => File(f).existsSync()).toList();
  }

  Stream<ExportProgress> export(
    String outputDir, {
    OverwritePolicy policy = OverwritePolicy.overwrite,
  }) {
    final info = _info;
    if (info == null || _segments.isEmpty) {
      return const Stream<ExportProgress>.empty();
    }
    return _ffmpeg.exportAll(
      info: info,
      segments: List.of(_segments),
      outputDir: outputDir,
      mode: _mode,
      policy: policy,
    );
  }

  @override
  void dispose() {
    _kfSub?.cancel();
    super.dispose();
  }
}
