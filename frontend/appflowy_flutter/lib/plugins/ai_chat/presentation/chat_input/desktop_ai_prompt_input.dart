import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/ai_prompt_input_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_control_cubit.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../layout_define.dart';
import 'ai_prompt_buttons.dart';
import 'chat_input_file.dart';
import 'chat_input_span.dart';
import 'chat_mention_page_menu.dart';
import 'select_sources_menu.dart';

class DesktopAIPromptInput extends StatefulWidget {
  const DesktopAIPromptInput({
    super.key,
    required this.chatId,
    required this.isStreaming,
    required this.onStopStreaming,
    required this.onSubmitted,
    required this.onUpdateSelectedSources,
  });

  final String chatId;
  final bool isStreaming;
  final void Function() onStopStreaming;
  final void Function(String, Map<String, dynamic>) onSubmitted;
  final void Function(bool, List<String>) onUpdateSelectedSources;

  @override
  State<DesktopAIPromptInput> createState() => _DesktopAIPromptInputState();
}

class _DesktopAIPromptInputState extends State<DesktopAIPromptInput> {
  final textFieldKey = GlobalKey();
  final layerLink = LayerLink();
  final overlayController = OverlayPortalController();
  final inputControlCubit = ChatInputControlCubit();
  final focusNode = FocusNode();
  final textController = TextEditingController();

  late SendButtonState sendButtonState;

