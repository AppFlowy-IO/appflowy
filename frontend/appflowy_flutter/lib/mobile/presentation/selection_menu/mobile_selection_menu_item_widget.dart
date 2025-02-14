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
    required this.onTap,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final bool isSelected;
  final MobileSelectionMenuStyle selectionMenuStyle;
  final VoidCallback onTap;

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
                color: style.selectionMenuItemRightIconColor,
              ),
            ],
          ],
        ),
        onPressed: () {
          onTap.call();
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

class MobileSelectionMenuStyle extends SelectionMenuStyle {
  const MobileSelectionMenuStyle({
    required super.selectionMenuBackgroundColor,
    required super.selectionMenuItemTextColor,
    required super.selectionMenuItemIconColor,
    required super.selectionMenuItemSelectedTextColor,
    required super.selectionMenuItemSelectedIconColor,
    required super.selectionMenuItemSelectedColor,
    required this.selectionMenuItemRightIconColor,
  });

  final Color selectionMenuItemRightIconColor;

  static const MobileSelectionMenuStyle light = MobileSelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFFFFFFFF),
    selectionMenuItemTextColor: Color(0xFF1F2225),
    selectionMenuItemIconColor: Color(0xFF333333),
    selectionMenuItemSelectedColor: Color(0xFFF2F5F7),
    selectionMenuItemRightIconColor: Color(0xB31E2022),
    selectionMenuItemSelectedTextColor: Color.fromARGB(255, 56, 91, 247),
    selectionMenuItemSelectedIconColor: Color.fromARGB(255, 56, 91, 247),
  );

  static const MobileSelectionMenuStyle dark = MobileSelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFF424242),
    selectionMenuItemTextColor: Color(0xFFFFFFFF),
    selectionMenuItemIconColor: Color(0xFFFFFFFF),
    selectionMenuItemSelectedColor: Color(0xFF666666),
    selectionMenuItemRightIconColor: Color(0xB3FFFFFF),
    selectionMenuItemSelectedTextColor: Color(0xFF131720),
    selectionMenuItemSelectedIconColor: Color(0xFF131720),
  );
}
