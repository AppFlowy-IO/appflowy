import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_file.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_image.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/draggable_item/draggable_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _excludeFromDropTarget = [
  ImageBlockKeys.type,
  CustomImageBlockKeys.type,
  MultiImageBlockKeys.type,
  FileBlockKeys.type,
  SimpleTableBlockKeys.type,
  SimpleTableCellBlockKeys.type,
  SimpleTableRowBlockKeys.type,
];

class EditorDropHandler extends StatelessWidget {
  const EditorDropHandler({
    super.key,
    required this.viewId,
    required this.editorState,
    required this.isLocalMode,
    required this.child,
    this.dropManagerState,
  });

  final String viewId;
  final EditorState editorState;
  final bool isLocalMode;
  final Widget child;
  final EditorDropManagerState? dropManagerState;

  @override
  Widget build(BuildContext context) {
    final childWidget = Consumer<EditorDropManagerState>(
      builder: (context, dropState, _) => DragTarget<ViewPB>(
        onLeave: (_) {
          editorState.selectionService.removeDropTarget();
          disableAutoScrollWhenDragging = false;
        },
        onMove: (details) {
          disableAutoScrollWhenDragging = true;

          if (details.data.id == viewId) {
            return;
          }

          _onDragUpdated(details.offset);
        },
        onWillAcceptWithDetails: (details) {
          if (!dropState.isDropEnabled) {
            return false;
          }

          if (details.data.id == viewId) {
            return false;
          }

          return true;
        },
        onAcceptWithDetails: _onDragViewDone,
        builder: (context, _, __) => ChangeNotifierProvider(
          create: (_) => getIt.get<EditorDropManagerState>(),
          builder: (context, _) {
            final topLevelEditorDropManagerState =
                Provider.of<EditorDropManagerState>(context);
            return DropTarget(
              enable: dropState.isDropEnabled &&
                  topLevelEditorDropManagerState.isDropEnabled,
              onDragExited: (_) =>
                  editorState.selectionService.removeDropTarget(),
              onDragUpdated: (details) =>
                  _onDragUpdated(details.globalPosition),
              onDragDone: _onDragDone,
              child: child,
            );
          },
        ),
      ),
    );

    // Due to how DropTarget works, there is no way to differentiate if an overlay is
    // blocking the target visibly, so when we have an overlay with a drop target,
    // we should disable the drop target for the Editor, until it is closed.
    //
    // See FileBlockComponent for sample use.
    //
    // Relates to:
    // - https://github.com/MixinNetwork/flutter-plugins/issues/2
    // - https://github.com/MixinNetwork/flutter-plugins/issues/331
    if (dropManagerState != null) {
      return ChangeNotifierProvider.value(
        value: dropManagerState!,
        child: childWidget,
      );
    }

    return ChangeNotifierProvider(
      create: (_) => EditorDropManagerState(),
      child: childWidget,
    );
  }

  void _onDragUpdated(Offset position) {
    final data = editorState.selectionService.getDropTargetRenderData(position);

    if (data != null &&
        data.dropPath != null &&

        // We implement custom Drop logic for image blocks, this is
        // how we can exclude them from the Drop Target
        !_excludeFromDropTarget.contains(data.cursorNode?.type)) {
      // Render the drop target
      editorState.selectionService.renderDropTargetForOffset(position);
    } else {
      editorState.selectionService.removeDropTarget();
    }
  }

  Future<void> _onDragDone(DropDoneDetails details) async {
    editorState.selectionService.removeDropTarget();

    final data = editorState.selectionService
        .getDropTargetRenderData(details.globalPosition);

    if (data != null) {
      final cursorNode = data.cursorNode;
      final dropPath = data.dropPath;

      if (cursorNode != null && dropPath != null) {
        if (_excludeFromDropTarget.contains(cursorNode.type)) {
          return;
        }

        for (final file in details.files) {
          final fileName = file.name.toLowerCase();
          if (file.mimeType?.startsWith('image/') ??
              false || imgExtensionRegex.hasMatch(fileName)) {
            await editorState.dropImages(dropPath, [file], viewId, isLocalMode);
          } else {
            await editorState.dropFiles(dropPath, [file], viewId, isLocalMode);
          }
        }
      }
    }
  }

  void _onDragViewDone(DragTargetDetails<ViewPB> details) {
    editorState.selectionService.removeDropTarget();

    final data =
        editorState.selectionService.getDropTargetRenderData(details.offset);
    if (data != null) {
      final cursorNode = data.cursorNode;
      final dropPath = data.dropPath;

      if (cursorNode != null && dropPath != null) {
        if (_excludeFromDropTarget.contains(cursorNode.type)) {
          return;
        }

        final view = details.data;
        final node = pageMentionNode(view.id);
        final t = editorState.transaction..insertNode(dropPath, node);
        editorState.apply(t);
      }
    }
  }
}
