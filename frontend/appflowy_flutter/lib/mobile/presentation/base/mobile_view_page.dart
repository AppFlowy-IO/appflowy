import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar.dart';
import 'package:appflowy/mobile/presentation/base/view_page/app_bar_buttons.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_mobile_state_container.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_lock_status_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileViewPage extends StatefulWidget {
  const MobileViewPage({
    super.key,
    required this.id,
    required this.viewLayout,
    this.title,
    this.arguments,
    this.fixedTitle,
    this.showMoreButton = true,
    this.blockId,
    this.tabs = const [PickerTabType.emoji, PickerTabType.icon],
  });

  /// view id
  final String id;
  final ViewLayoutPB viewLayout;
  final String? title;
  final Map<String, dynamic>? arguments;
  final bool showMoreButton;
  final String? blockId;
  final List<PickerTabType> tabs;

  // only used in row page
  final String? fixedTitle;

  @override
  State<MobileViewPage> createState() => _MobileViewPageState();
}

class _MobileViewPageState extends State<MobileViewPage> {
  // used to determine if the user has scrolled down and show the app bar in immersive mode
  ScrollNotificationObserverState? _scrollNotificationObserver;

  // control the app bar opacity when in immersive mode
  final ValueNotifier<double> _appBarOpacity = ValueNotifier(1.0);

  @override
  void initState() {
    super.initState();

    getIt<ReminderBloc>().add(const ReminderEvent.started());
  }

