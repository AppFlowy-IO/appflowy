import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/font_colors.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mobile_toolbar_item/utils.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/workspace/application/appearance_defaults.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universal_platform/universal_platform.dart';

class EditorStyleCustomizer {
  EditorStyleCustomizer({
    required this.context,
    required this.padding,
    this.width,
    this.editorState,
  });

  final BuildContext context;
  final EdgeInsets padding;
  final double? width;
  final EditorState? editorState;

  static const double maxDocumentWidth = 480 * 4;
  static const double minDocumentWidth = 480;

  static EdgeInsets get documentPadding => UniversalPlatform.isMobile
      ? EdgeInsets.zero
      : EdgeInsets.only(
          left: 40,
          right: 40 + EditorStyleCustomizer.optionMenuWidth,
        );

  static double get nodeHorizontalPadding =>
      UniversalPlatform.isMobile ? 24 : 0;

  static EdgeInsets get documentPaddingWithOptionMenu =>
      documentPadding + EdgeInsets.only(left: optionMenuWidth);

  static double get optionMenuWidth => UniversalPlatform.isMobile ? 0 : 44;

  EditorStyle style() {
    if (UniversalPlatform.isDesktopOrWeb) {
      return desktop();
    } else if (UniversalPlatform.isMobile) {
      return mobile();
    }
    throw UnimplementedError();
  }

  EditorStyle desktop() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    final appearanceFont = context.read<AppearanceSettingsCubit>().state.font;
    final appearance = context.read<DocumentAppearanceCubit>().state;
    final fontSize = appearance.fontSize;
    String fontFamily = appearance.fontFamily;
    if (fontFamily.isEmpty && appearanceFont.isNotEmpty) {
      fontFamily = appearanceFont;
    }

    final cursorColor = (editorState?.editable ?? true)
        ? (appearance.cursorColor ??
            DefaultAppearanceSettings.getDefaultCursorColor(context))
        : Colors.transparent;

