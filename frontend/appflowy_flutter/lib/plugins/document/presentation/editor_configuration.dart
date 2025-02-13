import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/code_block_copy_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// The node types that support slash menu.
final Set<String> supportSlashMenuNodeTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,

  // Lists
  TodoListBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  QuoteBlockKeys.type,
  ToggleListBlockKeys.type,

  // Simple table
  SimpleTableBlockKeys.type,
  SimpleTableRowBlockKeys.type,
  SimpleTableCellBlockKeys.type,
};

/// Build the block component builders.
///
/// Every block type should have a corresponding builder in the map.
/// Otherwise, the errorBlockComponentBuilder will be rendered.
///
/// Additional, you can define the block render options in the builder
/// - customize the block option actions. (... button and + button)
/// - customize the block component configuration. (padding, placeholder, etc.)
/// - customize the block icon. (bulleted list, numbered list, todo list)
/// - customize the hover menu. (show the menu at the top-right corner of the block)
Map<String, BlockComponentBuilder> buildBlockComponentBuilders({
  required BuildContext context,
  required EditorState editorState,
  required EditorStyleCustomizer styleCustomizer,
  SlashMenuItemsBuilder? slashMenuItemsBuilder,
  bool editable = true,
  ShowPlaceholder? showParagraphPlaceholder,
  String Function(Node)? placeholderText,
  EdgeInsets? customHeadingPadding,
  bool alwaysDistributeSimpleTableColumnWidths = false,
}) {
  final configuration = _buildDefaultConfiguration(context);
  final builders = _buildBlockComponentBuilderMap(
    context,
    configuration: configuration,
    editorState: editorState,
    styleCustomizer: styleCustomizer,
    showParagraphPlaceholder: showParagraphPlaceholder,
    placeholderText: placeholderText,
    alwaysDistributeSimpleTableColumnWidths:
        alwaysDistributeSimpleTableColumnWidths,
  );

  // customize the action builder. actually, we can customize them in their own builder. Put them here just for convenience.
  if (editable) {
    _customBlockOptionActions(
      context,
      builders: builders,
      editorState: editorState,
      styleCustomizer: styleCustomizer,
      slashMenuItemsBuilder: slashMenuItemsBuilder,
    );
  }

  return builders;
}

BlockComponentConfiguration _buildDefaultConfiguration(BuildContext context) {
  final configuration = BlockComponentConfiguration(
    padding: (node) {
      if (UniversalPlatform.isMobile) {
        final pageStyle = context.read<DocumentPageStyleBloc>().state;
        final factor = pageStyle.fontLayout.factor;
        final top = pageStyle.lineHeightLayout.padding * factor;
        EdgeInsets edgeInsets = EdgeInsets.only(top: top);
        // only add padding for the top level node, otherwise the nested node will have extra padding
        if (node.path.length == 1) {
          if (node.type != SimpleTableBlockKeys.type) {
            // do not add padding for the simple table to allow it overflow
            edgeInsets = edgeInsets.copyWith(
              left: EditorStyleCustomizer.nodeHorizontalPadding,
            );
          }
          edgeInsets = edgeInsets.copyWith(
            right: EditorStyleCustomizer.nodeHorizontalPadding,
          );
        }
        return edgeInsets;
      }

      return const EdgeInsets.symmetric(vertical: 5.0);
    },
    indentPadding: (node, textDirection) {
      double padding = 26.0;
      // only add indent padding for the top level node to align the children
      if (UniversalPlatform.isMobile && node.path.length == 1) {
        padding += EditorStyleCustomizer.nodeHorizontalPadding;
      }
      return textDirection == TextDirection.ltr
          ? EdgeInsets.only(left: padding)
          : EdgeInsets.only(right: padding);
    },
  );
  return configuration;
}

/// Build the option actions for the block component.
///
/// Notes: different block type may have different option actions.
/// All the block types have the delete and duplicate options.
List<OptionAction> _buildOptionActions(BuildContext context, String type) {
  final standardActions = [
    OptionAction.delete,
    OptionAction.duplicate,
  ];

  // filter out the copy link to block option if in local mode
  if (context.read<DocumentBloc?>()?.isLocalMode != true) {
    standardActions.add(OptionAction.copyLinkToBlock);
  }

  standardActions.add(OptionAction.turnInto);

  if (SimpleTableBlockKeys.type == type) {
    standardActions.addAll([
      OptionAction.divider,
      OptionAction.setToPageWidth,
      OptionAction.distributeColumnsEvenly,
    ]);
  }

  if (EditorOptionActionType.color.supportTypes.contains(type)) {
    standardActions.addAll([OptionAction.divider, OptionAction.color]);
  }

  if (EditorOptionActionType.align.supportTypes.contains(type)) {
    standardActions.addAll([OptionAction.divider, OptionAction.align]);
  }

  if (EditorOptionActionType.depth.supportTypes.contains(type)) {
    standardActions.addAll([OptionAction.divider, OptionAction.depth]);
  }

  return standardActions;
}

