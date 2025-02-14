import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy/plugins/inline_actions/widgets/inline_actions_handler.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class InlineActionsGroup extends StatelessWidget {
  const InlineActionsGroup({
    super.key,
    required this.result,
    required this.editorState,
    required this.menuService,
    required this.style,
    required this.onSelected,
    required this.startOffset,
    required this.endOffset,
    this.isLastGroup = false,
    this.isGroupSelected = false,
    this.selectedIndex = 0,
  });

  final InlineActionsResult result;
  final EditorState editorState;
  final InlineActionsMenuService menuService;
  final InlineActionsMenuStyle style;
  final VoidCallback onSelected;
  final int startOffset;
  final int endOffset;

  final bool isLastGroup;
  final bool isGroupSelected;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: isLastGroup ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.title != null) ...[
            FlowyText.medium(result.title!, color: style.groupTextColor),
            const SizedBox(height: 4),
          ],
          ...result.results.mapIndexed(
            (index, item) => InlineActionsWidget(
              item: item,
              editorState: editorState,
              menuService: menuService,
              isSelected: isGroupSelected && index == selectedIndex,
              style: style,
              onSelected: onSelected,
              startOffset: startOffset,
              endOffset: endOffset,
            ),
          ),
        ],
      ),
    );
  }
}

class InlineActionsWidget extends StatefulWidget {
  const InlineActionsWidget({
    super.key,
    required this.item,
    required this.editorState,
    required this.menuService,
    required this.isSelected,
    required this.style,
    required this.onSelected,
    required this.startOffset,
    required this.endOffset,
  });

  final InlineActionsMenuItem item;
  final EditorState editorState;
  final InlineActionsMenuService menuService;
  final bool isSelected;
  final InlineActionsMenuStyle style;
  final VoidCallback onSelected;
  final int startOffset;
  final int endOffset;

  @override
  State<InlineActionsWidget> createState() => _InlineActionsWidgetState();
}

class _InlineActionsWidgetState extends State<InlineActionsWidget> {
  @override
  Widget build(BuildContext context) {
    final icon = widget.item.icon;
    final hasIcon = icon != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        width: kInlineMenuWidth,
        child: FlowyButton(
          expand: true,
          isSelected: widget.isSelected,
          text: Row(
            children: [
              if (hasIcon) ...[
                icon.call(widget.isSelected),
                SizedBox(width: 12),
              ],
              Flexible(
                child: FlowyText.regular(
                  widget.item.label,
                  figmaLineHeight: 18,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          onTap: _onPressed,
        ),
      ),
    );
  }

  void _onPressed() {
    widget.onSelected();
    widget.item.onSelected?.call(
      context,
      widget.editorState,
      widget.menuService,
      (widget.startOffset, widget.endOffset),
    );
  }
}
