import 'dart:math';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_select_sources_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../layout_define.dart';
import 'chat_mention_page_menu.dart';

class PromptInputDesktopSelectSourcesButton extends StatefulWidget {
  const PromptInputDesktopSelectSourcesButton({
    super.key,
    required this.onUpdateSelectedSources,
  });

  final void Function(bool, List<String>) onUpdateSelectedSources;

  @override
  State<PromptInputDesktopSelectSourcesButton> createState() =>
      _PromptInputDesktopSelectSourcesButtonState();
}

class _PromptInputDesktopSelectSourcesButtonState
    extends State<PromptInputDesktopSelectSourcesButton> {
  late final cubit = ChatSettingsCubit();
  final popoverController = PopoverController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatBlocState = context.read<ChatBloc>().state;
      cubit
        ..updateSelectedSources(chatBlocState.selectedSourceIds)
        ..updateOnlyUseSelectedSources(chatBlocState.onlyUseSelectedSources);
    });
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final userProfile = userWorkspaceBloc.userProfile;
    final workspaceId =
        userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => SpaceBloc(
            userProfile: userProfile,
            workspaceId: workspaceId,
          )..add(const SpaceEvent.initial(openFirstPage: false)),
        ),
        BlocProvider.value(
          value: cubit,
        ),
      ],
      child: BlocSelector<SpaceBloc, SpaceState, ViewPB?>(
        selector: (state) => state.currentSpace,
        builder: (context, spaceView) {
          return BlocListener<ChatBloc, ChatState>(
            listener: (context, state) {
              cubit
                ..updateOnlyUseSelectedSources(state.onlyUseSelectedSources)
                ..updateSelectedSources(state.selectedSourceIds)
                ..updateSelectedStatus();
            },
            child: AppFlowyPopover(
              constraints: BoxConstraints.loose(const Size(320, 380)),
              offset: const Offset(0.0, -10.0),
              direction: PopoverDirection.topWithCenterAligned,
              margin: EdgeInsets.zero,
              controller: popoverController,
              onOpen: () {
                if (spaceView != null) {
                  context.read<ChatSettingsCubit>().refreshSources(spaceView);
                }
              },
              onClose: () {
                widget.onUpdateSelectedSources(
                  cubit.state.onlyUseSelectedSources,
                  cubit.selectedSourceIds,
                );
                if (spaceView != null) {
                  context.read<ChatSettingsCubit>().refreshSources(spaceView);
                }
              },
              popupBuilder: (_) {
                return BlocProvider.value(
                  value: context.read<ChatSettingsCubit>(),
                  child: const _PopoverContent(),
                );
              },
              child: _IndicatorButton(
                onTap: () => popoverController.show(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IndicatorButton extends StatelessWidget {
  const _IndicatorButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: DesktopAIPromptSizes.actionBarButtonSize,
        child: FlowyHover(
          style: const HoverStyle(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 4, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowySvg(
                  FlowySvgs.ai_page_s,
                  color: Theme.of(context).iconTheme.color,
                ),
                const HSpace(2.0),
                BlocBuilder<ChatBloc, ChatState>(
                  builder: (context, state) {
                    return FlowyText(
                      state.selectedSourceIds.length.toString(),
                      fontSize: 14,
                      figmaLineHeight: 16,
                      color: Theme.of(context).hintColor,
                    );
                  },
                ),
                const HSpace(2.0),
                FlowySvg(
                  FlowySvgs.ai_source_drop_down_s,
                  color: Theme.of(context).hintColor,
                  size: const Size.square(10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoverContent extends StatelessWidget {
  const _PopoverContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatSettingsCubit, ChatSettingsState>(
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: SpaceSearchField(
                width: 600,
                onSearch: (context, value) =>
                    context.read<ChatSettingsCubit>().updateFilter(value),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              height: 30,
              child: FlowyButton(
                text: FlowyText(
                  LocaleKeys.chat_onlyUseRags.tr(),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  context
                      .read<ChatSettingsCubit>()
                      .updateOnlyUseSelectedSources(
                        !state.onlyUseSelectedSources,
                      );
                },
                rightIcon: state.onlyUseSelectedSources
                    ? FlowySvg(
                        FlowySvgs.check_s,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
            ),
            _buildDivider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                children: [
                  ..._buildSelectedSources(context, state),
                  if (state.selectedSources.isNotEmpty &&
                      state.visibleSources.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: _buildDivider(),
                    ),
                  ..._buildVisibleSources(context, state),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1.0,
      thickness: 1.0,
      indent: 8.0,
      endIndent: 8.0,
    );
  }

  Iterable<Widget> _buildSelectedSources(
    BuildContext context,
    ChatSettingsState state,
  ) {
    return state.selectedSources
        .where((e) => e.ignoreStatus != IgnoreViewType.hide)
        .map(
          (e) => ChatSourceTreeItem(
            key: ValueKey(
              'selected_select_sources_tree_item_${e.view.id}',
            ),
            chatSource: e,
            level: 0,
            isDescendentOfSpace: e.view.isSpace,
            isSelectedSection: true,
            onSelected: (chatSource) {
              context
                  .read<ChatSettingsCubit>()
                  .toggleSelectedStatus(chatSource);
            },
            height: 30.0,
          ),
        );
  }

  Iterable<Widget> _buildVisibleSources(
    BuildContext context,
    ChatSettingsState state,
  ) {
    return state.visibleSources
        .where((e) => e.ignoreStatus != IgnoreViewType.hide)
        .map(
          (e) => ChatSourceTreeItem(
            key: ValueKey(
              'visible_select_sources_tree_item_${e.view.id}',
            ),
            chatSource: e,
            level: 0,
            isDescendentOfSpace: e.view.isSpace,
            isSelectedSection: false,
            onSelected: (chatSource) {
              context
                  .read<ChatSettingsCubit>()
                  .toggleSelectedStatus(chatSource);
            },
            height: 30.0,
          ),
        );
  }
}

class ChatSourceTreeItem extends StatefulWidget {
  const ChatSourceTreeItem({
    super.key,
    required this.chatSource,
    required this.level,
    required this.isDescendentOfSpace,
    required this.isSelectedSection,
    required this.onSelected,
    required this.height,
    this.showCheckbox = true,
  });

  final ChatSource chatSource;

  /// nested level of the view item
  final int level;

  final bool isDescendentOfSpace;

  final bool isSelectedSection;

  final void Function(ChatSource chatSource) onSelected;

  final double height;

  final bool showCheckbox;

  @override
  State<ChatSourceTreeItem> createState() => _ChatSourceTreeItemState();
}

class _ChatSourceTreeItemState extends State<ChatSourceTreeItem> {
  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: widget.height,
      child: ChatSourceTreeItemInner(
        chatSource: widget.chatSource,
        level: widget.level,
        isDescendentOfSpace: widget.isDescendentOfSpace,
        isSelectedSection: widget.isSelectedSection,
        showCheckbox: widget.showCheckbox,
        onSelected: widget.onSelected,
      ),
    );

    final disabledEnabledChild =
        widget.chatSource.ignoreStatus == IgnoreViewType.disable
            ? FlowyTooltip(
                message: widget.showCheckbox
                    ? switch (widget.chatSource.view.layout) {
                        ViewLayoutPB.Document =>
                          LocaleKeys.chat_sourcesLimitReached.tr(),
                        _ => LocaleKeys.chat_sourceUnsupported.tr(),
                      }
                    : "",
                child: Opacity(
                  opacity: 0.5,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.forbidden,
                    child: IgnorePointer(child: child),
                  ),
                ),
              )
            : child;

    return ValueListenableBuilder(
      valueListenable: widget.chatSource.isExpandedNotifier,
      builder: (context, isExpanded, child) {
        // filter the child views that should be ignored
        final childViews = widget.chatSource.children
            .where((e) => e.ignoreStatus != IgnoreViewType.hide)
            .toList();

        if (!isExpanded || childViews.isEmpty) {
          return disabledEnabledChild;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            disabledEnabledChild,
            ...childViews.map(
              (childSource) => ChatSourceTreeItem(
                key: ValueKey(
                  'select_sources_tree_item_${childSource.view.id}',
                ),
                chatSource: childSource,
                level: widget.level + 1,
                isDescendentOfSpace: widget.isDescendentOfSpace,
                isSelectedSection: widget.isSelectedSection,
                onSelected: widget.onSelected,
                height: widget.height,
                showCheckbox: widget.showCheckbox,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ChatSourceTreeItemInner extends StatelessWidget {
  const ChatSourceTreeItemInner({
    super.key,
    required this.chatSource,
    required this.level,
    required this.isDescendentOfSpace,
    required this.isSelectedSection,
    required this.showCheckbox,
    this.onSelected,
  });

  final ChatSource chatSource;
  final int level;
  final bool isDescendentOfSpace;
  final bool isSelectedSection;
  final bool showCheckbox;
  final void Function(ChatSource)? onSelected;

  @override
  Widget build(BuildContext context) {
    return FlowyHover(
      style: HoverStyle(
        hoverColor: AFThemeExtension.of(context).lightGreyHover,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onSelected?.call(chatSource),
        child: Row(
          children: [
            const HSpace(4.0),
            HSpace(max(20.0 * level - (isDescendentOfSpace ? 2 : 0), 0)),
            // builds the >, ^ or · button
            ToggleIsExpandedButton(
              chatSource: chatSource,
              isSelectedSection: isSelectedSection,
            ),
            const HSpace(2.0),
            // checkbox
            if (!chatSource.view.isSpace && showCheckbox) ...[
              SourceSelectedStatusCheckbox(
                chatSource: chatSource,
              ),
              const HSpace(4.0),
            ],
            // icon
            MentionViewIcon(
              view: chatSource.view,
            ),
            const HSpace(6.0),
            // title
            Expanded(
              child: FlowyText(
                chatSource.view.nameOrDefault,
                overflow: TextOverflow.ellipsis,
                fontSize: 14.0,
                figmaLineHeight: 18.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToggleIsExpandedButton extends StatelessWidget {
  const ToggleIsExpandedButton({
    super.key,
    required this.chatSource,
    required this.isSelectedSection,
  });

  final ChatSource chatSource;
  final bool isSelectedSection;

  @override
  Widget build(BuildContext context) {
    if (isReferencedDatabaseView(chatSource.view, chatSource.parentView)) {
      return const _DotIconWidget();
    }

    if (chatSource.children.isEmpty) {
      return const SizedBox.square(dimension: 16.0);
    }

    return FlowyHover(
      child: GestureDetector(
        child: ValueListenableBuilder(
          valueListenable: chatSource.isExpandedNotifier,
          builder: (context, value, _) => FlowySvg(
            value
                ? FlowySvgs.view_item_expand_s
                : FlowySvgs.view_item_unexpand_s,
            size: const Size.square(16.0),
          ),
        ),
        onTap: () => context
            .read<ChatSettingsCubit>()
            .toggleIsExpanded(chatSource, isSelectedSection),
      ),
    );
  }
}

class _DotIconWidget extends StatelessWidget {
  const _DotIconWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).iconTheme.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class SourceSelectedStatusCheckbox extends StatelessWidget {
  const SourceSelectedStatusCheckbox({
    super.key,
    required this.chatSource,
  });

  final ChatSource chatSource;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: chatSource.selectedStatusNotifier,
      builder: (context, selectedStatus, _) => FlowySvg(
        switch (selectedStatus) {
          SourceSelectedStatus.unselected => FlowySvgs.uncheck_s,
          SourceSelectedStatus.selected => FlowySvgs.check_filled_s,
          SourceSelectedStatus.partiallySelected => FlowySvgs.check_partial_s,
        },
        size: const Size.square(18.0),
        blendMode: null,
      ),
    );
  }
}