void _customBlockOptionActions(
  BuildContext context, {
  required Map<String, BlockComponentBuilder> builders,
  required EditorState editorState,
  required EditorStyleCustomizer styleCustomizer,
  SlashMenuItemsBuilder? slashMenuItemsBuilder,
}) {
  for (final entry in builders.entries) {
    if (entry.key == PageBlockKeys.type) {
      continue;
    }
    final builder = entry.value;
    final actions = _buildOptionActions(context, entry.key);

    if (UniversalPlatform.isDesktop) {
      builder.showActions = (node) {
        final parentTableNode = node.parentTableNode;
        // disable the option action button in table cell to avoid the misalignment issue
        if (node.type != SimpleTableBlockKeys.type && parentTableNode != null) {
          return false;
        }
        return true;
      };

      builder.configuration = builder.configuration.copyWith(
        blockSelectionAreaMargin: (_) => const EdgeInsets.symmetric(
          vertical: 1,
        ),
      );

      builder.actionBuilder = (context, state) {
        double top = builder.configuration.padding(context.node).top;
        final type = context.node.type;
        final level = context.node.attributes[HeadingBlockKeys.level] ?? 0;
        if ((type == HeadingBlockKeys.type ||
                type == ToggleListBlockKeys.type) &&
            level > 0) {
          final offset = [13.0, 11.0, 8.0, 6.0, 4.0, 2.0];
          top += offset[level - 1];
        } else if (type == SimpleTableBlockKeys.type) {
          top += 8.0;
        } else {
          top += 2.0;
        }
        return ValueListenableBuilder(
          valueListenable: editorState.editableNotifier,
          builder: (_, editable, child) {
            return Opacity(
              opacity: editable ? 1.0 : 0.0,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: BlockActionList(
                  blockComponentContext: context,
                  blockComponentState: state,
                  editorState: editorState,
                  blockComponentBuilder: builders,
                  actions: actions,
                  showSlashMenu: slashMenuItemsBuilder != null
                      ? () => customAppFlowySlashCommand(
                            itemsBuilder: slashMenuItemsBuilder,
                            shouldInsertSlash: false,
                            deleteKeywordsByDefault: true,
                            style: styleCustomizer.selectionMenuStyleBuilder(),
                            supportSlashMenuNodeTypes:
                                supportSlashMenuNodeTypes,
                          ).handler.call(editorState)
                      : () {},
                ),
              ),
            );
          },
        );
      };
    }
  }
}

