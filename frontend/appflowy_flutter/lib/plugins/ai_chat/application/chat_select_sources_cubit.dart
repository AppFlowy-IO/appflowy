import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_select_sources_cubit.freezed.dart';

const int _kMaxSelectedParentPageCount = 3;

enum SourceSelectedStatus {
  unselected,
  selected,
  partiallySelected;

  bool get isUnselected => this == unselected;
  bool get isSelected => this == selected;
  bool get isPartiallySelected => this == partiallySelected;
}

class ChatSource {
  ChatSource({
    required this.view,
    required this.parentView,
    required this.children,
    required bool isExpanded,
    required SourceSelectedStatus selectedStatus,
    required IgnoreViewType ignoreStatus,
  })  : isExpandedNotifier = ValueNotifier(isExpanded),
        selectedStatusNotifier = ValueNotifier(selectedStatus),
        ignoreStatusNotifier = ValueNotifier(ignoreStatus);

  final ViewPB view;
  final ViewPB? parentView;
  final List<ChatSource> children;
  final ValueNotifier<bool> isExpandedNotifier;
  final ValueNotifier<SourceSelectedStatus> selectedStatusNotifier;
  final ValueNotifier<IgnoreViewType> ignoreStatusNotifier;

  bool get isExpanded => isExpandedNotifier.value;
  SourceSelectedStatus get selectedStatus => selectedStatusNotifier.value;
  IgnoreViewType get ignoreStatus => ignoreStatusNotifier.value;

  void toggleIsExpanded() {
    isExpandedNotifier.value = !isExpanded;
  }

  ChatSource copy() {
    return ChatSource(
      view: view,
      parentView: parentView,
      children: children.map<ChatSource>((child) => child.copy()).toList(),
      ignoreStatus: ignoreStatus,
      isExpanded: isExpanded,
      selectedStatus: selectedStatus,
    );
  }

  ChatSource? findChildBySourceId(String sourceId) {
    if (view.id == sourceId) {
      return this;
    }
    for (final child in children) {
      final childResult = child.findChildBySourceId(sourceId);
      if (childResult != null) {
        return childResult;
      }
    }
    return null;
  }

  void resetIgnoreViewTypeRecursive() {
    ignoreStatusNotifier.value = view.layout.isDocumentView
        ? IgnoreViewType.none
        : IgnoreViewType.disable;

    for (final child in children) {
      child.resetIgnoreViewTypeRecursive();
    }
  }

  void updateIgnoreViewTypeRecursive(IgnoreViewType newIgnoreViewType) {
    ignoreStatusNotifier.value = newIgnoreViewType;
    for (final child in children) {
      child.updateIgnoreViewTypeRecursive(newIgnoreViewType);
    }
  }

  void dispose() {
    for (final child in children) {
      child.dispose();
    }
    isExpandedNotifier.dispose();
    selectedStatusNotifier.dispose();
    ignoreStatusNotifier.dispose();
  }
}

class ChatSettingsCubit extends Cubit<ChatSettingsState> {
  ChatSettingsCubit() : super(ChatSettingsState.initial());

  List<String> selectedSourceIds = [];
  ChatSource? source;
  List<ChatSource> selectedSources = [];
  String filter = '';

  void updateOnlyUseSelectedSources(bool onlyUseSelectedSources) {
    if (state.onlyUseSelectedSources != onlyUseSelectedSources) {
      emit(state.copyWith(onlyUseSelectedSources: onlyUseSelectedSources));
    }
  }

  void updateSelectedSources(List<String> newSelectedSourceIds) {
    selectedSourceIds = [...newSelectedSourceIds];
  }

  void refreshSources(ViewPB view) async {
    filter = "";
    final newSource = await _recursiveBuild(view, null);

    _restrictSelectionIfNecessary(newSource.children);

    final selected = _buildSelectedSources(newSource).toList();

    newSource.toggleIsExpanded();

    emit(
      state.copyWith(
        selectedSources: selected,
        visibleSources: [newSource],
      ),
    );

    source?.dispose();
    source = newSource.copy();

    selectedSources
      ..forEach((e) => e.dispose())
      ..clear()
      ..addAll(selected.map((e) => e.copy()));
  }

