import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/insert_page_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy/plugins/inline_actions/service_handler.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/dialog/styled_dialogs.dart';
import 'package:flutter/material.dart';

// const _channel = "InlinePageReference";

// TODO(Mathias): Clean up and use folder search instead
class InlinePageReferenceService extends InlineActionsDelegate {
  InlinePageReferenceService({
    required this.currentViewId,
    this.viewLayout,
    this.customTitle,
    this.insertPage = false,
    this.limitResults = 5,
  }) : assert(limitResults > 0, 'limitResults must be greater than 0') {
    init();
  }

  final Completer _initCompleter = Completer<void>();

  final String currentViewId;
  final ViewLayoutPB? viewLayout;
  final String? customTitle;

  /// Defaults to false, if set to true the Page
  /// will be inserted as a Reference
  /// When false, a link to the view will be inserted
  ///
  final bool insertPage;

  /// Defaults to 5
  /// Will limit the page reference results
  /// to [limitResults].
  ///
  final int limitResults;

  late final CachedRecentService _recentService;

  bool _recentViewsInitialized = false;
  late final List<InlineActionsMenuItem> _recentViews;

  Future<List<InlineActionsMenuItem>> _getRecentViews() async {
    if (_recentViewsInitialized) {
      return _recentViews;
    }

    _recentViewsInitialized = true;

    final sectionViews = await _recentService.recentViews();
    final views =
        sectionViews.unique((e) => e.item.id).map((e) => e.item).toList();

    // Filter by viewLayout
    views.retainWhere(
      (i) =>
          currentViewId != i.id &&
          (viewLayout == null || i.layout == viewLayout),
    );

    // Map to InlineActionsMenuItem, then take 5 items
    return _recentViews = views.map(_fromView).take(5).toList();
  }

  bool _viewsInitialized = false;
  late final List<ViewPB> _allViews;

  Future<List<ViewPB>> _getViews() async {
    if (_viewsInitialized) {
      return _allViews;
    }

    _viewsInitialized = true;

    final viewResult = await ViewBackendService.getAllViews();
    return _allViews = viewResult
            .toNullable()
            ?.items
            .where((v) => viewLayout == null || v.layout == viewLayout)
            .toList() ??
        const [];
  }

  Future<void> init() async {
    _recentService = getIt<CachedRecentService>();
    // _searchListener.start(onResultsClosed: _onResults);
  }

  @override
  Future<void> dispose() async {
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }

    await super.dispose();
  }

  @override
  Future<InlineActionsResult> search([
    String? search,
  ]) async {
    final isSearching = search != null && search.isNotEmpty;

    late List<InlineActionsMenuItem> items;
    if (isSearching) {
      final allViews = await _getViews();

      items = allViews
          .where(
            (view) =>
                view.id != currentViewId &&
                    view.name.toLowerCase().contains(search.toLowerCase()) ||
                (view.name.isEmpty && search.isEmpty) ||
                (view.name.isEmpty &&
                    LocaleKeys.menuAppHeader_defaultNewPageName
                        .tr()
                        .toLowerCase()
                        .contains(search.toLowerCase())),
          )
          .take(limitResults)
          .map((view) => _fromView(view))
          .toList();
    } else {
      items = await _getRecentViews();
    }

    return InlineActionsResult(
      title: customTitle?.isNotEmpty == true
          ? customTitle!
          : isSearching
              ? LocaleKeys.inlineActions_pageReference.tr()
              : LocaleKeys.inlineActions_recentPages.tr(),
      results: items,
    );
  }

  Future<void> _onInsertPageRef(
    ViewPB view,
    BuildContext context,
    EditorState editorState,
    (int, int) replace,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.start.path);

    if (node != null) {
      // Delete search term
      if (replace.$2 > 0) {
        final transaction = editorState.transaction
          ..deleteText(node, replace.$1, replace.$2);
        await editorState.apply(transaction);
      }

      // Insert newline before inserting referenced database
      if (node.delta?.toPlainText().isNotEmpty == true) {
        await editorState.insertNewLine();
      }
    }

    try {
      await editorState.insertReferencePage(view, view.layout);
    } on FlowyError catch (e) {
      if (context.mounted) {
        return Dialogs.show(
          context,
          child: AppFlowyErrorPage(
            error: e,
          ),
        );
      }
    }
  }

  Future<void> _onInsertLinkRef(
    ViewPB view,
    BuildContext context,
    EditorState editorState,
    InlineActionsMenuService menuService,
    (int, int) replace,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    // @page name -> $
    // preload the page infos
    pageMemorizer[view.id] = view;
    final transaction = editorState.transaction
      ..replaceText(
        node,
        replace.$1,
        replace.$2,
        MentionBlockKeys.mentionChar,
        attributes: {
          MentionBlockKeys.mention: {
            MentionBlockKeys.type: MentionType.page.name,
            MentionBlockKeys.pageId: view.id,
          },
        },
      );

    await editorState.apply(transaction);
  }

  InlineActionsMenuItem _fromView(ViewPB view) => InlineActionsMenuItem(
        keywords: [view.nameOrDefault.toLowerCase()],
        label: view.nameOrDefault,
        icon: (onSelected) => view.icon.value.isNotEmpty
            ? RawEmojiIconWidget(
                emoji: view.icon.toEmojiIconData(),
                emojiSize: 14,
              )
            : view.defaultIcon(),
        onSelected: (context, editorState, menu, replace) => insertPage
            ? _onInsertPageRef(view, context, editorState, replace)
            : _onInsertLinkRef(view, context, editorState, menu, replace),
      );

// Future<InlineActionsMenuItem?> _fromSearchResult(
//   SearchResultPB result,
// ) async {
//   final viewRes = await ViewBackendService.getView(result.viewId);
//   final view = viewRes.toNullable();
//   if (view == null) {
//     return null;
//   }

//   return _fromView(view);
// }
}
