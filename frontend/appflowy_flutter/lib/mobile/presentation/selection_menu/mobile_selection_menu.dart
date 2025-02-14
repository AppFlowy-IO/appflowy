import 'dart:async';
import 'dart:math';

import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'mobile_selection_menu_item_widget.dart';
import 'mobile_selection_menu_widget.dart';

class MobileSelectionMenu extends SelectionMenuService {
  MobileSelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = false,
    this.deleteKeywordsByDefault = false,
    this.style = MobileSelectionMenuStyle.light,
    this.itemCountFilter = 0,
    this.startOffset = 0,
    this.singleColumn = false,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;

  @override
  final MobileSelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;
  final int itemCountFilter;
  final int startOffset;

  @override
  void dismiss() {
    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    final selectionRects = editorState.selectionRects();
    if (selectionRects.isEmpty) {
      return;
    }

    calculateSelectionMenuOffset(selectionRects.first);
    final (left, top, right, bottom) = getPosition();

    final editorHeight = editorState.renderBox!.size.height;
    final editorWidth = editorState.renderBox!.size.width;

    _selectionMenuEntry = OverlayEntry(
      builder: (context) {
        return SizedBox(
          width: editorWidth,
          height: editorHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismiss,
            child: Stack(
              children: [
                Positioned(
                  top: top,
                  bottom: bottom,
                  left: left,
                  right: right,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: MobileSelectionMenuWidget(
                      selectionMenuStyle: style,
                      singleColumn: singleColumn,
                      items: selectionMenuItems
                        ..forEach((element) {
                          if (element is MobileSelectionMenuItem) {
                            element.deleteSlash = false;
                            element.deleteKeywords = deleteKeywordsByDefault;
                            for (final e in element.children) {
                              e.deleteSlash = deleteSlashByDefault;
                              e.deleteKeywords = deleteKeywordsByDefault;
                              e.onSelected = () {
                                dismiss();
                              };
                            }
                          } else {
                            element.deleteSlash = deleteSlashByDefault;
                            element.deleteKeywords = deleteKeywordsByDefault;
                            element.onSelected = () {
                              dismiss();
                            };
                          }
                        }),
                      maxItemInRow: 5,
                      editorState: editorState,
                      itemCountFilter: itemCountFilter,
                      startOffset: startOffset,
                      menuService: this,
                      onExit: () {
                        dismiss();
                      },
                      deleteSlashByDefault: deleteSlashByDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);

    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
  }

  @override
  Alignment get alignment {
    return _alignment;
  }

  @override
  Offset get offset {
    return _offset;
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
        break;
      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
        break;
      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
        break;
    }

    return (left, top, right, bottom);
  }

  void calculateSelectionMenuOffset(Rect rect) {
    // Workaround: We can customize the padding through the [EditorStyle],
    // but the coordinates of overlay are not properly converted currently.
    // Just subtract the padding here as a result.
    const menuHeight = 192.0, menuWidth = 240.0 + 10;
    const menuOffset = Offset(0, 10);
    final editorOffset =
        editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorHeight = editorState.renderBox!.size.height;
    final editorWidth = editorState.renderBox!.size.width;

    // show below default
    _alignment = Alignment.topLeft;
    final bottomRight = rect.bottomRight;
    final topRight = rect.topRight;
    var offset = bottomRight + menuOffset;
    _offset = Offset(
      offset.dx,
      offset.dy,
    );

    // show above
    if (offset.dy + menuHeight >= editorOffset.dy + editorHeight) {
      offset = topRight - menuOffset;
      _alignment = Alignment.bottomLeft;

      final limitX = editorWidth - menuWidth;
      _offset = Offset(
        min(offset.dx, limitX),
        MediaQuery.of(context).size.height - offset.dy,
      );
    }

    // show on left
    if (_offset.dx - editorOffset.dx > editorWidth / 2) {
      _alignment = _alignment == Alignment.topLeft
          ? Alignment.topRight
          : Alignment.bottomRight;

      final x = editorWidth - _offset.dx + editorOffset.dx;
      final limitX = editorWidth - menuWidth + editorOffset.dx;
      _offset = Offset(
        min(x, limitX),
        _offset.dy,
      );
    }
  }
}
