import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 缩略图按需解码 + LRU 缓存。
/// 长视频有几百张缩略图，全解码进内存会很浪费，只保留视口附近的。
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache({this.capacity = 160});

  final int capacity;

  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  bool _disposed = false;

  ui.Image? get(String path) {
    final img = _images.remove(path);
    if (img != null) {
      _images[path] = img; // 触碰即置于末尾（LRU）
      return img;
    }
    _schedule(path);
    return null;
  }

  void _schedule(String path) {
    if (_loading.contains(path) || _disposed) return;
    _loading.add(path);
    _decode(path);
  }

  Future<void> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (_disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _put(path, frame.image);
      notifyListeners();
    } catch (_) {
      // 解码失败就当没有这张图，不影响时间轴其余部分
    } finally {
      _loading.remove(path);
    }
  }

  void _put(String path, ui.Image img) {
    _images[path] = img;
    while (_images.length > capacity) {
      final oldest = _images.keys.first;
      _images.remove(oldest)?.dispose();
    }
  }

  void clear() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