  @override
  void dispose() {
    _appBarOpacity.dispose();

    // there's no need to remove the listener, because the observer will be disposed when the widget is unmounted.
    // inside the observer, the listener will be removed automatically.
    // _scrollNotificationObserver?.removeListener(_onScrollNotification);
    _scrollNotificationObserver = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MobileViewPageBloc(viewId: widget.id)
        ..add(const MobileViewPageEvent.initial()),
      child: BlocBuilder<MobileViewPageBloc, MobileViewPageState>(
        builder: (context, state) {
          final view = state.result?.fold((s) => s, (f) => null);
          final body = _buildBody(context, state);

          if (view == null) {
            return SizedBox.shrink();
          }

          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    FavoriteBloc()..add(const FavoriteEvent.initial()),
              ),
              BlocProvider(
                create: (_) =>
                    ViewBloc(view: view)..add(const ViewEvent.initial()),
              ),
              BlocProvider.value(
                value: getIt<ReminderBloc>(),
              ),
              BlocProvider(
                create: (_) =>
                    ShareBloc(view: view)..add(const ShareEvent.initial()),
              ),
              if (state.userProfilePB != null)
                BlocProvider(
                  create: (_) =>
                      UserWorkspaceBloc(userProfile: state.userProfilePB!)
                        ..add(const UserWorkspaceEvent.initial()),
                ),
              if (view.layout.isDocumentView)
                BlocProvider(
                  create: (_) => DocumentPageStyleBloc(view: view)
                    ..add(const DocumentPageStyleEvent.initial()),
                ),
              if (view.layout.isDocumentView || view.layout.isDatabaseView)
                BlocProvider(
                  create: (_) => ViewLockStatusBloc(view: view)
                    ..add(const ViewLockStatusEvent.initial()),
                ),
            ],
            child: Builder(
              builder: (context) {
                final view = context.watch<ViewBloc>().state.view;
                return _buildApp(context, view, body);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildApp(
    BuildContext context,
    ViewPB? view,
    Widget child,
  ) {
    final isDocument = view?.layout.isDocumentView ?? false;
    final title = _buildTitle(context, view);
    final actions = _buildAppBarActions(context, view);
    final appBar = isDocument
        ? MobileViewPageImmersiveAppBar(
            preferredSize: Size(
              double.infinity,
              AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight,
            ),
            title: title,
            appBarOpacity: _appBarOpacity,
            actions: actions,
            view: view,
          )
        : FlowyAppBar(title: title, actions: actions);
    final body = isDocument
        ? Builder(
            builder: (context) {
              _rebuildScrollNotificationObserver(context);
              return child;
            },
          )
        : SafeArea(child: child);
    return Scaffold(
      extendBodyBehindAppBar: isDocument,
      appBar: appBar,
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, MobileViewPageState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final result = state.result;
    if (result == null) {
      return FlowyMobileStateContainer.error(
        emoji: '😔',
        title: LocaleKeys.error_weAreSorry.tr(),
        description: LocaleKeys.error_loadingViewError.tr(),
        errorMsg: '',
      );
    }

    return result.fold(
      (view) {
        final plugin = view.plugin(arguments: widget.arguments ?? const {})
          ..init();
        return plugin.widgetBuilder.buildWidget(
          shrinkWrap: false,
          context: PluginContext(userProfile: state.userProfilePB),
          data: {
            MobileDocumentScreen.viewFixedTitle: widget.fixedTitle,
            MobileDocumentScreen.viewBlockId: widget.blockId,
            MobileDocumentScreen.viewSelectTabs: widget.tabs,
          },
        );
      },
      (error) {
        return FlowyMobileStateContainer.error(
          emoji: '😔',
          title: LocaleKeys.error_weAreSorry.tr(),
          description: LocaleKeys.error_loadingViewError.tr(),
          errorMsg: error.toString(),
        );
      },
    );
  }

  // Document:
  //  - [ collaborators, sync_indicator, layout_button, more_button]
  // Database:
  //  - [ sync_indicator, more_button]
  List<Widget> _buildAppBarActions(BuildContext context, ViewPB? view) {
    if (view == null) {
      return [];
    }

    final isImmersiveMode =
        context.read<MobileViewPageBloc>().state.isImmersiveMode;
    final isLocked =
        context.read<ViewLockStatusBloc?>()?.state.isLocked ?? false;
    final actions = <Widget>[];

    if (FeatureFlag.syncDocument.isOn) {
      // only document supports displaying collaborators.
      if (view.layout.isDocumentView) {
        actions.addAll([
          DocumentCollaborators(
            width: 60,
            height: 44,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(vertical: 8),
            view: view,
          ),
          const HSpace(12.0),
        ]);
      }
    }

    if (view.layout.isDocumentView && !isLocked) {
      actions.addAll([
        MobileViewPageLayoutButton(
          view: view,
          isImmersiveMode: isImmersiveMode,
          appBarOpacity: _appBarOpacity,
          tabs: widget.tabs,
        ),
      ]);
    }

    if (widget.showMoreButton) {
      actions.addAll([
        MobileViewPageMoreButton(
          view: view,
          isImmersiveMode: isImmersiveMode,
          appBarOpacity: _appBarOpacity,
        ),
      ]);
    } else {
      actions.addAll([
        const HSpace(18.0),
      ]);
    }

    return actions;
  }

  Widget _buildTitle(BuildContext context, ViewPB? view) {
    final icon = view?.icon;
    return ValueListenableBuilder(
      valueListenable: _appBarOpacity,
      builder: (_, value, child) {
        if (value < 0.99) {
          return Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: _buildLockStatus(context, view),
          );
        }

        return Opacity(
          opacity: value,
          child: Row(
            children: [
              if (icon != null && icon.value.isNotEmpty) ...[
                RawEmojiIconWidget(
                  emoji: icon.toEmojiIconData(),
                  emojiSize: 15,
                ),
                const HSpace(4),
              ],
              FlowyText.medium(
                widget.fixedTitle ?? view?.name ?? widget.title ?? '',
                fontSize: 15.0,
                overflow: TextOverflow.ellipsis,
                figmaLineHeight: 18.0,
              ),
              const HSpace(4.0),
              _buildLockStatusIcon(context, view),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLockStatus(BuildContext context, ViewPB? view) {
    if (view == null || view.layout == ViewLayoutPB.Chat) {
      return const SizedBox.shrink();
    }

    return BlocConsumer<ViewLockStatusBloc, ViewLockStatusState>(
      listenWhen: (previous, current) =>
          previous.isLoadingLockStatus == current.isLoadingLockStatus &&
          current.isLoadingLockStatus == false,
      listener: (context, state) {
        if (state.isLocked) {
          showToastNotification(
            context,
            message: LocaleKeys.lockPage_pageLockedToast.tr(),
          );

          EditorNotification.exitEditing().post();
        }
      },
      builder: (context, state) {
        if (state.isLocked) {
          return LockedPageStatus();
        } else if (!state.isLocked && state.lockCounter > 0) {
          return ReLockedPageStatus();
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildLockStatusIcon(BuildContext context, ViewPB? view) {
    if (view == null || view.layout == ViewLayoutPB.Chat) {
      return const SizedBox.shrink();
    }

    return BlocConsumer<ViewLockStatusBloc, ViewLockStatusState>(
      listenWhen: (previous, current) =>
          previous.isLoadingLockStatus == current.isLoadingLockStatus &&
          current.isLoadingLockStatus == false,
      listener: (context, state) {
        if (state.isLocked) {
          showToastNotification(
            context,
            message: LocaleKeys.lockPage_pageLockedToast.tr(),
          );
        }
      },
      builder: (context, state) {
        if (state.isLocked) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.read<ViewLockStatusBloc>().add(
                    const ViewLockStatusEvent.unlock(),
                  );
            },
            child: Padding(
              padding: const EdgeInsets.only(
                top: 4.0,
                right: 8,
                bottom: 4.0,
              ),
              child: FlowySvg(
                FlowySvgs.lock_page_s,
                color: const Color(0xFFD95A0B),
              ),
            ),
          );
        } else if (!state.isLocked && state.lockCounter > 0) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.read<ViewLockStatusBloc>().add(
                    const ViewLockStatusEvent.lock(),
                  );
            },
            child: Padding(
              padding: const EdgeInsets.only(
                top: 4.0,
                right: 8,
                bottom: 4.0,
              ),
              child: FlowySvg(
                FlowySvgs.unlock_page_s,
                color: Color(0xFF8F959E),
                blendMode: null,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _rebuildScrollNotificationObserver(BuildContext context) {
    _scrollNotificationObserver?.removeListener(_onScrollNotification);
    _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollNotificationObserver?.addListener(_onScrollNotification);
  }

  // immersive mode related
  // auto show or hide the app bar based on the scroll position
  void _onScrollNotification(ScrollNotification notification) {
    if (_scrollNotificationObserver == null) {
      return;
    }

    if (notification is ScrollUpdateNotification &&
        defaultScrollNotificationPredicate(notification)) {
      final ScrollMetrics metrics = notification.metrics;
      double height = MediaQuery.of(context).padding.top;
      if (defaultTargetPlatform == TargetPlatform.android) {
        height += AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight;
      }
      final progress = (metrics.pixels / height).clamp(0.0, 1.0);
      // reduce the sensitivity of the app bar opacity change
      if ((progress - _appBarOpacity.value).abs() >= 0.1 ||
          progress == 0 ||
          progress == 1.0) {
        _appBarOpacity.value = progress;
      }
    }
  }
}
