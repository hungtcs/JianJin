import 'package:flutter/widgets.dart';

import '../../models/segment.dart';
import '../theme.dart';
import 'detail_timeline.dart';
import 'overview_bar.dart';
import 'thumbnail_cache.dart';
import 'timeline_view_controller.dart';

/// 双层时间轴面板：上「细节」放大轨，下「全片」地图。
///
/// 全片条放在下面：它离视频画面更远，而细节轨是打点时真正盯着的东西，
/// 让后者贴近画面可以缩短视线往返。
///
/// 两层共享同一个 [TimelineViewController]，因此全局条能直接拖动细节轨的视口，
/// 且「播放跟随」与「用户手动平移」只有一个裁决点，不会互相打架。
///
/// 每一层都用 [SizedBox] 显式限高再交给 [Row]。这一步不能省：
/// Row 在 Column 里拿到的是无界高度，`CrossAxisAlignment.stretch`
/// 会把无限高度传给子节点，直接触发 BoxConstraints 断言。
class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.duration,
    required this.position,
    required this.segments,
    required this.keyframes,
    required this.waveform,
    required this.thumbnails,
    required this.cache,
    this.thumbnailsLoading = false,
    this.waveformLoading = false,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onSelect,
    required this.onResize,
    this.selectedId,
    this.pendingIn,
  });

  final Duration duration;
  final Duration position;
  final List<Segment> segments;
  final List<Duration> keyframes;
  final List<double> waveform;
  final List<String> thumbnails;
  final ThumbnailCache cache;
  final bool thumbnailsLoading;
  final bool waveformLoading;

  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrub;
  final ValueChanged<Duration> onScrubEnd;
  final ValueChanged<String?> onSelect;
  final void Function(String id, Duration? start, Duration? end, bool commit)
      onResize;

  final String? selectedId;
  final Duration? pendingIn;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final _view = TimelineViewController();

  @override
  void initState() {
    super.initState();
    _view.reset(widget.duration);
  }

  @override
  void didUpdateWidget(TimelinePanel old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) {
      _view.reset(widget.duration);
    } else if (old.position != widget.position) {
      _view.followPlayhead(widget.position);
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: AppMetrics.detailHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TrackLabel(title: '细节', subtitle: '可缩放'),
              Expanded(
                child: DetailTimeline(
                  view: _view,
                  position: widget.position,
                  segments: widget.segments,
                  keyframes: widget.keyframes,
                  waveform: widget.waveform,
                  thumbnails: widget.thumbnails,
                  cache: widget.cache,
                  thumbnailsLoading: widget.thumbnailsLoading,
                  waveformLoading: widget.waveformLoading,
                  selectedId: widget.selectedId,
                  pendingIn: widget.pendingIn,
                  onScrubStart: widget.onScrubStart,
                  onScrub: widget.onScrub,
                  onScrubEnd: widget.onScrubEnd,
                  onSelect: widget.onSelect,
                  onResize: widget.onResize,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: AppMetrics.overviewHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 不再放「跟随」按钮：脱离跟随时直接点全片条上的播放游标
              // 即可回到播放头，那个游标本来就在，不必再加一个控件。
              const TrackLabel(title: '全片'),
              Expanded(
                child: OverviewBar(
                  view: _view,
                  position: widget.position,
                  segments: widget.segments,
                  waveform: widget.waveform,
                  selectedId: widget.selectedId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 时间轴左侧标签栏。两条轨紧挨在一起容易被误认为是两条音轨，
/// 标出层级后「上面是整片地图、下面是放大细节」就不用猜了。
class TrackLabel extends StatelessWidget {
  const TrackLabel({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 10),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label.copyWith(fontSize: 10.5)),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppText.label
                  .copyWith(fontSize: 9, color: AppColors.textFaint),
            ),
        ],
      ),
    );
  }
}
