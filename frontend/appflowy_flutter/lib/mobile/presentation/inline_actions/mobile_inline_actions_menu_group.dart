import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class MobileInlineActionsGroup extends StatelessWidget {
  const MobileInlineActionsGroup({
    super.key,
    required this.result,
    required this.editorState,
    required this.menuService,
    required this.style,
    required this.onSelected,
    required this.startOffset,
    required this.endOffset,
    required this.onPreSelect,
    this.isLastGroup = false,
    this.isGroupSelected = false,
    this.selectedIndex = 0,
  });

  final InlineActionsResult result;
  final EditorState editorState;
  final InlineActionsMenuService menuService;
  final InlineActionsMenuStyle style;
  final VoidCallback onSelected;
  final ValueChanged<int> onPreSelect;
  final int startOffset;
  final int endOffset;

  final bool isLastGroup;
  final bool isGroupSelected;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.title != null) ...[
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FlowyText.medium(
                  result.title!,
                  color: style.groupTextColor,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        ...result.results.mapIndexed(
          (index, item) => GestureDetector(
            onTapDown: (e) {
              onPreSelect.call(index);
            },
            child: MobileInlineActionsWidget(
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
        ),
      ],
    );
  }
}

class MobileInlineActionsWidget extends StatelessWidget {
  const MobileInlineActionsWidget({
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
  Widget build(BuildContext context) {
    final hasIcon = item.icon != null;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isSelected ? style.menuItemSelectedColor : null,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: FlowyButton(
        expand: true,
        isSelected: isSelected,
        text: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (hasIcon) ...[
                  item.icon!.call(isSelected),
                  SizedBox(width: 12),
                ],
                Flexible(
                  child: FlowyText.regular(
                    item.label,
                    figmaLineHeight: 18,
                    overflow: TextOverflow.ellipsis,
                    fontSize: 16,
                    color: style.menuItemSelectedTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        onTap: () => _onPressed(context),
      ),
    );
  }

  void _onPressed(BuildContext context) {
    onSelected();
    item.onSelected?.call(
      context,
      editorState,
      menuService,
      (startOffset, endOffset),
    );
  }
}
