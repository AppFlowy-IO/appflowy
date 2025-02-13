import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'mobile_selection_menu_item.dart';

class MobileSelectionMenuItemWidget extends StatelessWidget {
  const MobileSelectionMenuItemWidget({
    super.key,
    required this.editorState,
    required this.menuService,
    required this.item,
    required this.isSelected,
    required this.selectionMenuStyle,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final bool isSelected;
  final SelectionMenuStyle selectionMenuStyle;

  @override
  Widget build(BuildContext context) {
    final style = selectionMenuStyle;
    final showRightArrow = item is MobileSelectionMenuItem &&
        (item as MobileSelectionMenuItem).isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton.icon(
        icon: item.icon(
          editorState,
          false,
          selectionMenuStyle,
        ),
        style: ButtonStyle(
          alignment: Alignment.centerLeft,
          overlayColor: WidgetStateProperty.all(
            style.selectionMenuItemSelectedColor,
          ),
          backgroundColor: isSelected
              ? WidgetStateProperty.all(
                  style.selectionMenuItemSelectedColor,
                )
              : WidgetStateProperty.all(Colors.transparent),
        ),
        label: Row(
          children: [
            item.nameBuilder?.call(item.name, style, false) ??
                Text(
                  item.name,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: style.selectionMenuItemTextColor,
                    fontSize: 16.0,
                  ),
                ),
            if (showRightArrow) ...[
              Spacer(),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: style.selectionMenuItemTextColor.withValues(alpha: 0.3),
              ),
            ],
          ],
        ),
        onPressed: () {
          item.handler(
            editorState,
            menuService,
            context,
          );
        },
      ),
    );
  }
}