    return EditorStyle.desktop(
      padding: padding,
      maxWidth: width,
      cursorColor: cursorColor,
      selectionColor: appearance.selectionColor ??
          DefaultAppearanceSettings.getDefaultSelectionColor(context),
      defaultTextDirection: appearance.defaultTextDirection,
      textStyleConfiguration: TextStyleConfiguration(
        lineHeight: 1.4,
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
        text: baseTextStyle(fontFamily).copyWith(
          fontSize: fontSize,
          color: afThemeExtension.onBackground,
        ),
        bold: baseTextStyle(fontFamily, fontWeight: FontWeight.bold).copyWith(
          fontWeight: FontWeight.w600,
        ),
        italic: baseTextStyle(fontFamily).copyWith(fontStyle: FontStyle.italic),
        underline: baseTextStyle(fontFamily).copyWith(
          decoration: TextDecoration.underline,
        ),
        strikethrough: baseTextStyle(fontFamily).copyWith(
          decoration: TextDecoration.lineThrough,
        ),
        href: baseTextStyle(fontFamily).copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: GoogleFonts.robotoMono(
          textStyle: baseTextStyle(fontFamily).copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.normal,
            color: Colors.red,
            backgroundColor:
                theme.colorScheme.inverseSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      textSpanDecorator: customizeAttributeDecorator,
      textScaleFactor:
          context.watch<AppearanceSettingsCubit>().state.textScaleFactor,
    );
  }

  EditorStyle mobile() {
    final afThemeExtension = AFThemeExtension.of(context);
    final pageStyle = context.read<DocumentPageStyleBloc>().state;
    final theme = Theme.of(context);
    final fontSize = pageStyle.fontLayout.fontSize;
    final lineHeight = pageStyle.lineHeightLayout.lineHeight;
    final fontFamily = pageStyle.fontFamily ??
        context.read<AppearanceSettingsCubit>().state.font;
    final defaultTextDirection =
        context.read<DocumentAppearanceCubit>().state.defaultTextDirection;
    final textScaleFactor =
        context.read<AppearanceSettingsCubit>().state.textScaleFactor;
    final baseTextStyle = this.baseTextStyle(fontFamily);

    return EditorStyle.mobile(
      padding: padding,
      defaultTextDirection: defaultTextDirection,
      textStyleConfiguration: TextStyleConfiguration(
        lineHeight: lineHeight,
        text: baseTextStyle.copyWith(
          fontSize: fontSize,
          color: afThemeExtension.onBackground,
        ),
        bold: baseTextStyle.copyWith(fontWeight: FontWeight.w600),
        italic: baseTextStyle.copyWith(fontStyle: FontStyle.italic),
        underline: baseTextStyle.copyWith(decoration: TextDecoration.underline),
        strikethrough: baseTextStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        ),
        href: baseTextStyle.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: GoogleFonts.robotoMono(
          textStyle: baseTextStyle.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.normal,
            color: Colors.red,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      textSpanDecorator: customizeAttributeDecorator,
      magnifierSize: const Size(144, 96),
      textScaleFactor: textScaleFactor,
      mobileDragHandleLeftExtend: 12.0,
      mobileDragHandleWidthExtend: 24.0,
    );
  }

  TextStyle headingStyleBuilder(int level) {
    final String? fontFamily;
    final List<double> fontSizes;
    final double fontSize;
    if (UniversalPlatform.isMobile) {
      final state = context.read<DocumentPageStyleBloc>().state;
      fontFamily = state.fontFamily;
      fontSize = state.fontLayout.fontSize;
      fontSizes = state.fontLayout.headingFontSizes;
    } else {
      fontFamily = context.read<DocumentAppearanceCubit>().state.fontFamily;
      fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      fontSizes = [
        fontSize + 16,
        fontSize + 12,
        fontSize + 8,
        fontSize + 4,
        fontSize + 2,
        fontSize,
      ];
    }
    return baseTextStyle(fontFamily, fontWeight: FontWeight.w600).copyWith(
      fontSize: fontSizes.elementAtOrNull(level - 1) ?? fontSize,
    );
  }

  CodeBlockStyle codeBlockStyleBuilder() {
    final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
    final fontFamily =
        context.read<DocumentAppearanceCubit>().state.codeFontFamily;

    return CodeBlockStyle(
      textStyle: baseTextStyle(fontFamily).copyWith(
        fontSize: fontSize,
        height: 1.5,
        color: AFThemeExtension.of(context).onBackground,
      ),
      backgroundColor: AFThemeExtension.of(context).calloutBGColor,
      foregroundColor: AFThemeExtension.of(context).textColor.withAlpha(155),
    );
  }

  TextStyle calloutBlockStyleBuilder() {
    if (UniversalPlatform.isMobile) {
      final afThemeExtension = AFThemeExtension.of(context);
      final pageStyle = context.read<DocumentPageStyleBloc>().state;
      final fontSize = pageStyle.fontLayout.fontSize;
      final fontFamily = pageStyle.fontFamily ?? defaultFontFamily;
      final baseTextStyle = this.baseTextStyle(fontFamily);
      return baseTextStyle.copyWith(
        fontSize: fontSize,
        color: afThemeExtension.onBackground,
      );
    } else {
      final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      return baseTextStyle(null).copyWith(
        fontSize: fontSize,
        height: 1.5,
      );
    }
  }

  TextStyle outlineBlockPlaceholderStyleBuilder() {
    final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
    return TextStyle(
      fontFamily: defaultFontFamily,
      fontSize: fontSize,
      height: 1.5,
      color: AFThemeExtension.of(context).onBackground.withValues(alpha: 0.6),
    );
  }

  TextStyle subPageBlockTextStyleBuilder() {
    if (UniversalPlatform.isMobile) {
      final pageStyle = context.read<DocumentPageStyleBloc>().state;
      final fontSize = pageStyle.fontLayout.fontSize;
      final fontFamily = pageStyle.fontFamily ?? defaultFontFamily;
      final baseTextStyle = this.baseTextStyle(fontFamily);
      return baseTextStyle.copyWith(
        fontSize: fontSize,
      );
    } else {
      final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      return baseTextStyle(null).copyWith(
        fontSize: fontSize,
        height: 1.5,
      );
    }
  }

  SelectionMenuStyle selectionMenuStyleBuilder() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    return SelectionMenuStyle(
      selectionMenuBackgroundColor: theme.cardColor,
      selectionMenuItemTextColor: afThemeExtension.onBackground,
      selectionMenuItemIconColor: afThemeExtension.onBackground,
      selectionMenuItemSelectedIconColor: theme.colorScheme.onSurface,
      selectionMenuItemSelectedTextColor: theme.colorScheme.onSurface,
      selectionMenuItemSelectedColor: afThemeExtension.greyHover,
    );
  }

  InlineActionsMenuStyle inlineActionsMenuStyleBuilder() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    return InlineActionsMenuStyle(
      backgroundColor: theme.cardColor,
      groupTextColor: afThemeExtension.onBackground.withValues(alpha: .8),
      menuItemTextColor: afThemeExtension.onBackground,
      menuItemSelectedColor: theme.colorScheme.secondary,
      menuItemSelectedTextColor: theme.colorScheme.onSurface,
    );
  }

  FloatingToolbarStyle floatingToolbarStyleBuilder() => FloatingToolbarStyle(
        backgroundColor: Theme.of(context).colorScheme.onTertiary,
      );

  TextStyle baseTextStyle(String? fontFamily, {FontWeight? fontWeight}) {
    if (fontFamily == null || fontFamily == defaultFontFamily) {
      return TextStyle(fontWeight: fontWeight);
    }
    try {
      return getGoogleFontSafely(fontFamily, fontWeight: fontWeight);
    } on Exception {
      if ([defaultFontFamily, builtInCodeFontFamily].contains(fontFamily)) {
        return TextStyle(fontFamily: fontFamily, fontWeight: fontWeight);
      }

      return TextStyle(fontWeight: fontWeight);
    }
  }

