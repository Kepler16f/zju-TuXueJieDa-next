import 'package:flutter/material.dart';

/// Engineering blueprint image stage with pinch/scroll zoom, pan, double-tap
/// reset, and optional press-and-hold overlay comparison image.
class ZoomableDiagramCanvas extends StatefulWidget {
  const ZoomableDiagramCanvas({
    super.key,
    required this.primaryAsset,
    this.compareAsset,
    this.compareLabel = '原题题面',
    this.isPeekingCompare = false,
  });

  final String primaryAsset;
  final String? compareAsset;
  final String compareLabel;
  final bool isPeekingCompare;

  @override
  State<ZoomableDiagramCanvas> createState() => _ZoomableDiagramCanvasState();
}

class _ZoomableDiagramCanvasState extends State<ZoomableDiagramCanvas> {
  final TransformationController _controller = TransformationController();
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant ZoomableDiagramCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryAsset != widget.primaryAsset) {
      // Keep zoom when stepping within same problem unless completely different.
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final s = _controller.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.01) {
      setState(() => _scale = s);
    }
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  void _zoomBy(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.8, 6.0);
    final ratio = target / current;
    _controller.value = _controller.value.clone()..scaleByDouble(ratio, ratio, 1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final showCompare = widget.isPeekingCompare && widget.compareAsset != null;
    final activeAsset = showCompare ? widget.compareAsset! : widget.primaryAsset;

    return Stack(
      children: [
        // Engineering CAD lines (thin cyan/blue/black) require crisp paper white.
        Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFF3F5F8),
          child: Center(
            child: GestureDetector(
              onDoubleTap: _resetZoom,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.75,
                maxScale: 6.0,
                boundaryMargin: const EdgeInsets.all(140),
                child: AspectRatio(
                  aspectRatio: 540 / 450,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD6DCE5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        activeAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showCompare)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade800.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '正在对比：${widget.compareLabel}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            elevation: 2,
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '缩小',
                    icon: const Icon(Icons.zoom_out_rounded, size: 19, color: Colors.black87),
                    onPressed: () => _zoomBy(0.8),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(52, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _resetZoom,
                    child: Text(
                      '${(_scale * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '放大',
                    icon: const Icon(Icons.zoom_in_rounded, size: 19, color: Colors.black87),
                    onPressed: () => _zoomBy(1.25),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