  @override
  void initState() {
    super.initState();

    textController.addListener(handleTextControllerChanged);

    // refresh border color on focus change and hide menu when lost focus
    focusNode.addListener(
      () => setState(() {
        if (!focusNode.hasFocus) {
          cancelMentionPage();
        }
      }),
    );

    updateSendButtonState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    updateSendButtonState();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    focusNode.dispose();
    textController.dispose();
    inputControlCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: inputControlCubit,
      child: BlocListener<ChatInputControlCubit, ChatInputControlState>(
        listener: (context, state) {
          state.maybeWhen(
            updateSelectedViews: (selectedViews) {
              context
                  .read<AIPromptInputBloc>()
                  .add(AIPromptInputEvent.updateMentionedViews(selectedViews));
            },
            orElse: () {},
          );
        },
        child: OverlayPortal(
          controller: overlayController,
          overlayChildBuilder: (context) {
            return ChatMentionPageMenu(
              anchor: ChatInputAnchor(textFieldKey, layerLink),
              textController: textController,
              onPageSelected: handlePageSelected,
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: focusNode.hasFocus
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
                width: focusNode.hasFocus ? 1.5 : 1.0,
              ),
              borderRadius: DesktopAIPromptSizes.promptFrameRadius,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        DesktopAIPromptSizes.attachedFilesBarPadding.vertical +
                            DesktopAIPromptSizes.attachedFilesPreviewHeight,
                  ),
                  child: TextFieldTapRegion(
                    child: ChatInputFile(
                      chatId: widget.chatId,
                      onDeleted: (file) => context
                          .read<AIPromptInputBloc>()
                          .add(AIPromptInputEvent.removeFile(file)),
                    ),
                  ),
                ),
                Stack(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: DesktopAIPromptSizes.textFieldMinHeight +
                            DesktopAIPromptSizes.actionBarHeight +
                            DesktopAIPromptSizes.actionBarPadding.vertical,
                        maxHeight: 300,
                      ),
                      child: inputTextField(),
                    ),
                    Positioned.fill(
                      top: null,
                      child: TextFieldTapRegion(
                        child: _PromptBottomActions(
                          textController: textController,
                          overlayController: overlayController,
                          focusNode: focusNode,
                          sendButtonState: sendButtonState,
                          onSendPressed: handleSendPressed,
                          onStopStreaming: widget.onStopStreaming,
                          onUpdateSelectedSources:
                              widget.onUpdateSelectedSources,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void cancelMentionPage() {
    if (overlayController.isShowing) {
      inputControlCubit.reset();
      overlayController.hide();
    }
  }

  void updateSendButtonState() {
    if (widget.isStreaming) {
      sendButtonState = SendButtonState.streaming;
    } else if (textController.text.trim().isEmpty) {
      sendButtonState = SendButtonState.disabled;
    } else {
      sendButtonState = SendButtonState.enabled;
    }
  }

  void handleSendPressed() {
    if (widget.isStreaming) {
      return;
    }
    final trimmedText = inputControlCubit.formatIntputText(
      textController.text.trim(),
    );
    textController.clear();
    if (trimmedText.isEmpty) {
      return;
    }

    // get the attached files and mentioned pages
    final metadata = context.read<AIPromptInputBloc>().consumeMetadata();

    widget.onSubmitted(trimmedText, metadata);
  }

  void handleTextControllerChanged() {
    if (!textController.value.composing.isCollapsed) {
      return;
    }

    // update whether send button is clickable
    setState(() => updateSendButtonState());

    // handle text and selection changes ONLY when mentioning a page

    // disable mention
    return;
    // ignore: dead_code
    if (!overlayController.isShowing ||
        inputControlCubit.filterStartPosition == -1) {
      return;
    }

    // handle cases where mention a page is cancelled
    final textSelection = textController.value.selection;
    final isSelectingMultipleCharacters = !textSelection.isCollapsed;
    final isCaretBeforeStartOfRange =
        textSelection.baseOffset < inputControlCubit.filterStartPosition;
    final isCaretAfterEndOfRange =
        textSelection.baseOffset > inputControlCubit.filterEndPosition;
    final isTextSame = inputControlCubit.inputText == textController.text;

    if (isSelectingMultipleCharacters ||
        isTextSame && (isCaretBeforeStartOfRange || isCaretAfterEndOfRange)) {
      cancelMentionPage();
      return;
    }

    final previousLength = inputControlCubit.inputText.characters.length;
    final currentLength = textController.text.characters.length;

    // delete "@"
    if (previousLength != currentLength && isCaretBeforeStartOfRange) {
      cancelMentionPage();
      return;
    }

    // handle cases where mention the filter is updated
    if (previousLength != currentLength) {
      final diff = currentLength - previousLength;
      final newEndPosition = inputControlCubit.filterEndPosition + diff;
      final newFilter = textController.text.substring(
        inputControlCubit.filterStartPosition,
        newEndPosition,
      );
      inputControlCubit.updateFilter(
        textController.text,
        newFilter,
        newEndPosition: newEndPosition,
      );
    } else if (!isTextSame) {
      final newFilter = textController.text.substring(
        inputControlCubit.filterStartPosition,
        inputControlCubit.filterEndPosition,
      );
      inputControlCubit.updateFilter(textController.text, newFilter);
    }
  }

  void handlePageSelected(ViewPB view) {
    final newText = textController.text.replaceRange(
      inputControlCubit.filterStartPosition,
      inputControlCubit.filterEndPosition,
      view.id,
    );
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: inputControlCubit.filterStartPosition + view.id.length,
        affinity: TextAffinity.upstream,
      ),
    );

    inputControlCubit.selectPage(view);
    overlayController.hide();
  }

  Widget inputTextField() {
    return Actions(
      actions: buildActions(),
      child: CompositedTransformTarget(
        link: layerLink,
        child: BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
          builder: (context, state) {
            return _PromptTextField(
              key: textFieldKey,
              cubit: inputControlCubit,
              textController: textController,
              textFieldFocusNode: focusNode,
              hintText: switch (state.aiType) {
                AIType.appflowyAI => LocaleKeys.chat_inputMessageHint.tr(),
                AIType.localAI => LocaleKeys.chat_inputLocalAIMessageHint.tr()
              },
              // onStartMentioningPage: () {
              //   WidgetsBinding.instance.addPostFrameCallback((_) {
              //     inputControlCubit.startSearching(textController.value);
              //     overlayController.show();
              //   });
              // },
            );
          },
        ),
      ),
    );
  }

  Map<Type, Action<Intent>> buildActions() {
    return {
      _FocusPreviousItemIntent: CallbackAction<_FocusPreviousItemIntent>(
        onInvoke: (intent) {
          inputControlCubit.updateSelectionUp();
          return;
        },
      ),
      _FocusNextItemIntent: CallbackAction<_FocusNextItemIntent>(
        onInvoke: (intent) {
          inputControlCubit.updateSelectionDown();
          return;
        },
      ),
      _CancelMentionPageIntent: CallbackAction<_CancelMentionPageIntent>(
        onInvoke: (intent) {
          cancelMentionPage();
          return;
        },
      ),
      _SubmitOrMentionPageIntent: CallbackAction<_SubmitOrMentionPageIntent>(
        onInvoke: (intent) {
          if (overlayController.isShowing) {
            inputControlCubit.state.maybeWhen(
              ready: (visibleViews, focusedViewIndex) {
                if (focusedViewIndex != -1 &&
                    focusedViewIndex < visibleViews.length) {
                  handlePageSelected(visibleViews[focusedViewIndex]);
                }
              },
              orElse: () {},
            );
          } else {
            handleSendPressed();
          }
          return;
        },
      ),
    };
  }
}

class _PromptTextField extends StatefulWidget {
  const _PromptTextField({
    super.key,
    required this.cubit,
    required this.textController,
    required this.textFieldFocusNode,
    // required this.onStartMentioningPage,
    this.hintText = "",
  });

  final ChatInputControlCubit cubit;
  final TextEditingController textController;
  final FocusNode textFieldFocusNode;
  // final void Function() onStartMentioningPage;
  final String hintText;

  @override
  State<_PromptTextField> createState() => _PromptTextFieldState();
}

class _PromptTextFieldState extends State<_PromptTextField> {
  bool isComposing = false;

  @override
  void initState() {
    super.initState();
    // widget.textFieldFocusNode.onKeyEvent = handleKeyEvent;
    widget.textController.addListener(onTextChanged);
  }

