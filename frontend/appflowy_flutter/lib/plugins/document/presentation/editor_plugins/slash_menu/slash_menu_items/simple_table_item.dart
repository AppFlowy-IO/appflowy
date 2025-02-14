import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'slash_menu_item_builder.dart';

final _keywords = [
  'table',
  'rows',
  'columns',
  'data',
];

// table menu item
SelectionMenuItem tableSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_table.tr(),
  keywords: _keywords,
  handler: (editorState, _, __) async => editorState.insertSimpleTable(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_simple_table_s,
    isSelected: isSelected,
    style: style,
  ),
);

SelectionMenuItem mobileTableSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_simpleTable.tr(),
  keywords: _keywords,
  handler: (editorState, _, __) async => editorState.insertSimpleTable(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_simple_table_s,
    isSelected: isSelected,
    style: style,
  ),
);

extension on EditorState {
  Future<void> insertSimpleTable() async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final currentNode = getNodeAtPath(selection.end.path);
    if (currentNode == null) {
      return;
    }

    // create a simple table with 2 columns and 2 rows
    final tableNode = createSimpleTableBlockNode(
      columnCount: 2,
      rowCount: 2,
    );

    final transaction = this.transaction;
    final delta = currentNode.delta;
    if (delta != null && delta.isEmpty) {
      final path = selection.end.path;
      transaction
        ..insertNode(path, tableNode)
        ..deleteNode(currentNode);
      transaction.afterSelection = Selection.collapsed(
        Position(
          // table -> row -> cell -> paragraph
          path: path + [0, 0, 0],
        ),
      );
    } else {
      final path = selection.end.path.next;
      transaction.insertNode(path, tableNode);
      transaction.afterSelection = Selection.collapsed(
        Position(
          // table -> row -> cell -> paragraph
          path: path + [0, 0, 0],
        ),
      );
    }

    await apply(transaction);
  }
}
