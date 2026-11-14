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

/// Immutable snapshot of the [VideoPlayerValue] fields that drive the widget
/// tree (everything except the per-frame playback position). The player
/// listener rebuilds only when one of these fields actually changes, so the
/// position stream no longer triggers a whole-tree [setState] every frame.
class _PlayerSnapshot {
  const _PlayerSnapshot({
    this.initialized = false,
    this.playing = false,
    this.buffering = false,
    this.looping = false,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.aspectRatio = 0,
    this.errorText = '',
  });

  final bool initialized;
  final bool playing;
  final bool buffering;
  final bool looping;
  final Duration duration;
  final Size size;
  final double aspectRatio;
  final String errorText;

  bool differsFrom(_PlayerSnapshot other) =>
      initialized != other.initialized ||
      playing != other.playing ||
      buffering != other.buffering ||
      looping != other.looping ||
      duration != other.duration ||
      size != other.size ||
      aspectRatio != other.aspectRatio ||
      errorText != other.errorText;
}

class _ProblemVideoPlayerState extends State<ProblemVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _loading = true;
  bool _looping = true;
  double _speed = 1.0;

  /// 状态快照：listener 仅在这些字段变化时才整树 setState。
  _PlayerSnapshot _snap = const _PlayerSnapshot();

  /// 播放进度走独立 notifier：由 listener 直接更新、不触发整树重建，
  /// 进度条与时间文本通过 ValueListenableBuilder 局部消费。
  final ValueNotifier<Duration> _position = ValueNotifier<Duration>(Duration.zero);

  /// 拖动进度条期间为 true：listener 暂停写入 notifier，避免拇指回跳。
  bool _seeking = false;

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
    // 子树（含 ValueListenableBuilder）先于父 State 卸载，此刻已解除订阅，
    // 可以安全释放进度 notifier。
    _position.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    _disposeController();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _snap = const _PlayerSnapshot();
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
    } catch (e) {
      if (!mounted || _controller != ctrl) return;
      setState(() {
        _loading = false;
        _error = e;
      });
      return;
    }
    if (!mounted || _controller != ctrl) return;
    setState(() => _loading = false);
  }

  void _disposeController() {
    final ctrl = _controller;
    _controller = null;
    _seeking = false;
    if (ctrl != null) {
      ctrl.removeListener(_onPlayerUpdate);
      unawaited(ctrl.dispose());
    }
    // 切换视频时重置进度。注意这里不能 dispose notifier：树中的
    // ValueListenableBuilder 仍订阅着它，提前 dispose 会在其更新/卸载时
    // 触发 ChangeNotifier 的 debug 断言；notifier 在本 State 最终
    // dispose 时与控制器一并释放。
    _position.value = Duration.zero;
  }

  void _onPlayerUpdate() {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final value = ctrl.value;

    // 进度单独走 notifier：每帧更新不进入 setState。
    if (value.isInitialized &&
        !_seeking &&
        value.position != _position.value) {
      _position.value = value.position;
    }

    final next = _PlayerSnapshot(
      initialized: value.isInitialized,
      playing: value.isPlaying,
      buffering: value.isBuffering,
      looping: value.isLooping,
      duration: value.duration,
      size: value.size,
      aspectRatio: value.aspectRatio,
      errorText: value.errorDescription ?? '',
    );
    if (next.differsFrom(_snap)) {
      setState(() => _snap = next);
    }
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
    final snap = _snap;
    final controllerError = ctrl?.value.errorDescription;
    final hasControllerError =
        controllerError != null && controllerError.isNotEmpty;
    if (_error != null ||
        ctrl == null ||
        !snap.initialized ||
        hasControllerError) {
      final errorText = _error?.toString() ?? controllerError ?? '未知错误';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded,
                  size: 42, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('视频加载失败：$errorText', textAlign: TextAlign.center),
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

    final aspectRatio = snap.aspectRatio > 0 ? snap.aspectRatio : 4 / 3;

    return Container(
      color: const Color(0xFF101318),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: GestureDetector(
                  onTap: () => snap.playing ? ctrl.pause() : ctrl.play(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(ctrl),
                      if (snap.buffering)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white70,
                          ),
                        ),
                      if (!snap.playing)
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
                  tooltip: snap.playing ? '暂停' : '播放',
                  icon: Icon(
                    snap.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => snap.playing ? ctrl.pause() : ctrl.play(),
                ),
                Expanded(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: _position,
                    builder: (context, position, _) {
                      final durMs =
                          snap.duration.inMilliseconds.clamp(1, 1 << 30);
                      final posMs = position.inMilliseconds.clamp(0, durMs);
                      return Row(
                        children: [
                          Text(
                            '${_fmtDuration(position)} / ${_fmtDuration(snap.duration)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: posMs.toDouble(),
                              min: 0,
                              max: durMs.toDouble(),
                              onChanged: (v) {
                                // 拖动期间同步 notifier 并暂停 listener
                                // 写入，避免未到位的播放进度把拇指拉回去。
                                final target = Duration(milliseconds: v.round());
                                _seeking = true;
                                _position.value = target;
                                unawaited(ctrl.seekTo(target));
                              },
                              onChangeEnd: (v) async {
                                try {
                                  await ctrl.seekTo(
                                    Duration(milliseconds: v.round()),
                                  );
                                } catch (_) {
                                  // seek 失败也要恢复进度同步。
                                } finally {
                                  _seeking = false;
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
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
