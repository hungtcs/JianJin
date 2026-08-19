import 'package:flutter_test/flutter_test.dart';
import 'package:jianjin/src/ui/timeline/timeline_view_controller.dart';

/// 播放跟随与手动平移曾经每帧互相覆盖，表现为「播放中滚动会抖动」。
/// 这里把仲裁规则逐条钉死。
TimelineViewController make({
  Duration duration = const Duration(minutes: 10),
  double width = 1000,
  double zoom = 4, // 视野 = 总时长 / zoom
}) {
  final v = TimelineViewController()
    ..setWidth(width)
    ..reset(duration);
  // reset 后是整片铺满，再放大到 1/zoom 视野
  v.zoomTo(v.pxPerMs * zoom, 0);
  v.resumeFollow();
  return v;
}

void main() {
  group('视野与边界', () {
    test('reset 后整片铺满且处于跟随态', () {
      final v = TimelineViewController()
        ..setWidth(1000)
        ..reset(const Duration(minutes: 10));
      expect(v.fitsEntirely, isTrue);
      expect(v.following, isTrue);
      expect(v.viewStartMs, 0);
    });

    test('整片可见时平移无效，不会把视图推出边界', () {
      final v = TimelineViewController()
        ..setWidth(1000)
        ..reset(const Duration(minutes: 10));
      v.panByPixels(500);
      expect(v.viewStartMs, 0);
    });

    test('缩放不会小于「整片铺满」', () {
      final v = make();
      for (var i = 0; i < 50; i++) {
        v.zoomAt(0.5, 500);
      }
      expect(v.fitsEntirely, isTrue);
      expect(v.viewStartMs, 0);
    });

    test('平移被夹在 [0, 总时长-视野] 内', () {
      final v = make();
      v.panByPixels(999999);
      expect(v.viewEndMs, closeTo(v.duration.inMilliseconds.toDouble(), 1));
      v.panByPixels(-999999);
      expect(v.viewStartMs, 0);
    });
  });

  group('跟随 / 手动的仲裁（抖动的根因）', () {
    test('手动平移后立即交出跟随权', () {
      final v = make();
      expect(v.following, isTrue);
      v.panByPixels(100);
      expect(v.following, isFalse);
    });

    test('缩放同样交出跟随权', () {
      final v = make();
      v.zoomAt(1.2, 500);
      expect(v.following, isFalse);
    });

    test('交出后播放推进绝不移动视图——这是不抖的关键', () {
      final v = make();
      // 把视口挪到片尾，播放头在片头推进，全程处于视野之外
      v.panToStart(v.duration.inMilliseconds * 0.8);
      final start = v.viewStartMs;
      expect(v.following, isFalse);

      for (var s = 0; s < 60; s++) {
        v.followPlayhead(Duration(seconds: s));
        expect(v.viewStartMs, start, reason: '第 $s 秒时视图发生了移动');
      }
      expect(v.following, isFalse, reason: '播放头始终在视野外，不应收回控制权');
    });

    test('播放头自己走进视野时无声接管，且视图不跳', () {
      final v = make();
      v.panByPixels(300);
      final start = v.viewStartMs;
      expect(v.following, isFalse);

      final inside = Duration(
        milliseconds: (v.viewStartMs + v.visibleMs * 0.5).round(),
      );
      v.followPlayhead(inside);

      expect(v.following, isTrue, reason: '播放追上视野应收回控制权');
      expect(v.viewStartMs, start, reason: '接管的那一刻视图不应移动');
    });

    test('跟随中播放头未越过触发线时视图不动（避免每帧微调）', () {
      final v = make();
      final start = v.viewStartMs;
      final justInside = Duration(
        milliseconds: (v.viewStartMs + v.visibleMs * 0.5).round(),
      );
      v.followPlayhead(justInside);
      expect(v.viewStartMs, start, reason: '未到触发线不该滑动');
    });

    test('跟随中播放头逼近右缘时整屏前推', () {
      final v = make();
      final start = v.viewStartMs;
      final nearEdge = Duration(
        milliseconds: (v.viewStartMs + v.visibleMs * 0.95).round(),
      );
      v.followPlayhead(nearEdge);
      expect(v.viewStartMs, greaterThan(start));
      expect(v.following, isTrue);
    });

    test('resumeFollow 可显式收回控制权', () {
      final v = make();
      v.panByPixels(200);
      expect(v.following, isFalse);
      v.resumeFollow();
      expect(v.following, isTrue);
    });
  });

  group('全局条拖动视口', () {
    test('panToStart 直接设定视口起点', () {
      final v = make();
      final total = v.duration.inMilliseconds.toDouble();
      v.panToStart(total * 0.5);
      expect(v.viewStartMs, closeTo(total * 0.5, 1));
    });

    test('panToStart 越界时被夹住', () {
      final v = make();
      v.panToStart(1e12);
      expect(v.viewEndMs, closeTo(v.duration.inMilliseconds.toDouble(), 1));
    });

    test('centerOn 把目标时间放到视野中央', () {
      final v = make();
      const target = Duration(minutes: 5);
      v.centerOn(target);
      final center = v.viewStartMs + v.visibleMs / 2;
      expect(center, closeTo(target.inMilliseconds.toDouble(), 1));
    });
  });

  group('拖动视口边缘（setViewRange）', () {
    test('设定范围后视野与之吻合', () {
      final v = make();
      v.setViewRange(60000, 180000);
      expect(v.viewStartMs, closeTo(60000, 1));
      expect(v.viewEndMs, closeTo(180000, 1));
    });

    test('起止传反了也能正确归一', () {
      final v = make();
      v.setViewRange(180000, 60000);
      expect(v.viewStartMs, closeTo(60000, 1));
      expect(v.viewEndMs, closeTo(180000, 1));
    });

    test('视野不会被拖到小于最大缩放允许的宽度', () {
      final v = make();
      v.setViewRange(60000, 60001);
      expect(v.viewEndMs - v.viewStartMs, greaterThan(1.0));
      expect(v.pxPerMs, lessThanOrEqualTo(0.5));
    });

    test('超出片尾时向左收敛而不是越界', () {
      final v = make();
      final total = v.duration.inMilliseconds.toDouble();
      v.setViewRange(total - 500, total + 100000);
      expect(v.viewEndMs, closeTo(total, 1));
      expect(v.viewStartMs, greaterThanOrEqualTo(0));
    });

    test('拖边缘同样交出跟随权', () {
      final v = make();
      expect(v.following, isTrue);
      v.setViewRange(60000, 180000);
      expect(v.following, isFalse);
    });
  });

  group('坐标换算', () {
    test('xOf 与 timeAt 互为逆运算', () {
      final v = make();
      v.panToStart(60000);
      const t = Duration(seconds: 75);
      expect(v.timeAt(v.xOf(t)).inMilliseconds, closeTo(75000, 2));
    });

    test('timeAt 结果被夹在 [0, 总时长]', () {
      final v = make();
      expect(v.timeAt(-99999), Duration.zero);
      expect(v.timeAt(99999), v.duration);
    });
  });
}
