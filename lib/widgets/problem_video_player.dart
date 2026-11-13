import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Unified H.264 MP4 animation player for problems backed by legacy AVI clips.
class ProblemVideoPlayer extends StatefulWidget {
  const ProblemVideoPlayer({
    super.key,
    required this.assetPath,
    required this.sourceName,
  });

  final String assetPath;
  final String sourceName;

  @override
  State<ProblemVideoPlayer> createState() => _ProblemVideoPlayerState();
}

class _ProblemVideoPlayerState extends State<ProblemVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = true;
  bool _looping = true;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant ProblemVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _disposeController();
      _initController();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initController() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      // Linux video backend plug-in can be added separately without blocking Windows/Android builds.
      setState(() {
        _loading = false;
        _error = '当前 Linux 原生视频后端尚未启用（计划在 Linux 专属构建阶段接入）。';
      });
      return;
    }

    final ctrl = VideoPlayerController.asset(widget.assetPath);
    _controller = ctrl;
    ctrl.addListener(_onPlayerUpdate);
    try {
      await ctrl.initialize();
      await ctrl.setLooping(_looping);
      await ctrl.setPlaybackSpeed(_speed);
      await ctrl.play();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _disposeController() {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      ctrl.removeListener(_onPlayerUpdate);
      unawaited(ctrl.dispose());
    }
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  String _fmtDuration(Duration d) {
    final totalSec = d.inSeconds;
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载三维 / 投影演示动画...'),
          ],
        ),
      );
    }

    final ctrl = _controller;
    if (_error != null || ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded, size: 42, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('视频初始化失败：${_error ?? '未知错误'}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _initController,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试加载'),
              ),
            ],
          ),
        ),
      );
    }

    final val = ctrl.value;
    final durMs = val.duration.inMilliseconds.clamp(1, 1 << 30);
    final posMs = val.position.inMilliseconds.clamp(0, durMs);

    return Container(
      color: const Color(0xFF101318),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: val.aspectRatio > 0 ? val.aspectRatio : 4 / 3,
                child: GestureDetector(
                  onTap: () => val.isPlaying ? ctrl.pause() : ctrl.play(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(ctrl),
                      if (!val.isPlaying)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF191E26),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: val.isPlaying ? '暂停' : '播放',
                  icon: Icon(
                    val.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => val.isPlaying ? ctrl.pause() : ctrl.play(),
                ),
                Text(
                  '${_fmtDuration(val.position)} / ${_fmtDuration(val.duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: posMs.toDouble(),
                    min: 0,
                    max: durMs.toDouble(),
                    onChanged: (v) => ctrl.seekTo(Duration(milliseconds: v.round())),
                  ),
                ),
                IconButton(
                  tooltip: _looping ? '循环播放：开' : '循环播放：关',
                  icon: Icon(
                    Icons.repeat_rounded,
                    color: _looping ? Colors.lightBlueAccent : Colors.white54,
                  ),
                  onPressed: () async {
                    final next = !_looping;
                    await ctrl.setLooping(next);
                    if (mounted) setState(() => _looping = next);
                  },
                ),
                PopupMenuButton<double>(
                  tooltip: '倍速',
                  initialValue: _speed,
                  onSelected: (v) async {
                    await ctrl.setPlaybackSpeed(v);
                    if (mounted) setState(() => _speed = v);
                  },
                  itemBuilder: (_) => const [0.5, 0.75, 1.0, 1.5, 2.0]
                      .map((s) => PopupMenuItem(value: s, child: Text('${s}x')))
                      .toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_speed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
