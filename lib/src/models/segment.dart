import 'package:flutter/foundation.dart';

/// 片段来源。为静音检测/镜头检测预留：它们产出「提议」，
/// 走同一套审核交互，用户确认后转为 [SegmentOrigin.manual]。
enum SegmentOrigin { manual, silenceGap, sceneCut }

@immutable
class Segment {
  const Segment({
    required this.id,
    required this.start,
    required this.end,
    this.label,
    this.origin = SegmentOrigin.manual,
  });

  final String id;
  final Duration start;
  final Duration end;
  final String? label;
  final SegmentOrigin origin;

  Duration get duration => end - start;

  bool contains(Duration t) => t >= start && t <= end;

  bool overlaps(Segment other) => start < other.end && other.start < end;

  Segment copyWith({
    Duration? start,
    Duration? end,
    String? label,
    SegmentOrigin? origin,
  }) {
    return Segment(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      label: label ?? this.label,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        if (label != null) 'label': label,
        'origin': origin.name,
      };

  static Segment fromJson(Map<String, dynamic> j) => Segment(
        id: j['id'] as String,
        start: Duration(milliseconds: j['startMs'] as int),
        end: Duration(milliseconds: j['endMs'] as int),
        label: j['label'] as String?,
        origin: SegmentOrigin.values.firstWhere(
          (e) => e.name == j['origin'],
          orElse: () => SegmentOrigin.manual,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is Segment &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.label == label &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(id, start, end, label, origin);
}

/// 合并重叠/相邻片段。标重叠了不该报错，直接并成一段，减少心智负担。
List<Segment> mergeSegments(
  List<Segment> input, {
  Duration tolerance = Duration.zero,
}) {
  if (input.length < 2) return List.of(input);

  final sorted = List.of(input)..sort((a, b) => a.start.compareTo(b.start));
  final out = <Segment>[sorted.first];

  for (final seg in sorted.skip(1)) {
    final last = out.last;
    if (seg.start - last.end <= tolerance) {
      out[out.length - 1] =
          last.copyWith(end: seg.end > last.end ? seg.end : last.end);
    } else {
      out.add(seg);
    }
  }
  return out;
}