  @override
  void dispose() {
    // widget.textFieldFocusNode.onKeyEvent = null;
    widget.textController.removeListener(onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: buildShortcuts(),
      child: ExtendedTextField(
        controller: widget.textController,
        focusNode: widget.textFieldFocusNode,
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: DesktopAIPromptSizes.textFieldContentPadding.add(
            const EdgeInsets.only(
              bottom: DesktopAIPromptSizes.actionBarHeight,
            ),
          ),
          hintText: widget.hintText,
          hintStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).hintColor),
          isCollapsed: true,
          isDense: true,
        ),
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 1,
        maxLines: null,
        style: Theme.of(context).textTheme.bodyMedium,
        specialTextSpanBuilder: ChatInputTextSpanBuilder(
          inputControlCubit: widget.cubit,
          specialTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  // KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
  //   if (event.character == '@') {
  //     widget.onStartMentioningPage();
  //   }
  //   return KeyEventResult.ignored;
  // }

  void onTextChanged() {
    setState(
      () => isComposing = !widget.textController.value.composing.isCollapsed,
    );
  }

  Map<ShortcutActivator, Intent> buildShortcuts() {
    if (isComposing) {
      return const {};
    }

    return const {
      SingleActivator(LogicalKeyboardKey.arrowUp): _FocusPreviousItemIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown): _FocusNextItemIntent(),
      SingleActivator(LogicalKeyboardKey.escape): _CancelMentionPageIntent(),
      SingleActivator(LogicalKeyboardKey.enter): _SubmitOrMentionPageIntent(),
    };
  }
}

class _SubmitOrMentionPageIntent extends Intent {
  const _SubmitOrMentionPageIntent();
}

class _CancelMentionPageIntent extends Intent {
  const _CancelMentionPageIntent();
}

class _FocusPreviousItemIntent extends Intent {
  const _FocusPreviousItemIntent();
}

class _FocusNextItemIntent extends Intent {
  const _FocusNextItemIntent();
}

class _PromptBottomActions extends StatelessWidget {
  const _PromptBottomActions({
    required this.textController,
    required this.overlayController,
    required this.focusNode,
    required this.sendButtonState,
    required this.onSendPressed,
    required this.onStopStreaming,
    required this.onUpdateSelectedSources,
  });

  final TextEditingController textController;
  final OverlayPortalController overlayController;
  final FocusNode focusNode;
  final SendButtonState sendButtonState;
  final void Function() onSendPressed;
  final void Function() onStopStreaming;
  final void Function(bool, List<String>) onUpdateSelectedSources;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesktopAIPromptSizes.actionBarHeight,
      margin: DesktopAIPromptSizes.actionBarPadding,
      child: BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
        builder: (context, state) {
          return Row(
            children: [
              // predefinedFormatButton(),
              const Spacer(),
              if (state.aiType == AIType.appflowyAI) ...[
                _selectSourcesButton(context),
                const HSpace(
                  DesktopAIPromptSizes.actionBarButtonSpacing,
                ),
              ],
              // _mentionButton(context),
              // const HSpace(
              //   DesktopAIPromptSizes.actionBarButtonSpacing,
              // ),
              if (state.supportChatWithFile) ...[
                _attachmentButton(context),
                const HSpace(
                  DesktopAIPromptSizes.actionBarButtonSpacing,
                ),
              ],
              _sendButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _selectSourcesButton(BuildContext context) {
    return PromptInputDesktopSelectSourcesButton(
      onUpdateSelectedSources: onUpdateSelectedSources,
    );
  }

  // Widget _mentionButton(BuildContext context) {
  //   return PromptInputMentionButton(
  //     iconSize: DesktopAIPromptSizes.actionBarIconSize,
  //     buttonSize: DesktopAIPromptSizes.actionBarButtonSize,
  //     onTap: () {
  //       if (overlayController.isShowing) {
  //         return;
  //       }
  //       if (!focusNode.hasFocus) {
  //         focusNode.requestFocus();
  //       }
  //       textController.text += '@';
  //       Future.delayed(Duration.zero, () {
  //         context
  //             .read<ChatInputControlCubit>()
  //             .startSearching(textController.value);
  //         overlayController.show();
  //       });
  //     },
  //   );
  // }

  Widget _attachmentButton(BuildContext context) {
    return PromptInputAttachmentButton(
      onTap: () async {
        final path = await getIt<FilePickerService>().pickFiles(
          dialogTitle: '',
          type: FileType.custom,
          allowedExtensions: ["pdf", "txt", "md"],
        );

        if (path == null) {
          return;
        }

        for (final file in path.files) {
          if (file.path != null && context.mounted) {
            context
                .read<AIPromptInputBloc>()
                .add(AIPromptInputEvent.attachFile(file.path!, file.name));
          }
        }
      },
    );
  }

  Widget _sendButton() {
    return PromptInputSendButton(
      buttonSize: DesktopAIPromptSizes.actionBarHeight,
      iconSize: DesktopAIPromptSizes.sendButtonSize,
      state: sendButtonState,
      onSendPressed: onSendPressed,
      onStopStreaming: onStopStreaming,
    );
  }
}