  Future<ChatSource> _recursiveBuild(ViewPB view, ViewPB? parentView) async {
    SourceSelectedStatus selectedStatus = SourceSelectedStatus.unselected;
    final isThisSourceSelected = selectedSourceIds.contains(view.id);

    final childrenViews =
        await ViewBackendService.getChildViews(viewId: view.id).toNullable();

    int selectedCount = 0;
    final children = <ChatSource>[];

    if (childrenViews != null) {
      for (final childView in childrenViews) {
        if (childView.layout == ViewLayoutPB.Chat) {
          continue;
        }
        final childChatSource = await _recursiveBuild(childView, view);
        if (childChatSource.selectedStatus.isSelected) {
          selectedCount++;
        }
        children.add(childChatSource);
      }

      final areAllChildrenSelectedOrNoChildren =
          children.length == selectedCount;
      final isAnyChildNotUnselected =
          children.any((e) => !e.selectedStatus.isUnselected);

      if (isThisSourceSelected && areAllChildrenSelectedOrNoChildren) {
        selectedStatus = SourceSelectedStatus.selected;
      } else if (isThisSourceSelected || isAnyChildNotUnselected) {
        selectedStatus = SourceSelectedStatus.partiallySelected;
      }
    } else if (isThisSourceSelected) {
      selectedStatus = SourceSelectedStatus.selected;
    }

    return ChatSource(
      view: view,
      parentView: parentView,
      children: children,
      ignoreStatus: view.layout.isDocumentView
          ? IgnoreViewType.none
          : IgnoreViewType.disable,
      isExpanded: false,
      selectedStatus: selectedStatus,
    );
  }

  void _restrictSelectionIfNecessary(List<ChatSource> sources) {
    for (final source in sources) {
      source.resetIgnoreViewTypeRecursive();
    }
    if (sources.where((e) => !e.selectedStatus.isUnselected).length >=
        _kMaxSelectedParentPageCount) {
      sources
          .where((e) => e.selectedStatus == SourceSelectedStatus.unselected)
          .forEach(
            (e) => e.updateIgnoreViewTypeRecursive(IgnoreViewType.disable),
          );
    }
  }

  void updateFilter(String filter) {
    this.filter = filter;
    for (final source in state.visibleSources) {
      source.dispose();
    }
    if (source == null) {
      emit(ChatSettingsState.initial());
    } else {
      final selected =
          selectedSources.map(_buildSearchResults).nonNulls.toList();
      final visible = [_buildSearchResults(source!)].nonNulls.toList();
      emit(
        state.copyWith(
          selectedSources: selected,
          visibleSources: visible,
        ),
      );
    }
  }

  /// traverse tree to build up search query
  ChatSource? _buildSearchResults(ChatSource chatSource) {
    final isVisible = chatSource.view.nameOrDefault
        .toLowerCase()
        .contains(filter.toLowerCase());

    final childrenResults = <ChatSource>[];
    for (final childSource in chatSource.children) {
      final childResult = _buildSearchResults(childSource);
      if (childResult != null) {
        childrenResults.add(childResult);
      }
    }

    return isVisible || childrenResults.isNotEmpty
        ? ChatSource(
            view: chatSource.view,
            parentView: chatSource.parentView,
            children: childrenResults,
            ignoreStatus: chatSource.ignoreStatus,
            isExpanded: chatSource.isExpanded,
            selectedStatus: chatSource.selectedStatus,
          )
        : null;
  }

  /// traverse tree to build up selected sources
  Iterable<ChatSource> _buildSelectedSources(ChatSource chatSource) {
    final children = <ChatSource>[];

    for (final childSource in chatSource.children) {
      children.addAll(_buildSelectedSources(childSource));
    }

    return selectedSourceIds.contains(chatSource.view.id)
        ? [
            ChatSource(
              view: chatSource.view,
              parentView: chatSource.parentView,
              children: children,
              ignoreStatus: chatSource.ignoreStatus,
              selectedStatus: chatSource.selectedStatus,
              isExpanded: true,
            ),
          ]
        : children;
  }