Map<String, BlockComponentBuilder> _buildBlockComponentBuilderMap(
  BuildContext context, {
  required BlockComponentConfiguration configuration,
  required EditorState editorState,
  required EditorStyleCustomizer styleCustomizer,
  ShowPlaceholder? showParagraphPlaceholder,
  String Function(Node)? placeholderText,
  EdgeInsets? customHeadingPadding,
  bool alwaysDistributeSimpleTableColumnWidths = false,
}) {
  final customBlockComponentBuilderMap = {
    PageBlockKeys.type: PageBlockComponentBuilder(),
    ParagraphBlockKeys.type: _buildParagraphBlockComponentBuilder(
      context,
      configuration,
      showParagraphPlaceholder,
      placeholderText,
    ),
    TodoListBlockKeys.type: _buildTodoListBlockComponentBuilder(
      context,
      configuration,
    ),
    BulletedListBlockKeys.type: _buildBulletedListBlockComponentBuilder(
      context,
      configuration,
    ),
    NumberedListBlockKeys.type: _buildNumberedListBlockComponentBuilder(
      context,
      configuration,
    ),
    QuoteBlockKeys.type: _buildQuoteBlockComponentBuilder(
      context,
      configuration,
    ),
    HeadingBlockKeys.type: _buildHeadingBlockComponentBuilder(
      context,
      configuration,
      styleCustomizer,
      customHeadingPadding,
    ),
    ImageBlockKeys.type: _buildCustomImageBlockComponentBuilder(
      context,
      configuration,
    ),
    MultiImageBlockKeys.type: _buildMultiImageBlockComponentBuilder(
      context,
      configuration,
    ),
    TableBlockKeys.type: _buildTableBlockComponentBuilder(
      context,
      configuration,
    ),
    TableCellBlockKeys.type: _buildTableCellBlockComponentBuilder(
      context,
      configuration,
    ),
    DatabaseBlockKeys.gridType: _buildDatabaseViewBlockComponentBuilder(
      context,
      configuration,
    ),
    DatabaseBlockKeys.boardType: _buildDatabaseViewBlockComponentBuilder(
      context,
      configuration,
    ),
    DatabaseBlockKeys.calendarType: _buildDatabaseViewBlockComponentBuilder(
      context,
      configuration,
    ),
    CalloutBlockKeys.type: _buildCalloutBlockComponentBuilder(
      context,
      configuration,
    ),
    DividerBlockKeys.type: _buildDividerBlockComponentBuilder(
      context,
      configuration,
      editorState,
    ),
    MathEquationBlockKeys.type: _buildMathEquationBlockComponentBuilder(
      context,
      configuration,
    ),
    CodeBlockKeys.type: _buildCodeBlockComponentBuilder(
      context,
      configuration,
      styleCustomizer,
    ),
    AIWriterBlockKeys.type: _buildAIWriterBlockComponentBuilder(
      context,
      configuration,
    ),
    AskAIBlockKeys.type: _buildAskAIBlockComponentBuilder(
      context,
      configuration,
    ),
    ToggleListBlockKeys.type: _buildToggleListBlockComponentBuilder(
      context,
      configuration,
      styleCustomizer,
      customHeadingPadding,
    ),
    OutlineBlockKeys.type: _buildOutlineBlockComponentBuilder(
      context,
      configuration,
      styleCustomizer,
    ),
    LinkPreviewBlockKeys.type: _buildLinkPreviewBlockComponentBuilder(
      context,
      configuration,
    ),
    FileBlockKeys.type: _buildFileBlockComponentBuilder(
      context,
      configuration,
    ),
    SubPageBlockKeys.type: _buildSubPageBlockComponentBuilder(
      context,
      configuration,
      styleCustomizer: styleCustomizer,
    ),
    errorBlockComponentBuilderKey: ErrorBlockComponentBuilder(
      configuration: configuration,
    ),
    SimpleTableBlockKeys.type: _buildSimpleTableBlockComponentBuilder(
      context,
      configuration,
      alwaysDistributeColumnWidths: alwaysDistributeSimpleTableColumnWidths,
    ),
    SimpleTableRowBlockKeys.type: _buildSimpleTableRowBlockComponentBuilder(
      context,
      configuration,
      alwaysDistributeColumnWidths: alwaysDistributeSimpleTableColumnWidths,
    ),
    SimpleTableCellBlockKeys.type: _buildSimpleTableCellBlockComponentBuilder(
      context,
      configuration,
      alwaysDistributeColumnWidths: alwaysDistributeSimpleTableColumnWidths,
    ),
  };

  final builders = {
    ...standardBlockComponentBuilderMap,
    ...customBlockComponentBuilderMap,
  };

  return builders;
}

SimpleTableBlockComponentBuilder _buildSimpleTableBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration, {
  bool alwaysDistributeColumnWidths = false,
}) {
  final copiedConfiguration = configuration.copyWith(
    padding: (node) {
      final padding = configuration.padding(node);
      if (UniversalPlatform.isDesktop) {
        return padding;
      } else {
        return padding;
      }
    },
  );
  return SimpleTableBlockComponentBuilder(
    configuration: copiedConfiguration,
    alwaysDistributeColumnWidths: alwaysDistributeColumnWidths,
  );
}

SimpleTableRowBlockComponentBuilder _buildSimpleTableRowBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration, {
  bool alwaysDistributeColumnWidths = false,
}) {
  return SimpleTableRowBlockComponentBuilder(
    configuration: configuration,
    alwaysDistributeColumnWidths: alwaysDistributeColumnWidths,
  );
}