  InlineSpan customizeAttributeDecorator(
    BuildContext context,
    Node node,
    int index,
    TextInsert text,
    TextSpan before,
    TextSpan after,
  ) {
    final attributes = text.attributes;
    if (attributes == null) {
      return before;
    }

    if (attributes.backgroundColor != null) {
      final color = EditorFontColors.fromBuiltInColors(
        context,
        attributes.backgroundColor!,
      );
      if (color != null) {
        return TextSpan(
          text: before.text,
          style: after.style?.merge(
            TextStyle(backgroundColor: color),
          ),
        );
      }
    }

    // try to refresh font here.
    if (attributes.fontFamily != null) {
      try {
        if (before.text?.contains('_regular') == true) {
          getGoogleFontSafely(attributes.fontFamily!.parseFontFamilyName());
        } else {
          return TextSpan(
            text: before.text,
            style: after.style?.merge(
              getGoogleFontSafely(attributes.fontFamily!),
            ),
          );
        }
      } catch (_) {
        // ignore
      }
    }

    // Inline Mentions (Page Reference, Date, Reminder, etc.)
    final mention =
        attributes[MentionBlockKeys.mention] as Map<String, dynamic>?;
    if (mention != null) {
      final type = mention[MentionBlockKeys.type];
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: after.style,
        child: MentionBlock(
          key: ValueKey(
            switch (type) {
              MentionType.page => mention[MentionBlockKeys.pageId],
              MentionType.date => mention[MentionBlockKeys.date],
              _ => MentionBlockKeys.mention,
            },
          ),
          node: node,
          index: index,
          mention: mention,
          textStyle: after.style,
        ),
      );
    }

    // customize the inline math equation block
    final formula = attributes[InlineMathEquationKeys.formula];
    if (formula is String) {
      return WidgetSpan(
        style: after.style,
        alignment: PlaceholderAlignment.middle,
        child: InlineMathEquation(
          node: node,
          index: index,
          formula: formula,
          textStyle: after.style ?? style().textStyleConfiguration.text,
        ),
      );
    }

    // customize the link on mobile
    final href = attributes[AppFlowyRichTextKeys.href] as String?;
    if (UniversalPlatform.isMobile && href != null) {
      return TextSpan(
        style: before.style,
        text: text.text,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            final editorState = context.read<EditorState>();
            if (editorState.selection == null) {
              afLaunchUrlString(href, addingHttpSchemeWhenFailed: true);
              return;
            }

            editorState.updateSelectionWithReason(
              editorState.selection,
              extraInfo: {selectionExtraInfoDisableMobileToolbarKey: true},
            );

            showEditLinkBottomSheet(
              context,
              text.text,
              href,
              (linkContext, newText, newHref) {
                final selection = Selection.single(
                  path: node.path,
                  startOffset: index,
                  endOffset: index + text.text.length,
                );
                editorState.updateTextAndHref(
                  text.text,
                  href,
                  newText,
                  newHref,
                  selection: selection,
                );
                linkContext.pop();
              },
            );
          },
      );
    }

    return defaultTextSpanDecoratorForAttribute(
      context,
      node,
      index,
      text,
      before,
      after,
    );
  }

  Widget buildToolbarItemTooltip(
    BuildContext context,
    String id,
    String message,
    Widget child,
  ) {
    final tooltipMessage = _buildTooltipMessage(id, message);
    child = FlowyTooltip(
      richMessage: tooltipMessage,
      preferBelow: false,
      verticalOffset: 20,
      child: child,
    );

    // the align/font toolbar item doesn't need the hover effect
    final toolbarItemsWithoutHover = {
      kFontToolbarItemId,
      kAlignToolbarItemId,
    };

    if (!toolbarItemsWithoutHover.contains(id)) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: FlowyHover(
          style: HoverStyle(
            hoverColor: Colors.grey.withValues(alpha: 0.3),
          ),
          child: child,
        ),
      );
    }

    return child;
  }

  TextSpan _buildTooltipMessage(String id, String message) {
    final markdownItemTooltips = {
      'underline': (LocaleKeys.toolbar_underline.tr(), 'U'),
      'bold': (LocaleKeys.toolbar_bold.tr(), 'B'),
      'italic': (LocaleKeys.toolbar_italic.tr(), 'I'),
      'strikethrough': (LocaleKeys.toolbar_strike.tr(), 'Shift+S'),
      'code': (LocaleKeys.toolbar_inlineCode.tr(), 'E'),
    };

    final markdownItemIds = markdownItemTooltips.keys.toSet();
    // the items without shortcuts
    if (!markdownItemIds.contains(id)) {
      return TextSpan(
        text: message,
        style: context.tooltipTextStyle(),
      );
    }

    final tooltip = markdownItemTooltips[id];
    if (tooltip == null) {
      return TextSpan(
        text: message,
        style: context.tooltipTextStyle(),
      );
    }

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: '${tooltip.$1}\n',
          style: context.tooltipTextStyle(),
        ),
        TextSpan(
          text: (Platform.isMacOS ? '⌘+' : 'Ctrl+\\') + tooltip.$2,
          style: context
              .tooltipTextStyle()
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
      ],
    );

    return textSpan;
  }
}
