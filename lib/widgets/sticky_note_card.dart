import 'dart:async';

import 'package:flutter/material.dart';

import '../data/curriculum_repository.dart';

/// Per-problem sticky note card shown in the workspace detail panel.
///
/// Editing is debounced (600 ms) into [CurriculumRepository.setNote]; an
/// explicit save button flushes immediately, and switching problems flushes
/// any pending edit for the previous problem first.
class StickyNoteCard extends StatefulWidget {
  const StickyNoteCard({
    super.key,
    required this.repo,
    required this.problemId,
    this.editorInDialog = false,
  });

  final CurriculumRepository repo;
  final String problemId;

  /// 编辑形态：false = 侧栏内联展开输入（横屏/桌面默认）；
  /// true = 竖屏点按钮弹出对话框输入/编辑（题干已并入主界面，不再内联展开）。
  final bool editorInDialog;

  @override
  State<StickyNoteCard> createState() => _StickyNoteCardState();
}

class _StickyNoteCardState extends State<StickyNoteCard> {
  static const _debounceDuration = Duration(milliseconds: 600);

  late final TextEditingController _controller;
  Timer? _debounceTimer;
  bool _editing = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.repo.noteFor(widget.problemId));
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(StickyNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.problemId != widget.problemId) {
      // Flush the outgoing problem's note before swapping content. An open
      // editor stays open and shows the incoming problem's note.
      _persist(oldWidget.problemId, _controller.text);
      _dirty = false;
      _controller
        ..removeListener(_handleTextChanged)
        ..text = widget.repo.noteFor(widget.problemId)
        ..addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    if (_dirty) {
      _persist(widget.problemId, _controller.text);
    }
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (!_editing) return;
    _dirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      _debounceDuration,
      () => _persist(widget.problemId, _controller.text),
    );
    setState(() {});
  }

  void _persist(String problemId, String text) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _dirty = false;
    unawaited(widget.repo.setNote(problemId, text));
  }

  void _startEditing() {
    setState(() => _editing = true);
  }

  /// 竖屏形态：弹出对话框输入/编辑便签，保存后即持久化。
  Future<void> _openEditorDialog() async {
    final theme = Theme.of(context);
    final hasNote = widget.repo.noteFor(widget.problemId).trim().isNotEmpty;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hasNote ? '编辑便签' : '添加便签'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: '在这里写你的解题心得/易错点…',
            border: OutlineInputBorder(),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _controller
                ..removeListener(_handleTextChanged)
                ..text = widget.repo.noteFor(widget.problemId)
                ..addListener(_handleTextChanged);
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _clearNote();
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('清空'),
          ),
          FilledButton.icon(
            onPressed: () {
              _persist(widget.problemId, _controller.text);
              Navigator.of(dialogContext).pop(true);
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  void _saveAndCloseEditor() {
    _persist(widget.problemId, _controller.text);
    setState(() => _editing = false);
  }

  Future<void> _clearNote() async {
    _debounceTimer?.cancel();
    _controller
      ..removeListener(_handleTextChanged)
      ..clear()
      ..addListener(_handleTextChanged);
    _dirty = false;
    await widget.repo.setNote(widget.problemId, '');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteText = _editing
        ? _controller.text
        : widget.repo.noteFor(widget.problemId);
    final hasNote = noteText.trim().isNotEmpty;
    final charCount = _editing ? _controller.text.length : noteText.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '便签',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_editing) ...[
                TextButton.icon(
                  onPressed: _saveAndCloseEditor,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('保存'),
                ),
                IconButton(
                  tooltip: '清空便签内容',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _clearNote,
                ),
              ] else
                IconButton(
                  tooltip: hasNote ? '编辑便签' : '添加便签',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(hasNote ? Icons.edit_outlined : Icons.add_rounded),
                  onPressed: widget.editorInDialog
                      ? _openEditorDialog
                      : _startEditing,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_editing)
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '在这里写你的解题心得/易错点…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            )
          else if (widget.editorInDialog)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openEditorDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  hasNote ? noteText : '点此添加便签，方便日后回顾本题',
                  style: hasNote
                      ? theme.textTheme.bodyMedium?.copyWith(height: 1.55)
                      : theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                ),
              ),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _startEditing,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  hasNote ? noteText : '点击添加便签，方便日后回顾本题',
                  style: hasNote
                      ? theme.textTheme.bodyMedium?.copyWith(height: 1.55)
                      : theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$charCount 字',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