SimpleTableCellBlockComponentBuilder _buildSimpleTableCellBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration, {
  bool alwaysDistributeColumnWidths = false,
}) {
  return SimpleTableCellBlockComponentBuilder(
    configuration: configuration,
    alwaysDistributeColumnWidths: alwaysDistributeColumnWidths,
  );
}

ParagraphBlockComponentBuilder _buildParagraphBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  ShowPlaceholder? showParagraphPlaceholder,
  String Function(Node)? placeholderText,
) {
  return ParagraphBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderText: placeholderText,
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
    showPlaceholder: showParagraphPlaceholder,
  );
}

TodoListBlockComponentBuilder _buildTodoListBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return TodoListBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderText: (_) => LocaleKeys.blockPlaceholders_todoList.tr(),
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
    iconBuilder: (_, node, onCheck) => TodoListIcon(
      node: node,
      onCheck: onCheck,
    ),
    toggleChildrenTriggers: [
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    ],
  );
}

BulletedListBlockComponentBuilder _buildBulletedListBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return BulletedListBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderText: (_) => LocaleKeys.blockPlaceholders_bulletList.tr(),
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
    iconBuilder: (_, node) => BulletedListIcon(node: node),
  );
}

NumberedListBlockComponentBuilder _buildNumberedListBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return NumberedListBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderText: (_) => LocaleKeys.blockPlaceholders_numberList.tr(),
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
    iconBuilder: (_, node, textDirection) {
      TextStyle? textStyle;
      if (node.isInHeaderColumn || node.isInHeaderRow) {
        textStyle = configuration.textStyle(node).copyWith(
              fontWeight: FontWeight.bold,
            );
      }
      return NumberedListIcon(
        node: node,
        textDirection: textDirection,
        textStyle: textStyle,
      );
    },
  );
}

QuoteBlockComponentBuilder _buildQuoteBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return QuoteBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderText: (_) => LocaleKeys.blockPlaceholders_quote.tr(),
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
  );
}

HeadingBlockComponentBuilder _buildHeadingBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  EditorStyleCustomizer styleCustomizer,
  EdgeInsets? customHeadingPadding,
) {
  return HeadingBlockComponentBuilder(
    configuration: configuration.copyWith(
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
      padding: (node) {
        if (customHeadingPadding != null) {
          return customHeadingPadding;
        }

        if (UniversalPlatform.isMobile) {
          final pageStyle = context.read<DocumentPageStyleBloc>().state;
          final factor = pageStyle.fontLayout.factor;
          final headingPaddings =
              pageStyle.lineHeightLayout.headingPaddings.map((e) => e * factor);
          final level =
              (node.attributes[HeadingBlockKeys.level] ?? 6).clamp(1, 6);
          final top = headingPaddings.elementAt(level - 1);
          EdgeInsets edgeInsets = EdgeInsets.only(top: top);
          if (node.path.length == 1) {
            edgeInsets = edgeInsets.copyWith(
              left: EditorStyleCustomizer.nodeHorizontalPadding,
              right: EditorStyleCustomizer.nodeHorizontalPadding,
            );
          }
          return edgeInsets;
        }

        return const EdgeInsets.only(top: 12.0, bottom: 4.0);
      },
      placeholderText: (node) {
        int level = node.attributes[HeadingBlockKeys.level] ?? 6;
        level = level.clamp(1, 6);
        return LocaleKeys.blockPlaceholders_heading.tr(
          args: [level.toString()],
        );
      },
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
    ),
    textStyleBuilder: (level) {
      return styleCustomizer.headingStyleBuilder(level);
    },
  );
}

CustomImageBlockComponentBuilder _buildCustomImageBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return CustomImageBlockComponentBuilder(
    configuration: configuration,
    showMenu: true,
    menuBuilder: (node, state, imageStateNotifier) => Positioned(
      top: 10,
      right: 10,
      child: ImageMenu(
        node: node,
        state: state,
        imageStateNotifier: imageStateNotifier,
      ),
    ),
  );
}

MultiImageBlockComponentBuilder _buildMultiImageBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return MultiImageBlockComponentBuilder(
    configuration: configuration,
    showMenu: true,
    menuBuilder: (
      Node node,
      MultiImageBlockComponentState state,
      ValueNotifier<int> indexNotifier,
      VoidCallback onImageDeleted,
    ) =>
        Positioned(
      top: 10,
      right: 10,
      child: MultiImageMenu(
        node: node,
        state: state,
        indexNotifier: indexNotifier,
        isLocalMode: context.read<DocumentBloc>().isLocalMode,
        onImageDeleted: onImageDeleted,
      ),
    ),
  );
}

