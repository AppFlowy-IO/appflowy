import 'package:appflowy/plugins/database/widgets/database_view_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/built_in_page_widget.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DatabaseBlockKeys {
  const DatabaseBlockKeys._();

  static const String gridType = 'grid';
  static const String boardType = 'board';
  static const String calendarType = 'calendar';

  static const String parentID = 'parent_id';
  static const String viewID = 'view_id';
}

class DatabaseViewBlockComponentBuilder extends BlockComponentBuilder {
  DatabaseViewBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return DatabaseBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      node.attributes[DatabaseBlockKeys.parentID] is String &&
      node.attributes[DatabaseBlockKeys.viewID] is String;
}

class DatabaseBlockComponentWidget extends BlockComponentStatefulWidget {
  const DatabaseBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<DatabaseBlockComponentWidget> createState() =>
      _DatabaseBlockComponentWidgetState();
}

class _DatabaseBlockComponentWidgetState
    extends State<DatabaseBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Widget build(BuildContext context) {
    final editorState = Provider.of<EditorState>(context, listen: false);
    Widget child = BuiltInPageWidget(
      node: widget.node,
      editorState: editorState,
      builder: (view) => DatabaseViewWidget(key: ValueKey(view.id), view: view),
    );

    child = Padding(
      padding: padding,
      child: FocusScope(
        skipTraversal: true,
        onFocusChange: (value) {
          if (value && keepEditorFocusNotifier.value == 0) {
            context.read<EditorState>().selection = null;
          }
        },
        child: child,
      ),
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: widget.node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }

    if (!editorState.editable) {
      child = IgnorePointer(
        child: child,
      );
    }

    return child;
  }
}
