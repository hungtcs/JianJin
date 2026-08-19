import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../player/player_controller.dart';
import 'theme.dart';

class VideoPane extends StatelessWidget {
  const VideoPane({
    super.key,
    required this.player,
    required this.hasVideo,
    required this.onOpen,
  });

  final PlayerController player;
  final bool hasVideo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0C0E),
      child: hasVideo
          ? Video(
              controller: player.videoController,
              // 播放器控件全部自绘在 transport 条上，这里只要画面
              controls: NoVideoControls,
              fill: const Color(0xFF0C0C0E),
            )
          : _EmptyState(onOpen: onOpen),
    );
  }
}

class _EmptyState extends StatefulWidget {
  const _EmptyState({required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hover ? AppColors.borderStrong : AppColors.border,
              ),
              color: _hover ? AppColors.panel : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  // 未 hover 时压暗，避免空状态下 logo 抢视觉
                  opacity: _hover ? 1.0 : 0.72,
                  child: Image.asset(
                    'assets/logo/logo_icon.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 16),
                Text('打开视频', style: AppText.base.copyWith(fontSize: 14)),
                const SizedBox(height: 5),
                const Text('拖入文件，或按 ⌘O', style: AppText.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
