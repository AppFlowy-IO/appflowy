import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_mobile_quick_action_button.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_lock_status_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum MobileViewBottomSheetBodyAction {
  undo,
  redo,
  rename,
  duplicate,
  delete,
  addToFavorites,
  removeFromFavorites,
  helpCenter,
  publish,
  unpublish,
  copyPublishLink,
  visitSite,
  copyShareLink,
  updatePathName,
  lockPage;

  static const disableInLockedView = [
    undo,
    redo,
    rename,
    delete,
  ];
}

class MobileViewBottomSheetBodyActionArguments {
  static const isLockedKey = 'is_locked';
}

typedef MobileViewBottomSheetBodyActionCallback = void Function(
  MobileViewBottomSheetBodyAction action,
  // for the [MobileViewBottomSheetBodyAction.lockPage] action,
  // it will pass the [isLocked] value to the callback.
  {
  Map<String, dynamic>? arguments,
});

class ViewPageBottomSheet extends StatefulWidget {
  const ViewPageBottomSheet({
    super.key,
    required this.view,
    required this.onAction,
    required this.onRename,
  });

  final ViewPB view;
  final MobileViewBottomSheetBodyActionCallback onAction;
  final void Function(String name) onRename;

  @override
  State<ViewPageBottomSheet> createState() => _ViewPageBottomSheetState();
}

class _ViewPageBottomSheetState extends State<ViewPageBottomSheet> {
  MobileBottomSheetType type = MobileBottomSheetType.view;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case MobileBottomSheetType.view:
        return MobileViewBottomSheetBody(
          view: widget.view,
          onAction: (action, {arguments}) {
            switch (action) {
              case MobileViewBottomSheetBodyAction.rename:
                setState(() {
                  type = MobileBottomSheetType.rename;
                });
                break;
              default:
                widget.onAction(action, arguments: arguments);
            }
          },
        );

      case MobileBottomSheetType.rename:
        return MobileBottomSheetRenameWidget(
          name: widget.view.name,
          onRename: (name) {
            widget.onRename(name);
          },
        );
    }
  }
}

class MobileViewBottomSheetBody extends StatelessWidget {
  const MobileViewBottomSheetBody({
    super.key,
    required this.view,
    required this.onAction,
  });

  final ViewPB view;
  final MobileViewBottomSheetBodyActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final isFavorite = view.isFavorite;
    final isLocked =
        context.watch<ViewLockStatusBloc?>()?.state.isLocked ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileQuickActionButton(
          text: LocaleKeys.button_rename.tr(),
          icon: FlowySvgs.view_item_rename_s,
          iconSize: const Size.square(18),
          enable: !isLocked,
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.rename,
          ),
        ),
        _divider(),
        MobileQuickActionButton(
          text: isFavorite
              ? LocaleKeys.button_removeFromFavorites.tr()
              : LocaleKeys.button_addToFavorites.tr(),
          icon: isFavorite ? FlowySvgs.unfavorite_s : FlowySvgs.favorite_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            isFavorite
                ? MobileViewBottomSheetBodyAction.removeFromFavorites
                : MobileViewBottomSheetBodyAction.addToFavorites,
          ),
        ),
        _divider(),
        if (view.layout.isDatabaseView || view.layout.isDocumentView) ...[
          MobileQuickActionButton(
            text: LocaleKeys.disclosureAction_lockPage.tr(),
            icon: FlowySvgs.lock_page_s,
            iconSize: const Size.square(18),
            rightIconBuilder: (context) => _LockPageRightIconBuilder(
              onAction: onAction,
            ),
            onTap: () {
              final isLocked =
                  context.read<ViewLockStatusBloc?>()?.state.isLocked ?? false;
              onAction(
                MobileViewBottomSheetBodyAction.lockPage,
                arguments: {
                  MobileViewBottomSheetBodyActionArguments.isLockedKey:
                      !isLocked,
                },
              );
            },
          ),
          _divider(),
        ],
        MobileQuickActionButton(
          text: LocaleKeys.button_duplicate.tr(),
          icon: FlowySvgs.duplicate_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.duplicate,
          ),
        ),
        // copy link
        _divider(),
        MobileQuickActionButton(
          text: LocaleKeys.shareAction_copyLink.tr(),
          icon: FlowySvgs.m_copy_link_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.copyShareLink,
          ),
        ),
        _divider(),
        ..._buildPublishActions(context),
        _divider(),
        MobileQuickActionButton(
          text: LocaleKeys.button_delete.tr(),
          textColor: Theme.of(context).colorScheme.error,
          icon: FlowySvgs.trash_s,
          iconColor: Theme.of(context).colorScheme.error,
          iconSize: const Size.square(18),
          enable: !isLocked,
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.delete,
          ),
        ),
        _divider(),
      ],
    );
  }

  List<Widget> _buildPublishActions(BuildContext context) {
    final userProfile = context.read<MobileViewPageBloc>().state.userProfilePB;
    // the publish feature is only available for AppFlowy Cloud
    if (userProfile == null ||
        userProfile.authenticator != AuthenticatorPB.AppFlowyCloud) {
      return [];
    }

    final isPublished = context.watch<ShareBloc>().state.isPublished;
    if (isPublished) {
      return [
        MobileQuickActionButton(
          text: LocaleKeys.shareAction_updatePathName.tr(),
          icon: FlowySvgs.view_item_rename_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.updatePathName,
          ),
        ),
        _divider(),
        MobileQuickActionButton(
          text: LocaleKeys.shareAction_visitSite.tr(),
          icon: FlowySvgs.m_visit_site_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.visitSite,
          ),
        ),
        _divider(),
        MobileQuickActionButton(
          text: LocaleKeys.shareAction_unPublish.tr(),
          icon: FlowySvgs.m_unpublish_s,
          iconSize: const Size.square(18),
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.unpublish,
          ),
        ),
      ];
    } else {
      return [
        MobileQuickActionButton(
          text: LocaleKeys.shareAction_publish.tr(),
          icon: FlowySvgs.m_publish_s,
          onTap: () => onAction(
            MobileViewBottomSheetBodyAction.publish,
          ),
        ),
      ];
    }
  }

  Widget _divider() => const MobileQuickActionDivider();
}

class _LockPageRightIconBuilder extends StatelessWidget {
  const _LockPageRightIconBuilder({
    required this.onAction,
  });

  final MobileViewBottomSheetBodyActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    final isLocked =
        context.watch<ViewLockStatusBloc?>()?.state.isLocked ?? false;
    return SizedBox(
      width: 46,
      height: 30,
      child: FittedBox(
        fit: BoxFit.fill,
        child: CupertinoSwitch(
          value: isLocked,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: (value) {
            onAction(
              MobileViewBottomSheetBodyAction.lockPage,
              arguments: {
                MobileViewBottomSheetBodyActionArguments.isLockedKey: value,
              },
            );
          },
        ),
      ),
    );
  }
}
