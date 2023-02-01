import 'package:app_flowy/plugins/document/presentation/plugins/base/insert_page_command.dart';
import 'package:app_flowy/plugins/grid/presentation/grid_page.dart';
import 'package:app_flowy/startup/startup.dart';
import 'package:app_flowy/workspace/application/app/app_service.dart';
import 'package:app_flowy/workspace/application/view/view_ext.dart';
import 'package:app_flowy/workspace/presentation/home/home_stack.dart';
import 'package:app_flowy/workspace/presentation/home/menu/menu.dart';
import 'package:app_flowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pbserver.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:dartz/dartz.dart' as dartz;
import 'package:flowy_infra_ui/style_widget/icon_button.dart';
import 'package:flutter/material.dart';
import 'package:app_flowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/image.dart';

const String kGridType = 'grid';

class GridNodeWidgetBuilder extends NodeWidgetBuilder<Node> {
  @override
  Widget build(NodeWidgetContext<Node> context) {
    return _GridWidget(
      key: context.node.key,
      node: context.node,
      editorState: context.editorState,
    );
  }

  @override
  NodeValidator<Node> get nodeValidator => (node) {
        return node.attributes[kAppID] is String &&
            node.attributes[kViewID] is String;
      };
}

class _GridWidget extends StatefulWidget {
  const _GridWidget({
    Key? key,
    required this.node,
    required this.editorState,
  }) : super(key: key);

  final Node node;
  final EditorState editorState;

  @override
  State<_GridWidget> createState() => _GridWidgetState();
}

class _GridWidgetState extends State<_GridWidget> {
  final focusNode = FocusNode();

  String get gridID {
    return widget.node.attributes[kViewID];
  }

  String get appID {
    return widget.node.attributes[kAppID];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dartz.Either<ViewPB, FlowyError>>(
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final board = snapshot.data?.getLeftOrNull<ViewPB>();
          if (board != null) {
            return _build(context, board);
          }
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
      future: AppService().getView(appID, gridID),
    );
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  Widget _build(BuildContext context, ViewPB viewPB) {
    return MouseRegion(
      onEnter: (event) {
        widget.editorState.service.scrollService?.disable();
      },
      onExit: (event) {
        widget.editorState.service.scrollService?.enable();
      },
      child: SizedBox(
        height: 400,
        child: Stack(
          children: [
            _buildMenu(context, viewPB),
            _buildGrid(context, viewPB),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, ViewPB viewPB) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (value) {
        if (value) {
          widget.editorState.service.selectionService.clearSelection();
        }
      },
      child: GridPage(
        key: ValueKey(viewPB.id),
        view: viewPB,
      ),
    );
  }

  Widget _buildMenu(BuildContext context, ViewPB viewPB) {
    return Positioned(
      top: 5,
      left: 5,
      child: PopoverActionList<_ActionWrapper>(
        direction: PopoverDirection.bottomWithCenterAligned,
        actions:
            _ActionType.values.map((action) => _ActionWrapper(action)).toList(),
        buildChild: (controller) {
          return FlowyIconButton(
            tooltipText: LocaleKeys.tooltip_openMenu.tr(),
            width: 20,
            height: 30,
            iconPadding: const EdgeInsets.all(3),
            icon: svgWidget('editor/details'),
            onPressed: () => controller.show(),
          );
        },
        onSelected: (action, controller) async {
          switch (action.inner) {
            case _ActionType.openAsPage:
              getIt<MenuSharedState>().latestOpenView = viewPB;
              getIt<HomeStackManager>().setPlugin(viewPB.plugin());

              break;
            case _ActionType.delete:
              final transaction = widget.editorState.transaction;
              transaction.deleteNode(widget.node);
              widget.editorState.apply(transaction);
              break;
          }
          controller.close();
        },
      ),
    );
  }
}

enum _ActionType {
  openAsPage,
  delete,
}

class _ActionWrapper extends ActionCell {
  final _ActionType inner;

  _ActionWrapper(this.inner);

  Widget? icon(Color iconColor) => null;

  @override
  String get name {
    switch (inner) {
      case _ActionType.openAsPage:
        return LocaleKeys.tooltip_openAsPage.tr();
      case _ActionType.delete:
        return LocaleKeys.disclosureAction_delete.tr();
    }
  }
}
