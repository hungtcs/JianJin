import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// media_kit(libmpv) 的薄封装。
/// 只暴露这个应用需要的能力：精确定位、变速、逐帧。
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _player = Player();
    _video = VideoController(_player);
    _bind();
  }

  late final Player _player;
  late final VideoController _video;
  final _subs = <StreamSubscription<dynamic>>[];

  VideoController get videoController => _video;
  Player get raw => _player;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _rate = 1.0;
  bool _seeking = false;

  /// 播放到此处自动暂停（点击片段列表试看时用）。
  /// 任何手动跳转/播放都会清掉它——用户既然自己操作了，
  /// 就不该再被一个看不见的终点打断。
  Duration? _stopAt;

  /// 静音前的音量，取消静音时恢复到这个值而不是固定的 100，
  /// 否则用户自己调过的音量会被抹掉
  double _volumeBeforeMute = 100;
  bool _muted = false;

  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get muted => _muted;
  double get rate => _rate;

  void _bind() {
    _subs.add(_player.stream.position.listen((v) {
      // 拖动 playhead 期间忽略回报，否则会和用户输入打架
      if (_seeking) return;
      if (v != _position) {
        _position = v;
        notifyListeners();
      }
      final stop = _stopAt;
      if (stop != null && v >= stop) {
        _stopAt = null;
        // 先暂停再对齐到终点：位置回报有间隔，直接停会略微过头
        _player.pause();
        _player.seek(stop);
        _position = stop;
        notifyListeners();
      }
    }));
    _subs.add(_player.stream.duration.listen((v) {
      if (v != _duration) {
        _duration = v;
        notifyListeners();
      }
    }));
    _subs.add(_player.stream.playing.listen((v) {
      if (v != _playing) {
        _playing = v;
        notifyListeners();
      }
    }));
    _subs.add(_player.stream.rate.listen((v) {
      if (v != _rate) {
        _rate = v;
        notifyListeners();
      }
    }));
  }

  Future<void> open(String path) async {
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    await _player.open(Media(path), play: false);
  }

  /// 关闭当前媒体，回到空状态
  Future<void> close() async {
    _stopAt = null;
    await _player.stop();
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _rate = 1.0;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (_muted) {
      _muted = false;
      notifyListeners();
      await _player.setVolume(_volumeBeforeMute);
    } else {
      _volumeBeforeMute = _player.state.volume;
      _muted = true;
      notifyListeners();
      await _player.setVolume(0);
    }
  }

  Future<void> playPause() {
    _stopAt = null;
    return _playing ? _player.pause() : _player.play();
  }

  Future<void> pause() {
    _stopAt = null;
    return _player.pause();
  }

  /// 从 [start] 播到 [end] 自动暂停。点击片段列表试看该片段。
  Future<void> playRange(Duration start, Duration end) async {
    await seek(start); // seek 会清掉 _stopAt，所以必须在其后再设
    _stopAt = end;
    await _player.play();
  }

  Future<void> seek(Duration to) async {
    _stopAt = null;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && to > _duration ? _duration : to);
    _position = clamped;
    notifyListeners();
    await _player.seek(clamped);
  }

  Future<void> nudge(Duration delta) => seek(_position + delta);

  /// 拖动 playhead 期间调用，抑制播放器的位置回报
  void beginScrub() => _seeking = true;

  Future<void> endScrub(Duration to) async {
    _seeking = false;
    await seek(to);
  }

  void scrubTo(Duration to) {
    if (!_seeking) return;
    _stopAt = null;
    _position = to;
    notifyListeners();
    _player.seek(to);
  }

  /// J/L 的变速梯度。L 连按加速，J 连按倒放加速。
  static const rateSteps = <double>[1, 2, 4, 8, 16];

  Future<void> faster() async {
    final i = rateSteps.indexWhere((r) => r > _rate + 0.01);
    await setRate(i == -1 ? rateSteps.last : rateSteps[i]);
    if (!_playing) await _player.play();
  }

  Future<void> slower() async {
    final below = rateSteps.where((r) => r < _rate - 0.01).toList();
    await setRate(below.isEmpty ? rateSteps.first : below.last);
  }

  Future<void> setRate(double r) async {
    _rate = r;
    notifyListeners();
    await _player.setRate(r);
  }

  Future<void> resetRate() => setRate(1.0);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