TableBlockComponentBuilder _buildTableBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return TableBlockComponentBuilder(
    menuBuilder: (node, editorState, position, dir, onBuild, onClose) =>
        TableMenu(
      node: node,
      editorState: editorState,
      position: position,
      dir: dir,
      onBuild: onBuild,
      onClose: onClose,
    ),
  );
}

TableCellBlockComponentBuilder _buildTableCellBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return TableCellBlockComponentBuilder(
    colorBuilder: (context, node) {
      final String colorString =
          node.attributes[TableCellBlockKeys.colBackgroundColor] ??
              node.attributes[TableCellBlockKeys.rowBackgroundColor] ??
              '';
      if (colorString.isEmpty) {
        return null;
      }
      return buildEditorCustomizedColor(context, node, colorString);
    },
    menuBuilder: (node, editorState, position, dir, onBuild, onClose) =>
        TableMenu(
      node: node,
      editorState: editorState,
      position: position,
      dir: dir,
      onBuild: onBuild,
      onClose: onClose,
    ),
  );
}

DatabaseViewBlockComponentBuilder _buildDatabaseViewBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return DatabaseViewBlockComponentBuilder(
    configuration: configuration.copyWith(
      padding: (node) {
        if (UniversalPlatform.isMobile) {
          return configuration.padding(node);
        }
        return const EdgeInsets.symmetric(vertical: 10);
      },
    ),
  );
}

CalloutBlockComponentBuilder _buildCalloutBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  final calloutBGColor = AFThemeExtension.of(context).calloutBGColor;
  return CalloutBlockComponentBuilder(
    configuration: configuration.copyWith(
      padding: (node) {
        if (UniversalPlatform.isMobile) {
          return configuration.padding(node);
        }
        return const EdgeInsets.symmetric(vertical: 10);
      },
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
      textStyle: (node, {TextSpan? textSpan}) => _buildTextStyleInTableCell(
        context,
        node: node,
        configuration: configuration,
        textSpan: textSpan,
      ),
    ),
    inlinePadding: const EdgeInsets.symmetric(vertical: 8.0),
    defaultColor: calloutBGColor,
  );
}

DividerBlockComponentBuilder _buildDividerBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  EditorState editorState,
) {
  return DividerBlockComponentBuilder(
    configuration: configuration,
    height: 28.0,
    wrapper: (_, node, child) => MobileBlockActionButtons(
      showThreeDots: false,
      node: node,
      editorState: editorState,
      child: child,
    ),
  );
}

MathEquationBlockComponentBuilder _buildMathEquationBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return MathEquationBlockComponentBuilder(
    configuration: configuration,
  );
}

CodeBlockComponentBuilder _buildCodeBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  EditorStyleCustomizer styleCustomizer,
) {
  return CodeBlockComponentBuilder(
    styleBuilder: styleCustomizer.codeBlockStyleBuilder,
    configuration: configuration,
    padding: const EdgeInsets.only(left: 20, right: 30, bottom: 34),
    languagePickerBuilder: codeBlockLanguagePickerBuilder,
    copyButtonBuilder: codeBlockCopyBuilder,
  );
}

AIWriterBlockComponentBuilder _buildAIWriterBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return AIWriterBlockComponentBuilder();
}

AskAIBlockComponentBuilder _buildAskAIBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return AskAIBlockComponentBuilder();
}

