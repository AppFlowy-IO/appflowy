import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu.dart';
import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

typedef SlashMenuItemsBuilder = List<SelectionMenuItem> Function(
  EditorState editorState,
  Node node,
);

/// Show the slash menu
///
/// - support
///   - desktop
///
final CharacterShortcutEvent appFlowySlashCommand = CharacterShortcutEvent(
  key: 'show the slash menu',
  character: '/',
  handler: (editorState) async => _showSlashMenu(
    editorState,
    itemsBuilder: (_, __) => standardSelectionMenuItems,
    supportSlashMenuNodeTypes: supportSlashMenuNodeTypes,
  ),
);

CharacterShortcutEvent customAppFlowySlashCommand({
  required SlashMenuItemsBuilder itemsBuilder,
  bool shouldInsertSlash = true,
  bool deleteKeywordsByDefault = false,
  bool singleColumn = true,
  SelectionMenuStyle style = SelectionMenuStyle.light,
  required Set<String> supportSlashMenuNodeTypes,
}) {
  return CharacterShortcutEvent(
    key: 'show the slash menu',
    character: '/',
    handler: (editorState) => _showSlashMenu(
      editorState,
      shouldInsertSlash: shouldInsertSlash,
      deleteKeywordsByDefault: deleteKeywordsByDefault,
      singleColumn: singleColumn,
      style: style,
      supportSlashMenuNodeTypes: supportSlashMenuNodeTypes,
      itemsBuilder: itemsBuilder,
    ),
  );
}

SelectionMenuService? _selectionMenuService;

Future<bool> _showSlashMenu(
  EditorState editorState, {
  required SlashMenuItemsBuilder itemsBuilder,
  bool shouldInsertSlash = true,
  bool singleColumn = true,
  bool deleteKeywordsByDefault = false,
  SelectionMenuStyle style = SelectionMenuStyle.light,
  required Set<String> supportSlashMenuNodeTypes,
}) async {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }

  // delete the selection
  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }

  final afterSelection = editorState.selection;
  if (afterSelection == null || !afterSelection.isCollapsed) {
    assert(false, 'the selection should be collapsed');
    return true;
  }

  final node = editorState.getNodeAtPath(selection.start.path);

  // only enable in white-list nodes
  if (node == null ||
      !_isSupportSlashMenuNode(node, supportSlashMenuNodeTypes)) {
    return false;
  }

  final items = itemsBuilder(editorState, node);

  // insert the slash character
  if (shouldInsertSlash) {
    keepEditorFocusNotifier.increase();
    await editorState.insertTextAtPosition('/', position: selection.start);
  }

  // show the slash menu

  final context = editorState.getNodeAtPath(selection.start.path)?.context;
  if (context != null && context.mounted) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    _selectionMenuService?.dismiss();
    _selectionMenuService = UniversalPlatform.isMobile
        ? MobileSelectionMenu(
            context: context,
            editorState: editorState,
            selectionMenuItems: items,
            deleteSlashByDefault: shouldInsertSlash,
            deleteKeywordsByDefault: deleteKeywordsByDefault,
            singleColumn: singleColumn,
            style: isLight
                ? MobileSelectionMenuStyle.light
                : MobileSelectionMenuStyle.dark,
            startOffset: editorState.selection?.start.offset ?? 0,
          )
        : SelectionMenu(
            context: context,
            editorState: editorState,
            selectionMenuItems: items,
            deleteSlashByDefault: shouldInsertSlash,
            deleteKeywordsByDefault: deleteKeywordsByDefault,
            singleColumn: singleColumn,
            style: style,
          );

    // disable the keyboard service
    editorState.service.keyboardService?.disable();

    await _selectionMenuService?.show();
    // enable the keyboard service
    editorState.service.keyboardService?.enable();
  }

  if (shouldInsertSlash) {
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) => keepEditorFocusNotifier.decrease(),
    );
  }

  return true;
}

bool _isSupportSlashMenuNode(
  Node node,
  Set<String> supportSlashMenuNodeWhiteList,
) {
  // Check if current node type is supported
  if (!supportSlashMenuNodeWhiteList.contains(node.type)) {
    return false;
  }

  // If node has a parent and level > 1, recursively check parent nodes
  if (node.level > 1 && node.parent != null) {
    return _isSupportSlashMenuNode(
      node.parent!,
      supportSlashMenuNodeWhiteList,
    );
  }

  return true;
}