  void toggleSelectedStatus(ChatSource chatSource) {
    if (chatSource.view.isSpace) {
      return;
    }
    final allIds = _recursiveGetSourceIds(chatSource);

    if (chatSource.selectedStatus.isUnselected ||
        chatSource.selectedStatus.isPartiallySelected &&
            !chatSource.view.layout.isDocumentView) {
      for (final id in allIds) {
        if (!selectedSourceIds.contains(id)) {
          selectedSourceIds.add(id);
        }
      }
    } else {
      for (final id in allIds) {
        if (selectedSourceIds.contains(id)) {
          selectedSourceIds.remove(id);
        }
      }
    }

    updateSelectedStatus();
  }

  List<String> _recursiveGetSourceIds(ChatSource chatSource) {
    return [
      if (chatSource.view.layout.isDocumentView) chatSource.view.id,
      for (final childSource in chatSource.children)
        ..._recursiveGetSourceIds(childSource),
    ];
  }

  void updateSelectedStatus() {
    if (source == null) {
      return;
    }
    _recursiveUpdateSelectedStatus(source!);
    _restrictSelectionIfNecessary(source!.children);
    for (final visibleSource in state.visibleSources) {
      visibleSource.dispose();
    }
    final visible = [_buildSearchResults(source!)].nonNulls.toList();

    selectedSources
      ..forEach((e) => e.dispose())
      ..clear()
      ..addAll(_buildSelectedSources(source!));
    emit(
      state.copyWith(
        visibleSources: visible,
        selectedSources:
            selectedSources.map(_buildSearchResults).nonNulls.toList(),
      ),
    );
  }

  SourceSelectedStatus _recursiveUpdateSelectedStatus(ChatSource chatSource) {
    SourceSelectedStatus selectedStatus = SourceSelectedStatus.unselected;

    int selectedCount = 0;
    for (final childSource in chatSource.children) {
      final childStatus = _recursiveUpdateSelectedStatus(childSource);
      if (childStatus.isSelected) {
        selectedCount++;
      }
    }

    final isThisSourceSelected = selectedSourceIds.contains(chatSource.view.id);
    final areAllChildrenSelectedOrNoChildren =
        chatSource.children.length == selectedCount;
    final isAnyChildNotUnselected =
        chatSource.children.any((e) => !e.selectedStatus.isUnselected);

    if (isThisSourceSelected && areAllChildrenSelectedOrNoChildren) {
      selectedStatus = SourceSelectedStatus.selected;
    } else if (isThisSourceSelected || isAnyChildNotUnselected) {
      selectedStatus = SourceSelectedStatus.partiallySelected;
    }

    chatSource.selectedStatusNotifier.value = selectedStatus;
    return selectedStatus;
  }

  void toggleIsExpanded(ChatSource chatSource, bool isSelectedSection) {
    chatSource.toggleIsExpanded();
    if (isSelectedSection) {
      for (final selectedSource in selectedSources) {
        selectedSource
            .findChildBySourceId(chatSource.view.id)
            ?.toggleIsExpanded();
      }
    } else {
      source?.findChildBySourceId(chatSource.view.id)?.toggleIsExpanded();
    }
  }

  @override
  Future<void> close() {
    source?.dispose();
    for (final child in state.selectedSources) {
      child.dispose();
    }
    for (final child in state.visibleSources) {
      child.dispose();
    }
    return super.close();
  }
}

@freezed
class ChatSettingsState with _$ChatSettingsState {
  const factory ChatSettingsState({
    required bool onlyUseSelectedSources,
    required List<ChatSource> visibleSources,
    required List<ChatSource> selectedSources,
  }) = _ChatSettingsState;

  factory ChatSettingsState.initial() => const ChatSettingsState(
        onlyUseSelectedSources: false,
        visibleSources: [],
        selectedSources: [],
      );
}