ToggleListBlockComponentBuilder _buildToggleListBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  EditorStyleCustomizer styleCustomizer,
  EdgeInsets? customHeadingPadding,
) {
  return ToggleListBlockComponentBuilder(
    configuration: configuration.copyWith(
      padding: (node) {
        if (customHeadingPadding != null) {
          return customHeadingPadding;
        }

        if (UniversalPlatform.isMobile) {
          final pageStyle = context.read<DocumentPageStyleBloc>().state;
          final factor = pageStyle.fontLayout.factor;
          final headingPaddings =
              pageStyle.lineHeightLayout.headingPaddings.map((e) => e * factor);
          final level =
              (node.attributes[HeadingBlockKeys.level] ?? 6).clamp(1, 6);
          final top = headingPaddings.elementAt(level - 1);
          return configuration.padding(node).copyWith(top: top);
        }

        return const EdgeInsets.only(top: 12.0, bottom: 4.0);
      },
      textStyle: (node, {TextSpan? textSpan}) {
        final textStyle = _buildTextStyleInTableCell(
          context,
          node: node,
          configuration: configuration,
          textSpan: textSpan,
        );
        final level = node.attributes[ToggleListBlockKeys.level] as int?;
        if (level == null) {
          return textStyle;
        }
        return textStyle.merge(styleCustomizer.headingStyleBuilder(level));
      },
      textAlign: (node) => _buildTextAlignInTableCell(
        context,
        node: node,
        configuration: configuration,
      ),
      placeholderText: (node) {
        int? level = node.attributes[ToggleListBlockKeys.level];
        if (level == null) {
          return configuration.placeholderText(node);
        }
        level = level.clamp(1, 6);
        return LocaleKeys.blockPlaceholders_heading.tr(
          args: [level.toString()],
        );
      },
    ),
    textStyleBuilder: (level) => styleCustomizer.headingStyleBuilder(level),
  );
}

OutlineBlockComponentBuilder _buildOutlineBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
  EditorStyleCustomizer styleCustomizer,
) {
  return OutlineBlockComponentBuilder(
    configuration: configuration.copyWith(
      placeholderTextStyle: (node, {TextSpan? textSpan}) =>
          styleCustomizer.outlineBlockPlaceholderStyleBuilder(),
      padding: (node) {
        if (UniversalPlatform.isMobile) {
          return configuration.padding(node);
        }
        return const EdgeInsets.only(top: 12.0, bottom: 4.0);
      },
    ),
  );
}

LinkPreviewBlockComponentBuilder _buildLinkPreviewBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return LinkPreviewBlockComponentBuilder(
    configuration: configuration.copyWith(
      padding: (node) {
        if (UniversalPlatform.isMobile) {
          return configuration.padding(node);
        }
        return const EdgeInsets.symmetric(vertical: 10);
      },
    ),
    cache: LinkPreviewDataCache(),
    showMenu: true,
    menuBuilder: (context, node, state) => Positioned(
      top: 10,
      right: 0,
      child: LinkPreviewMenu(node: node, state: state),
    ),
    builder: (_, node, url, title, description, imageUrl) =>
        CustomLinkPreviewWidget(
      node: node,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
    ),
  );
}

FileBlockComponentBuilder _buildFileBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration,
) {
  return FileBlockComponentBuilder(
    configuration: configuration,
  );
}

SubPageBlockComponentBuilder _buildSubPageBlockComponentBuilder(
  BuildContext context,
  BlockComponentConfiguration configuration, {
  required EditorStyleCustomizer styleCustomizer,
}) {
  return SubPageBlockComponentBuilder(
    configuration: configuration.copyWith(
      textStyle: (node, {TextSpan? textSpan}) =>
          styleCustomizer.subPageBlockTextStyleBuilder(),
      padding: (node) {
        if (UniversalPlatform.isMobile) {
          return const EdgeInsets.symmetric(horizontal: 18);
        }
        return configuration.padding(node);
      },
    ),
  );
}

TextStyle _buildTextStyleInTableCell(
  BuildContext context, {
  required Node node,
  required BlockComponentConfiguration configuration,
  required TextSpan? textSpan,
}) {
  TextStyle textStyle = configuration.textStyle(node, textSpan: textSpan);

  if (node.isInHeaderColumn ||
      node.isInHeaderRow ||
      node.isInBoldColumn ||
      node.isInBoldRow) {
    textStyle = textStyle.copyWith(
      fontWeight: FontWeight.bold,
    );
  }

  final cellTextColor = node.textColorInColumn ?? node.textColorInRow;

  // enable it if we need to support the text color of the text span
  // final isTextSpanColorNull = textSpan?.style?.color == null;
  // final isTextSpanChildrenColorNull =
  //     textSpan?.children?.every((e) => e.style?.color == null) ?? true;

  if (cellTextColor != null) {
    textStyle = textStyle.copyWith(
      color: buildEditorCustomizedColor(
        context,
        node,
        cellTextColor,
      ),
    );
  }

  return textStyle;
}

TextAlign _buildTextAlignInTableCell(
  BuildContext context, {
  required Node node,
  required BlockComponentConfiguration configuration,
}) {
  final isInTable = node.isInTable;
  if (!isInTable) {
    return configuration.textAlign(node);
  }

  return node.tableAlign.textAlign;
}
